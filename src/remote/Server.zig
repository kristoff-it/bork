const Server = @This();

const std = @import("std");
const Io = std.Io;
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
    links: std.Io.net.Stream,
    send: []const u8,
    afk: struct {
        title: []const u8,
        target_time: Io.Timestamp,
        reason: []const u8,
    },
};

auth: Network.Auth,
listener: std.Io.net.Server,
io: Io,
gpa: std.mem.Allocator,
ch: *vaxis.Loop(GlobalEventUnion),
thread: std.Thread,

pub fn init(
    self: *Server,
    io: std.Io,
    alloc: std.mem.Allocator,
    environ: *std.process.Environ.Map,
    auth: Network.Auth,
    ch: *vaxis.Loop(GlobalEventUnion),
) !void {
    self.gpa = alloc;
    self.auth = auth;
    self.ch = ch;

    const tmp_dir_path = try folders.getPath(io, alloc, environ, .cache) orelse "/tmp";
    const socket_path = try std.fmt.allocPrint(
        alloc,
        "{s}/bork.sock",
        .{tmp_dir_path},
    );

    std.Io.Dir.cwd().deleteFile(io, socket_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    const address: std.Io.net.UnixAddress = try .init(socket_path);
    self.listener = try address.listen(io, .{});

    errdefer self.listener.deinit(io);

    self.thread = try std.Thread.spawn(.{}, start, .{self});
}

pub fn start(self: *Server) !void {
    const io = self.io;
    defer self.listener.deinit(io);
    var buf: [128]u8 = undefined;

    while (true) {
        const conn = try self.listener.accept(io);
        var r = conn.reader(io, &buf);

        const cmd: []u8 = r.interface.takeDelimiterExclusive('\n') catch |err| {
            std.log.debug("remote could not read: {}", .{err});
            return;
        };

        defer if (!std.mem.eql(u8, cmd, "LINKS")) conn.close(io);

        self.handle(conn, cmd) catch |err| {
            log.err("Error while handling remote command: {s}", .{@errorName(err)});
        };
    }
}

pub fn deinit(self: *Server) void {
    const io = self.io;
    std.log.debug("deiniting Remote Server", .{});
    self.listener.deinit(io);
    std.log.debug("deinit done", .{});
}

fn handle(self: *Server, stream: Io.net.Stream, cmd: []const u8) !void {
    defer std.log.debug("remote cmd: {s}", .{cmd});

    const io = self.io;
    const gpa = self.gpa;
    var stream_reader_buffer: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &stream_reader_buffer);

    if (std.mem.eql(u8, cmd, "SEND")) {
        const msg: []u8 = stream_reader.interface.takeDelimiterExclusive('\n') catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        std.log.debug("remote msg: {s}", .{msg});

        // Since sending the message from the main connection
        // makes it so that twitch doesn't echo it back, we're
        // opening a one-off connection to send the message.
        // This way we don't have to implement locally emote
        // parsing.
        var twitch_conn = Network.connect(
            io,
            self.auth.twitch.login,
            self.auth.twitch.token,
        ) catch return;
        defer twitch_conn.close(io);
        var wbuf: [64]u8 = undefined;
        var w = twitch_conn.writer(io, &wbuf);
        w.interface.print("PRIVMSG #{s} :{s}\n", .{
            self.auth.twitch.login,
            msg,
        }) catch return;
        w.interface.flush() catch return;
    }

    if (std.mem.eql(u8, cmd, "QUIT")) {
        try self.ch.postEvent(GlobalEventUnion{ .remote = .quit });
    } else if (std.mem.eql(u8, cmd, "RECONNECT")) {
        try self.ch.postEvent(GlobalEventUnion{ .remote = .reconnect });
    } else if (std.mem.eql(u8, cmd, "LINKS")) {
        try self.ch.postEvent(GlobalEventUnion{ .remote = .{ .links = stream } });
    } else if (std.mem.eql(u8, cmd, "BAN")) {
        const user = stream_reader.interface.takeDelimiterExclusive('\n') catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        std.log.debug("remote msg: {s}", .{user});

        // Since sending the message from the main connection
        // makes it so that twitch doesn't echo it back, we're
        // opening a one-off connection to send the message.
        // This way we don't have to implement locally emote
        // parsing.
        var twitch_conn = Network.connect(
            io,
            self.auth.twitch.login,
            self.auth.twitch.token,
        ) catch return;
        defer twitch_conn.close(io);
        var wbuf: [64]u8 = undefined;
        var w = twitch_conn.writer(io, &wbuf);
        w.interface.print("PRIVMSG #{s} :/ban {s}\n", .{
            self.auth.twitch.login,
            user,
        }) catch return;
        w.interface.flush() catch return;
    } else if (std.mem.eql(u8, cmd, "YT")) {
        const video_id = stream_reader.interface.takeDelimiterExclusive('\n') catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        const url_fmt = "https://www.googleapis.com/youtube/v3/liveBroadcasts?id={s}&part=id,snippet,status";

        var yt: std.http.Client = .{
            .io = io,
            .allocator = self.gpa,
        };
        defer yt.deinit();

        const live_url = try std.fmt.allocPrint(self.gpa, url_fmt, .{video_id});
        defer self.gpa.free(live_url);

        var response_writer: Io.Writer.Allocating = .init(gpa);
        defer response_writer.deinit();

        const res = try yt.fetch(.{
            .location = .{ .url = live_url },
            .method = .GET,
            .response_writer = &response_writer.writer,
            .extra_headers = &.{
                .{ .name = "Authorization", .value = self.auth.youtube.token.access },
            },
        });

        var wbuf: [128]u8 = undefined;
        var w = stream.writer(io, &wbuf);

        const live_buf = response_writer.written();
        if (res.status != .ok) {
            try w.interface.print("Error while fetching livestream details: {} \n{s}\n\n", .{
                res.status, live_buf,
            });
            try w.interface.flush();
            return;
        }

        const lives = std.json.parseFromSlice(livechat.LiveBroadcasts, self.gpa, live_buf, .{
            .ignore_unknown_fields = true,
        }) catch {
            try w.interface.print("Error while parsing livestream details.\n", .{});
            try w.interface.flush();
            return;
        };

        defer lives.deinit();

        const chat_id = for (lives.value.items) |l| {
            if (std.mem.eql(u8, l.status.lifeCycleStatus, "live")) break try self.gpa.dupeZ(u8, l.snippet.liveChatId);
        } else {
            try w.interface.print("The provided livestream does not seem to be live.\n", .{});
            try w.interface.flush();
            return;
        };

        try w.interface.print("Success!\n", .{});
        try w.interface.flush();

        const maybe_old = @atomicRmw(?[*:0]const u8, &livechat.new_chat_id, .Xchg, chat_id, .acq_rel);
        if (maybe_old) |m| self.gpa.free(std.mem.span(m));
    } else if (std.mem.eql(u8, cmd, "UNBAN")) {
        const user = stream_reader.interface.takeDelimiterExclusive('\n') catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        std.log.debug("remote msg: {s}", .{user});

        // Since sending the message from the main connection
        // makes it so that twitch doesn't echo it back, we're
        // opening a one-off connection to send the message.
        // This way we don't have to implement locally emote
        // parsing.
        var twitch_conn = Network.connect(
            io,
            self.auth.twitch.login,
            self.auth.twitch.token,
        ) catch return;
        defer twitch_conn.close(io);
        var wbuf: [64]u8 = undefined;
        var w = twitch_conn.writer(io, &wbuf);
        w.interface.print("PRIVMSG #{s} :/ban {s}\n", .{
            self.auth.twitch.login,
            user,
        }) catch return;
        w.interface.flush() catch return;
    } else if (std.mem.eql(u8, cmd, "AFK")) {
        var reader = stream_reader.interface;
        var aw: Io.Writer.Allocating = .init(gpa);
        defer aw.deinit();
        const time_string: []u8 = blk: {
            _ = reader.streamDelimiter(&aw.writer, '\n') catch |err| {
                std.log.debug("remote could read: {}", .{err});
                return;
            };
            reader.toss(1); // \n
            const result = aw.toOwnedSlice() catch |err| switch (err) {
                error.OutOfMemory => {
                    std.log.err("out of memory: {}", .{err});
                    return;
                }
            };
            break :blk result;
        };
        defer gpa.free(time_string);

        const parsed_time = parseTime(time_string) catch {
            std.log.debug("remote failed to parse time", .{});
            return;
        };

        std.log.debug("parsed_time in seconds: {d}", .{parsed_time});

        const target_time = Io.Timestamp.now(io, .real).addDuration(.fromSeconds(parsed_time));

        const reason: []u8 = blk: {
            _ = reader.streamDelimiter(&aw.writer, '\n') catch |err| {
                std.log.debug("remote could read: {}", .{err});
                return;
            };
            reader.toss(1); // \n
            const result = aw.toOwnedSlice() catch |err| switch (err) {
                error.OutOfMemory => {
                    std.log.err("out of memory: {}", .{err});
                    return;
                }
            };
            break :blk result;
        };
        errdefer self.gpa.free(reason);

        for (reason) |c| switch (c) {
            else => {},
            '\n', '\r', '\t' => return error.BadReason,
        };

        const title: []u8 = blk: {
            _ = reader.streamDelimiter(&aw.writer, '\n') catch |err| {
                std.log.debug("remote could read: {}", .{err});
                return;
            };
            reader.toss(1); // \n
            const result = aw.toOwnedSlice() catch |err| switch (err) {
                error.OutOfMemory => {
                    std.log.err("out of memory: {}", .{err});
                    return;
                }
            };
            break :blk result;
        };

        errdefer self.gpa.free(title);

        for (title) |c| switch (c) {
            else => {},
            '\n', '\r', '\t' => return error.BadReason,
        };

        try self.ch.postEvent(GlobalEventUnion{
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
pub fn replyLinks(io: Io, chat: *Chat, stream: Io.net.Stream) void {
    var maybe_current = chat.last_link_message;
    var wbuf: [1024]u8 = undefined;
    var w = stream.writer(io, &wbuf);
    while (maybe_current) |c| : (maybe_current = c.prev_links) {
        const text = switch (c.kind) {
            .chat => |comment| comment.text,
            else => continue,
        };
        var it = std.mem.tokenizeScalar(u8, text, ' ');
        while (it.next()) |word| {
            if (url.sense(word)) {
                const indent = "   >>";
                w.interface.print("{s} [{s}]\n{s} {s}\n\n", .{
                    c.time,
                    c.login_name,
                    indent,
                    url.clean(word),
                }) catch return;
            }
        }
    }

    w.interface.flush() catch return;

    stream.close(io);
}
