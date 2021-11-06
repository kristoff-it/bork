const std = @import("std");
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

pub fn send(alloc: *std.mem.Allocator, config: BorkConfig, it: *std.process.ArgIterator) !void {
    const message = try (it.next(alloc) orelse {
        std.debug.print("Usage ./bork send \"my message Kappa\"\n", .{});
        return;
    });

    const conn = connect(alloc, config.remote_port);
    defer conn.close();

    try conn.writer().writeAll("SEND\n");
    try conn.writer().writeAll(message);
    try conn.writer().writeAll("\n");
}

pub fn quit(alloc: *std.mem.Allocator, config: BorkConfig, it: *std.process.ArgIterator) !void {
    // TODO: validation
    _ = it;

    const conn = connect(alloc, config.remote_port);
    defer conn.close();

    try conn.writer().writeAll("QUIT\n");
}

pub fn links(alloc: *std.mem.Allocator, config: BorkConfig, it: *std.process.ArgIterator) !void {
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

pub fn ban(alloc: *std.mem.Allocator, config: BorkConfig, it: *std.process.ArgIterator) !void {
    const user = try (it.next(alloc) orelse {
        std.debug.print("Usage ./bork ban \"username\"\n", .{});
        return;
    });

    const conn = connect(alloc, config.remote_port);
    defer conn.close();

    try conn.writer().writeAll("BAN\n");
    try conn.writer().writeAll(user);
    try conn.writer().writeAll("\n");
}

pub fn unban(alloc: *std.mem.Allocator, config: BorkConfig, it: *std.process.ArgIterator) !void {
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

pub fn afk(alloc: *std.mem.Allocator, config: BorkConfig, it: *std.process.ArgIterator) !void {
    const time = try (it.next(alloc) orelse {
        std.debug.print(
            \\Usage ./bork afk time ["reason"]
            \\
        , .{});
        return;
    });

    const reason = if (it.next(alloc)) |arg| try arg else null;
    if (reason) |r| {
        for (r) |c| switch (c) {
            else => {},
            '\n', '\r', '\t' => {
                std.debug.print(
                    \\Usage ./bork afk time ["reason"]
                    \\Reason cannot contain newlines 
                    \\(uness you want to PR the feature yourself)
                    \\
                , .{});
                return;
            },
        };
    }

    const parsed_time = parseTime(time);

    if (parsed_time) |_| {
        if (it.next(alloc)) |_| {
            std.debug.print(
                \\Usage ./bork afk time ["reason"]
                \\
            , .{});
            return;
        }

        const conn = connect(alloc, config.remote_port);
        defer conn.close();

        try conn.writer().writeAll("AFK\n");
        try conn.writer().writeAll(time);
        try conn.writer().writeAll("\n");
        if (reason) |r| try conn.writer().writeAll(r);
        try conn.writer().writeAll("\n");
    } else |_| {
        std.debug.print(
            \\Usage ./bork afk time ["reason"]
            \\`time` can be expressed in human readable form. 
            \\E.g.: 5m, 1h, 1h15m, 60s
            \\
        , .{});
        return;
    }
}
