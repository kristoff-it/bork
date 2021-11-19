const std = @import("std");
const clap = @import("clap");
const Event = @import("../remote.zig").Event;
const BorkConfig = @import("../main.zig").BorkConfig;
const parseTime = @import("./utils.zig").parseTime;

fn connect(alloc: *std.mem.Allocator, port: u16) std.net.Stream {
    return std.net.tcpConnectToHost(alloc, "127.0.0.1", port) catch |err| switch (err) {
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

pub fn send(alloc: *std.mem.Allocator, config: BorkConfig, it: *clap.args.OsIterator) !void {
    const message = (try it.next()) orelse {
        std.debug.print("Usage ./bork send \"my message Kappa\"\n", .{});
        return;
    };

    const conn = connect(alloc, config.remote_port);
    defer conn.close();

    try conn.writer().writeAll("SEND\n");
    try conn.writer().writeAll(message);
    try conn.writer().writeAll("\n");
}

pub fn quit(alloc: *std.mem.Allocator, config: BorkConfig, it: *clap.args.OsIterator) !void {
    _ = it;
    const conn = connect(alloc, config.remote_port);
    defer conn.close();

    try conn.writer().writeAll("QUIT\n");
}

pub fn links(alloc: *std.mem.Allocator, config: BorkConfig, it: *clap.args.OsIterator) !void {
    // TODO: validation
    _ = it;

    const conn = connect(alloc, config.remote_port);
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

pub fn ban(alloc: *std.mem.Allocator, config: BorkConfig, it: *clap.args.OsIterator) !void {
    const user = (try it.next()) orelse {
        std.debug.print("Usage ./bork ban \"username\"\n", .{});
        return;
    };

    const conn = connect(alloc, config.remote_port);
    defer conn.close();

    try conn.writer().writeAll("BAN\n");
    try conn.writer().writeAll(user);
    try conn.writer().writeAll("\n");
}

pub fn unban(alloc: *std.mem.Allocator, config: BorkConfig, it: *clap.args.OsIterator) !void {
    const user = try it.next(alloc);

    if (try it.next(alloc)) |_| {
        std.debug.print(
            \\Usage ./bork unban ["username"]
            \\Omitting <username> will try to unban the last banned 
            \\user in the current session. 
            \\
        , .{});
        return;
    }

    const conn = connect(alloc, config.remote_port);
    defer conn.close();

    try conn.writer().writeAll("UNBAN\n");
    try conn.writer().writeAll(user);
    try conn.writer().writeAll("\n");
}

pub fn afk(alloc: *std.mem.Allocator, config: BorkConfig, it: *clap.args.OsIterator) !void {
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
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help             display this help message") catch unreachable,
        clap.parseParam("-t, --title <TITLE>    changes the title shown, defaults to 'AFK'") catch unreachable,
        clap.parseParam("<TIMER>                the countdown timer, eg: '1h25m' or '500s'") catch unreachable,
        clap.parseParam("<REASON>               the reason for being afk, eg: 'dinner'") catch unreachable,
    };

    var diag: clap.Diagnostic = undefined;
    var args = clap.parseEx(clap.Help, &params, it, .{
        .allocator = alloc,
        .diagnostic = &diag,
    }) catch |err| {
        // Report any useful error and exit
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };

    const positionals = args.positionals();
    const pos_ok = positionals.len > 0 and positionals.len < 3;
    if (args.flag("-h") or args.flag("--help") or !pos_ok) {
        std.debug.print("{s}\n", .{summary});
        clap.help(std.io.getStdErr().writer(), &params) catch {};
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

    const title = args.option("--title");
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

    std.debug.print("timer: {s}, reason: {s}, title: {s}\n", .{ time, reason, title });

    const conn = connect(alloc, config.remote_port);
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
