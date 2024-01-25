const std = @import("std");
const folders = @import("known-folders");
const ArgIterator = std.process.ArgIterator;
const clap = @import("clap");
const Event = @import("../remote.zig").Event;
const Config = @import("../Config.zig");
const parseTime = @import("./utils.zig").parseTime;

fn connect(gpa: std.mem.Allocator) std.net.Stream {
    const tmp_dir_path = (folders.getPath(gpa, .cache) catch @panic("oom")) orelse "/tmp";
    defer gpa.free(tmp_dir_path);

    const socket_path = std.fmt.allocPrint(
        gpa,
        "{s}/bork.sock",
        .{tmp_dir_path},
    ) catch @panic("oom");
    defer gpa.free(socket_path);

    return std.net.connectUnixSocket(socket_path) catch |err| switch (err) {
        error.ConnectionRefused => {
            std.debug.print(
                \\Connection refused!
                \\Is Bork running?
                \\
            , .{});
            std.os.exit(1);
        },
        else => {
            std.debug.print(
                \\Unexpected error: {}
                \\
            , .{err});
            std.os.exit(1);
        },
    };
}

pub fn send(gpa: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const message = it.next() orelse {
        std.debug.print("Usage ./bork send \"my message Kappa\"\n", .{});
        return;
    };

    const conn = connect(gpa);
    defer conn.close();

    try conn.writer().writeAll("SEND\n");
    try conn.writer().writeAll(message);
    try conn.writer().writeAll("\n");
}

pub fn quit(gpa: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    _ = it;
    const conn = connect(gpa);
    defer conn.close();

    try conn.writer().writeAll("QUIT\n");
}

pub fn reconnect(gpa: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    // TODO: validation
    _ = it;

    const conn = connect(gpa);
    defer conn.close();

    try conn.writer().writeAll("RECONNECT\n");
}

pub fn links(gpa: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    // TODO: validation
    _ = it;

    const conn = connect(gpa);
    defer conn.close();

    try conn.writer().writeAll("LINKS\n");

    std.debug.print("Latest links (not sent by you)\n\n", .{});

    var buf: [100]u8 = undefined;
    var n = try conn.read(&buf);

    const out = std.io.getStdOut();
    while (n != 0) : (n = try conn.read(&buf)) {
        try out.writeAll(buf[0..n]);
    }
}

pub fn ban(gpa: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const user = it.next() orelse {
        std.debug.print("Usage ./bork ban \"username\"\n", .{});
        return;
    };

    const conn = connect(gpa);
    defer conn.close();

    try conn.writer().writeAll("BAN\n");
    try conn.writer().writeAll(user);
    try conn.writer().writeAll("\n");
}

pub fn unban(gpa: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const user = try it.next(gpa);

    if (it.next(gpa)) |_| {
        std.debug.print(
            \\Usage ./bork unban ["username"]
            \\Omitting <username> will try to unban the last banned
            \\user in the current session.
            \\
        , .{});
        return;
    }

    const conn = connect(gpa);
    defer conn.close();

    try conn.writer().writeAll("UNBAN\n");
    try conn.writer().writeAll(user);
    try conn.writer().writeAll("\n");
}

pub fn afk(gpa: std.mem.Allocator, it: *std.process.ArgIterator) !void {
    const summary =
        \\Creates an AFK message with a countdown.
        \\Click on the message to dismiss it.
        \\
        \\Usage: bork afk TIMER [REASON] [-t TITLE]
        \\
        \\TIMER:  the countdown timer, eg: '1h25m' or '500s'
        \\REASON: the reason for being afk, eg: 'dinner'
        \\
    ;
    const params = comptime clap.parseParamsComptime(
        \\-h, --help           display this help message
        \\-t, --title <TITLE>  changes the title shown, defaults to 'AFK'
        \\<TIMER>              the countdown timer, eg: '1h25m' or '500s'
        \\<MSG>                the reason for being afk, eg: 'dinner'
        \\
    );

    const parsers = .{
        .TITLE = clap.parsers.string,
        .MSG = clap.parsers.string,
        .TIMER = clap.parsers.string,
    };

    var diag: clap.Diagnostic = undefined;
    const res = clap.parseEx(clap.Help, &params, parsers, it, .{
        .allocator = gpa,
        .diagnostic = &diag,
    }) catch |err| {
        // Report any useful error and exit
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };

    const positionals = res.positionals;
    const pos_ok = positionals.len > 0 and positionals.len < 3;
    if (res.args.help != 0 or !pos_ok) {
        std.debug.print("{s}\n", .{summary});
        clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{}) catch {};
        std.debug.print("\n", .{});
        return;
    }

    const time = positionals[0];
    _ = parseTime(time) catch {
        std.debug.print(
            \\Bad timer!
            \\Format: 1h15m, 60s, 7m
            \\
        , .{});
        return;
    };

    const reason = if (positionals.len == 2) positionals[1] else null;
    if (reason) |r| {
        for (r) |c| switch (c) {
            else => {},
            '\n', '\r', '\t' => {
                std.debug.print(
                    \\Reason cannot contain newlines!
                    \\
                , .{});
                return;
            },
        };
    }

    const title = res.args.title;
    if (title) |t| {
        for (t) |c| switch (c) {
            else => {},
            '\n', '\r', '\t' => {
                std.debug.print(
                    \\Title cannot contain newlines!
                    \\
                , .{});
                return;
            },
        };
    }

    std.debug.print("timer: {s}, reason: {?s}, title: {?s}\n", .{ time, reason, title });

    const conn = connect(gpa);
    defer conn.close();

    const w = conn.writer();

    try w.writeAll("AFK\n");
    try w.writeAll(time);
    try w.writeAll("\n");
    if (reason) |r| try w.writeAll(r);
    try conn.writer().writeAll("\n");
    if (title) |t| try w.writeAll(t);
    try conn.writer().writeAll("\n");
}
