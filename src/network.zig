const std = @import("std");

pub const Event = struct {
    msg: []const u8,
};

sock: std.fs.File,
reader: std.fs.File.Reader,
writer: std.fs.File.Writer,
name: []const u8,
oauth: []const u8,

const Self = @This();
pub fn init(alloc: *std.mem.Allocator, name: []const u8, oauth: []const u8) !Self {
    var socket = try connect(alloc, name, oauth);
    return Self{
        .socket = socket,
        .reader = socket.reader(),
        .writer = socket.writer(),
    };
}

fn connect(alloc: *std.mem.Allocator, name: []const u8, oauth: []const u8) !std.fs.File {
    var socket = try std.net.tcpConnectToHost(alloc, "irc.chat.twitch.tv", 6667);
    errdefer self.socket.close();

    try socket.writer().print(
        \\PASS {0}
        \\NICK {1}
        \\CAP REQ :twitch.tv/tags
        \\CAP REQ :twitch.tv/commands
        \\JOIN #{1}
        \\
    , .{ auth, nick });

    return socket;
}


