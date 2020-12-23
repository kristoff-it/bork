const std = @import("std");
const options = @import("build_options");
const Channel = @import("utils/channel.zig").Channel;
const Network = @import("Network.zig");
const Terminal = @import("Terminal.zig");
const Chat = @import("Chat.zig");

pub const io_mode = .evented;

var log: std.fs.File.Writer = undefined;

pub const Event = union(enum) {
    display: Terminal.Event,
    network: Network.Event,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = &gpa.allocator;
    const nick = nick: {
        var it = std.process.ArgIterator.init();
        var exe_name = try (it.next(alloc) orelse @panic("no executable name as first argument!?")); // burn exe name
        defer alloc.free(exe_name);

        break :nick try (it.next(alloc) orelse {
            std.debug.print("Usage: ./twitch-chat your_channel_name\n", .{});
            return;
        });
    };

    const auth = std.os.getenv("TWITCH_OAUTH") orelse @panic("missing TWITCH_OAUTH env variable");
    if (!std.mem.startsWith(u8, auth, "oauth:"))
        @panic("TWITCH_OAUTH needs to start with 'oauth:'");

    var l = try std.fs.cwd().createFile("twitch-chat2.log", .{ .truncate = true, .intended_io_mode = .blocking });
    log = l.writer();

    var buf: [24]Event = undefined;
    var ch = Channel(Event).init(&buf);

    var display = try Terminal.init(alloc, log, &ch);
    defer display.deinit();

    var network: Network = undefined;
    try network.init(alloc, &ch, log, nick, auth);

    var chat = Chat{ .allocator = alloc, .log = log };

    // Initial paint!
    try display.renderChat(&chat);

    // Main control loop
    var chaos = false;
    while (true) {
        var need_repaint = false;

        const event = ch.get();
        switch (event) {
            .display => |de| {
                switch (de) {
                    // TODO: SIGWINCH is disabled because of
                    //       rendering bugs. Re-enable .calm
                    //       and .chaos when restoring resize
                    //       signal support
                    .chaos => {
                        // chaos = true;
                    },
                    .calm => {
                        // chaos = false;
                        // try display.sizeChanged();
                        // need_repaint = true;
                    },
                    .other => |c| {
                        if (c[0] == 'r' or c[0] == 'R') {
                            log.writeAll("[key] R\n") catch unreachable;
                            try display.sizeChanged();
                            need_repaint = true;
                            chaos = false;
                        }
                    },
                    .up => {
                        need_repaint = chat.scroll(.up, 1);
                    },
                    .down => {
                        need_repaint = chat.scroll(.down, 1);
                    },
                    .right, .left, .tick, .escape => {},
                }
            },
            .network => |ne| switch (ne) {
                .connected => {},
                .disconnected => {
                    try chat.setConnectionStatus(.disconnected);
                    need_repaint = true;
                },
                .reconnected => {
                    try chat.setConnectionStatus(.reconnected);
                    need_repaint = true;
                },
                .message => |m| {
                    log.writeAll("got msg!\n") catch unreachable;

                    // Terminal wants to pre-render the message
                    // and keep a small buffer attached to the message
                    // as a form of caching.
                    const msg = try display.prepareMessage(m);
                    need_repaint = chat.addMessage(msg);
                },
            },
        }

        if (need_repaint and !chaos) {
            try display.renderChat(&chat);
        }
    }

    // TODO: implement real cleanup
}
