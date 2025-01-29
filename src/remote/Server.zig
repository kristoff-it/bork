const Server = @This();

const std = @import("std");
const builtin = @import("builtin");
const folders = @import("known-folders");
const vaxis = @import("vaxis");

const url = @import("../utils/url.zig");
const GlobalEventUnion = @import("../main.zig").Event;
const Chat = @import("../Chat.zig");
const Network = @import("../Network.zig");
const livechat = @import("../network/youtube/livechat.zig");
const parseTime = @import("./utils.zig").parseTime;

const log = std.log.scoped(.server);

pub const Event = union(enum) {
    quit,
    reconnect,
    links: std.net.Stream,
    send: []const u8,
    afk: struct {
        title: []const u8,
        target_time: i64,
        reason: []const u8,
    },
};

auth: Network.Auth,
listener: std.net.Server,
gpa: std.mem.Allocator,
ch: *vaxis.Loop(GlobalEventUnion),
thread: std.Thread,

pub fn init(
    self: *Server,
    alloc: std.mem.Allocator,
    auth: Network.Auth,
    ch: *vaxis.Loop(GlobalEventUnion),
) !void {
    self.gpa = alloc;
    self.auth = auth;
    self.ch = ch;

    const tmp_dir_path = try folders.getPath(alloc, .cache) orelse "/tmp";
    const socket_path = try std.fmt.allocPrint(
        alloc,
        "{s}/bork.sock",
        .{tmp_dir_path},
    );

    std.fs.cwd().deleteFile(socket_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    const address = try std.net.Address.initUnix(socket_path);
    self.listener = try address.listen(.{
        .reuse_address = builtin.target.os.tag != .windows,
        .reuse_port = builtin.target.os.tag != .windows,
    });

    errdefer self.listener.deinit();

    self.thread = try std.Thread.spawn(.{}, start, .{self});
}

pub fn start(self: *Server) !void {
    defer self.listener.deinit();

    while (true) {
        const conn = try self.listener.accept();
        defer conn.stream.close();
        self.handle(conn.stream) catch |err| {
            log.err("Error while handling remote command: {s}", .{@errorName(err)});
        };
    }
}

pub fn deinit(self: *Server) void {
    std.log.debug("deiniting Remote Server", .{});
    std.posix.shutdown(self.listener.stream.handle, .both) catch |err| {
        std.log.debug("remote shutdown encountered an error: {}", .{err});
    };
    std.log.debug("deinit done", .{});
}

fn handle(self: *Server, stream: std.net.Stream) !void {
    var buf: [100]u8 = undefined;

    const cmd = stream.reader().readUntilDelimiter(&buf, '\n') catch |err| {
        std.log.debug("remote could read: {}", .{err});
        return;
    };
    defer std.log.debug("remote cmd: {s}", .{cmd});

    if (std.mem.eql(u8, cmd, "SEND")) {
        const msg = stream.reader().readUntilDelimiterAlloc(self.gpa, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };
        defer self.gpa.free(msg);

        std.log.debug("remote msg: {s}", .{msg});

        // Since sending the message from the main connection
        // makes it so that twitch doesn't echo it back, we're
        // opening a one-off connection to send the message.
        // This way we don't have to implement locally emote
        // parsing.
        var twitch_conn = Network.connect(
            self.gpa,
            self.auth.twitch.login,
            self.auth.twitch.token,
        ) catch return;
        defer twitch_conn.close();
        twitch_conn.writer().print("PRIVMSG #{s} :{s}\n", .{
            self.auth.twitch.login,
            msg,
        }) catch return;
    }

    if (std.mem.eql(u8, cmd, "QUIT")) {
        self.ch.postEvent(GlobalEventUnion{ .remote = .quit });
    }

    if (std.mem.eql(u8, cmd, "RECONNECT")) {
        self.ch.postEvent(GlobalEventUnion{ .remote = .reconnect });
    }

    if (std.mem.eql(u8, cmd, "LINKS")) {
        self.ch.postEvent(GlobalEventUnion{ .remote = .{ .links = stream } });
    }

    if (std.mem.eql(u8, cmd, "BAN")) {
        const user = stream.reader().readUntilDelimiterAlloc(self.gpa, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        defer self.gpa.free(user);

        std.log.debug("remote msg: {s}", .{user});

        // Since sending the message from the main connection
        // makes it so that twitch doesn't echo it back, we're
        // opening a one-off connection to send the message.
        // This way we don't have to implement locally emote
        // parsing.
        var twitch_conn = Network.connect(
            self.gpa,
            self.auth.twitch.login,
            self.auth.twitch.token,
        ) catch return;
        defer twitch_conn.close();
        twitch_conn.writer().print("PRIVMSG #{s} :/ban {s}\n", .{
            self.auth.twitch.login,
            user,
        }) catch return;
    }

    if (std.mem.eql(u8, cmd, "YT")) {
        const video_id = stream.reader().readUntilDelimiterAlloc(self.gpa, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };
        defer self.gpa.free(video_id);

        const url_fmt = "https://www.googleapis.com/youtube/v3/liveBroadcasts?id={s}&part=id,snippet,status";

        var yt: std.http.Client = .{
            .allocator = self.gpa,
        };
        defer yt.deinit();

        const live_url = try std.fmt.allocPrint(self.gpa, url_fmt, .{video_id});
        defer self.gpa.free(live_url);

        var live_buf = std.ArrayList(u8).init(self.gpa);
        defer live_buf.deinit();

        const res = try yt.fetch(.{
            .location = .{ .url = live_url },
            .method = .GET,
            .response_storage = .{ .dynamic = &live_buf },
            .extra_headers = &.{
                .{ .name = "Authorization", .value = self.auth.youtube.token.access },
            },
        });

        const w = stream.writer();

        if (res.status != .ok) {
            try w.print("Error while fetching livestream details: {} \n{s}\n\n", .{
                res.status, live_buf.items,
            });
            return;
        }

        const lives = std.json.parseFromSlice(livechat.LiveBroadcasts, self.gpa, live_buf.items, .{
            .ignore_unknown_fields = true,
        }) catch {
            try w.print("Error while parsing livestream details.\n", .{});
            return;
        };

        defer lives.deinit();

        const chat_id = for (lives.value.items) |l| {
            if (std.mem.eql(u8, l.status.lifeCycleStatus, "live")) break try self.gpa.dupeZ(u8, l.snippet.liveChatId);
        } else {
            try w.print("The provided livestream does not seem to be live.\n", .{});
            return;
        };

        try w.print("Success!\n", .{});

        const maybe_old = @atomicRmw(?[*:0]const u8, &livechat.new_chat_id, .Xchg, chat_id, .acq_rel);
        if (maybe_old) |m| self.gpa.free(std.mem.span(m));
    }

    if (std.mem.eql(u8, cmd, "UNBAN")) {
        const user = stream.reader().readUntilDelimiterAlloc(self.gpa, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };
        defer self.gpa.free(user);

        std.log.debug("remote msg: {s}", .{user});

        // Since sending the message from the main connection
        // makes it so that twitch doesn't echo it back, we're
        // opening a one-off connection to send the message.
        // This way we don't have to implement locally emote
        // parsing.
        var twitch_conn = Network.connect(
            self.gpa,
            self.auth.twitch.login,
            self.auth.twitch.token,
        ) catch return;
        defer twitch_conn.close();
        twitch_conn.writer().print("PRIVMSG #{s} :/ban {s}\n", .{
            self.auth.twitch.login,
            user,
        }) catch return;
    }

    if (std.mem.eql(u8, cmd, "AFK")) {
        const reader = stream.reader();
        const time_string = reader.readUntilDelimiterAlloc(self.gpa, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };
        defer self.gpa.free(time_string);

        const parsed_time = parseTime(time_string) catch {
            std.log.debug("remote failed to parse time", .{});
            return;
        };

        std.log.debug("parsed_time in seconds: {d}", .{parsed_time});

        const target_time = std.time.timestamp() + parsed_time;

        const reason = reader.readUntilDelimiterAlloc(self.gpa, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        errdefer self.gpa.free(reason);

        for (reason) |c| switch (c) {
            else => {},
            '\n', '\r', '\t' => return error.BadReason,
        };

        const title = reader.readUntilDelimiterAlloc(self.gpa, '\n', 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        errdefer self.gpa.free(title);

        for (title) |c| switch (c) {
            else => {},
            '\n', '\r', '\t' => return error.BadReason,
        };

        self.ch.postEvent(GlobalEventUnion{
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
pub fn replyLinks(chat: *Chat, stream: std.net.Stream) void {
    var maybe_current = chat.last_link_message;
    while (maybe_current) |c| : (maybe_current = c.prev_links) {
        const text = switch (c.kind) {
            .chat => |comment| comment.text,
            else => continue,
        };
        var it = std.mem.tokenizeScalar(u8, text, ' ');
        while (it.next()) |word| {
            if (url.sense(word)) {
                const indent = "   >>";
                stream.writer().print("{s} [{s}]\n{s} {s}\n\n", .{
                    c.time,
                    c.login_name,
                    indent,
                    url.clean(word),
                }) catch return;
            }
        }
    }

    stream.close();
}
