const std = @import("std");

pub const io_mode = .evented;

pub fn main() !void {
    const auth = std.os.getenv("TWITCH_OAUTH") orelse @panic("missing twitch auth");
    if (!std.mem.startsWith(u8, auth, "oauth:"))
        @panic("TWITCH_OAUTH needs to start with 'oauth:'");

    const nick = "kristoff_it";

    var socket = try std.net.tcpConnectToHost(std.heap.page_allocator, "irc.chat.twitch.tv", 6667);
    defer socket.close();

    var reader = socket.reader();
    var writer = socket.writer();

    try writer.print(
        \\PASS {0}
        \\NICK {1}
        \\CAP REQ :twitch.tv/tags
        \\CAP REQ :twitch.tv/commands
        \\JOIN #{1}
        \\
    , .{ auth, nick });

    var buf: [1024]u8 = undefined;
    while (true) {
        const msg = reader.readUntilDelimiterOrEof(&buf, '\n');
        std.debug.print("{}\n", .{msg});
    }
}

const TwitchMessage = struct {};
