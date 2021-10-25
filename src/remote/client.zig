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
}
