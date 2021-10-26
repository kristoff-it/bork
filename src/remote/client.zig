const std = @import("std");
const Event = @import("../remote.zig").Event;
const BorkConfig = @import("../main.zig").BorkConfig;

pub fn send(alloc: *std.mem.Allocator, config: BorkConfig, it: *std.process.ArgIterator) !void {
    const message = try (it.next(alloc) orelse {
        std.debug.print("Usage ./bork send \"my message Kappa\"\n", .{});
        return;
    });

    const conn = try std.net.tcpConnectToHost(alloc, "127.0.0.1", config.remote_port);
    defer conn.close();

    try conn.writer().writeAll("SEND\n");
    try conn.writer().writeAll(message);
    try conn.writer().writeAll("\n");
}

pub fn quit(alloc: *std.mem.Allocator, config: BorkConfig, it: *std.process.ArgIterator) !void {
    // TODO: validation
    _ = it;

    const conn = try std.net.tcpConnectToHost(alloc, "127.0.0.1", config.remote_port);
    defer conn.close();

    try conn.writer().writeAll("QUIT\n");
}

pub fn links(alloc: *std.mem.Allocator, config: BorkConfig, it: *std.process.ArgIterator) !void {
    // TODO: validation
    _ = it;

    const conn = try std.net.tcpConnectToHost(alloc, "127.0.0.1", config.remote_port);
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
