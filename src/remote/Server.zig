const std = @import("std");
const Channel = @import("../utils/channel.zig").Channel;
const url = @import("../utils/url.zig");
const GlobalEventUnion = @import("../main.zig").Event;
const Chat = @import("../Chat.zig");
const BorkConfig = @import("../main.zig").BorkConfig;
const Network = @import("../Network.zig");
const parseTime = @import("./utils.zig").parseTime;

pub const Event = union(enum) {
    quit,
    reconnect,
    links: std.net.StreamServer.Connection,
    send: []const u8,
    afk: struct {
        title: []const u8,
        target_time: i64,
        reason: []const u8,
    },
};

address: std.net.Address,
listener: std.net.StreamServer,
config: BorkConfig,
token: []const u8,
alloc: std.mem.Allocator,
ch: *Channel(GlobalEventUnion),

pub fn init(
    self: *@This(),
    config: BorkConfig,
    token: []const u8,
    alloc: std.mem.Allocator,
    ch: *Channel(GlobalEventUnion),
) !void {
    self.config = config;
    self.token = token;

    self.alloc = alloc;
    self.ch = ch;

    self.address = try std.net.Address.parseIp("127.0.0.1", config.remote_port);

    self.listener = std.net.StreamServer.init(.{
        .reuse_address = true,
    });

    errdefer self.listener.deinit();

    // Start listening in a detached coroutine
    // TODO: since it's only one, this should just be
    //       a normal async call, stage2-san save me pepeHands
    try self.listener.listen(self.address);
    try std.event.Loop.instance.?.runDetached(alloc, listen, .{self});
}

// TODO: concurrency
pub fn deinit(self: *@This()) void {
    std.log.debug("deiniting Remote Server", .{});
    std.os.shutdown(self.listener.sockfd.?, .both) catch |err| {
        std.log.debug("remote shutdown encountered an error: {}", .{err});
    };
    self.listener.deinit();
    std.log.debug("deinit done", .{});
}

fn listen(self: *@This()) void {
    while (true) {
        const conn = self.listener.accept() catch |err| {
            std.log.debug("remote encountered an error: {}", .{err});
            continue;
        };

        // Handle the connection in a detached coroutine
        std.event.Loop.instance.?.runDetached(self.alloc, handle, .{ self, conn }) catch |err| {
            std.log.debug("remote could not handle a connection: {}", .{err});
        };
    }
}

fn handle(self: *@This(), conn: std.net.StreamServer.Connection) void {
    self.erroring_handle(conn) catch {};
}

fn erroring_handle(self: *@This(), conn: std.net.StreamServer.Connection) !void {
    var buf: [100]u8 = undefined;

    const cmd = conn.stream.reader().readUntilDelimiter(&buf, '\n') catch |err| {
        std.log.debug("remote could read: {}", .{err});
        return;
    };
    defer std.log.debug("remote cmd: {s}", .{cmd});

    if (std.mem.eql(u8, cmd, "SEND")) {
        const msg = conn.stream.reader().readUntilDelimiterAlloc(self.alloc, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };
        defer self.alloc.free(msg);

        std.log.debug("remote msg: {s}", .{msg});

        // Since sending the message from the main connection
        // makes it so that twitch doesn't echo it back, we're
        // opening a one-off connection to send the message.
        // This way we don't have to implement locally emote
        // parsing.
        var twitch_conn = Network.connect(self.alloc, self.config.nick, self.token) catch return;
        defer twitch_conn.close();
        twitch_conn.writer().print("PRIVMSG #{s} :{s}\n", .{ self.config.nick, msg }) catch return;
    }

    if (std.mem.eql(u8, cmd, "QUIT")) {
        self.ch.put(GlobalEventUnion{ .remote = .quit });
    }

    if (std.mem.eql(u8, cmd, "RECONNECT")) {
        self.ch.put(GlobalEventUnion{ .remote = .reconnect });
    }

    if (std.mem.eql(u8, cmd, "LINKS")) {
        self.ch.put(GlobalEventUnion{ .remote = .{ .links = conn } });
    }

    if (std.mem.eql(u8, cmd, "BAN")) {
        const user = conn.stream.reader().readUntilDelimiterAlloc(self.alloc, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        defer self.alloc.free(user);

        std.log.debug("remote msg: {s}", .{user});

        // Since sending the message from the main connection
        // makes it so that twitch doesn't echo it back, we're
        // opening a one-off connection to send the message.
        // This way we don't have to implement locally emote
        // parsing.
        var twitch_conn = Network.connect(self.alloc, self.config.nick, self.token) catch return;
        defer twitch_conn.close();
        twitch_conn.writer().print("PRIVMSG #{s} :/ban {s}\n", .{ self.config.nick, user }) catch return;
    }

    if (std.mem.eql(u8, cmd, "UNBAN")) {
        const user = conn.stream.reader().readUntilDelimiterAlloc(self.alloc, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };
        defer self.alloc.free(user);

        std.log.debug("remote msg: {s}", .{user});

        // Since sending the message from the main connection
        // makes it so that twitch doesn't echo it back, we're
        // opening a one-off connection to send the message.
        // This way we don't have to implement locally emote
        // parsing.
        var twitch_conn = Network.connect(self.alloc, self.config.nick, self.token) catch return;
        defer twitch_conn.close();
        twitch_conn.writer().print("PRIVMSG #{s} :/ban {s}\n", .{ self.config.nick, user }) catch return;
    }

    if (std.mem.eql(u8, cmd, "AFK")) {
        const reader = conn.stream.reader();
        const time_string = reader.readUntilDelimiterAlloc(self.alloc, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };
        defer self.alloc.free(time_string);

        const parsed_time = parseTime(time_string) catch {
            std.log.debug("remote failed to parse time", .{});
            return;
        };

        std.log.debug("parsed_time in seconds: {d}", .{parsed_time});

        const target_time = std.time.timestamp() + parsed_time;

        const reason = reader.readUntilDelimiterAlloc(self.alloc, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        errdefer self.alloc.free(reason);

        for (reason) |c| switch (c) {
            else => {},
            '\n', '\r', '\t' => return error.BadReason,
        };

        const title = reader.readUntilDelimiterAlloc(self.alloc, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        errdefer self.alloc.free(title);

        for (title) |c| switch (c) {
            else => {},
            '\n', '\r', '\t' => return error.BadReason,
        };

        self.ch.put(GlobalEventUnion{
            .remote = .{
                .afk = .{
                    .target_time = target_time,
                    .reason = reason,
                    .title = title,
                },
            },
        });
    }
}

// NOTE: this function should only be called by
// the thread that's also running the main control
// loop
pub fn replyLinks(chat: *Chat, conn: std.net.StreamServer.Connection) void {
    var maybe_current = chat.last_link_message;
    while (maybe_current) |c| : (maybe_current = c.prev_links) {
        const text = switch (c.kind) {
            .chat => |comment| comment.text,
            else => continue,
        };
        var it = std.mem.tokenize(u8, text, " ");
        while (it.next()) |word| {
            if (url.sense(word)) {
                const indent = "   >>";
                conn.stream.writer().print("{s} [{s}]\n{s} {s}\n\n", .{
                    c.time,
                    c.login_name,
                    indent,
                    url.clean(word),
                }) catch return;
            }
        }
    }

    conn.stream.close();
}
