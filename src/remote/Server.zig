const std = @import("std");
const Channel = @import("../utils/channel.zig").Channel;
const GlobalEventUnion = @import("../main.zig").Event;

pub const Event = union(enum) {
    close,
    send: []const u8,
};

address: std.net.Address,
listener: std.net.StreamServer,
alloc: *std.mem.Allocator,
ch: *Channel(GlobalEventUnion),

pub fn init(
    self: *@This(),
    port: u16,
    alloc: *std.mem.Allocator,
    ch: *Channel(GlobalEventUnion),
) !void {
    self.address = try std.net.Address.parseIp("127.0.0.1", port);
    self.ch = ch;
    self.alloc = alloc;

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
    self.listener.deinit();
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
    var buf: [100]u8 = undefined;

    const cmd = conn.stream.reader().readUntilDelimiter(&buf, '\n') catch |err| {
        std.log.debug("remote could read: {}", .{err});
        return;
    };

    std.log.debug("remote cmd: {s}", .{cmd});

    if (std.mem.eql(u8, cmd, "SEND")) {
        const msg = conn.stream.reader().readAllAlloc(self.alloc, 4096) catch |err| {
            std.log.debug("remote could read: {}", .{err});
            return;
        };

        std.log.debug("remote msg: {s}", .{msg});
        self.ch.put(GlobalEventUnion{ .remote = .{ .send = msg } });
    }
}
