const std = @import("std");
const options = @import("build_options");
const datetime = @import("datetime");
const clap = @import("clap");
const Channel = @import("utils/channel.zig").Channel;
const senseUserTZ = @import("utils/sense_tz.zig").senseUserTZ;
const Network = @import("Network.zig");
const Terminal = @import("Terminal.zig");
const Chat = @import("Chat.zig");

pub const io_mode = .evented;

var logfile: std.fs.File.Writer = undefined;

pub const Event = union(enum) {
    display: Terminal.Event,
    network: Network.Event,
};

pub fn main() !void {
    var l = try std.fs.cwd().createFile("twitch-chat2.log", .{ .truncate = true, .intended_io_mode = .blocking });
    logfile = l.writer();

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

    var buf: [24]Event = undefined;
    var ch = Channel(Event).init(&buf);

    var display = try Terminal.init(alloc, &ch);
    defer display.deinit();

    var network: Network = undefined;
    try network.init(alloc, &ch, nick, auth, senseUserTZ());

    var chat = Chat{ .allocator = alloc };

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
                        std.log.debug("[key] [{}]", .{c});
                        if (c[0] == 'r' or c[0] == 'R') {
                            try display.sizeChanged();
                            need_repaint = true;
                            chaos = false;
                        }
                    },
                    .up, .wheelUp, .pageUp => {
                        need_repaint = chat.scroll(.up, 1);
                    },
                    .down, .wheelDown, .pageDown => {
                        need_repaint = chat.scroll(.down, 1);
                    },
                    .escape => {
                        return;
                    },
                    .right, .left, .tick => {},
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
                    std.log.debug("got msg!", .{});
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

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;
    const held = std.debug.getStderrMutex().acquire();
    defer held.release();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    // Terminal.panic();
    log(.emerg, .examples, "{}", .{msg});
    std.builtin.default_panic(msg, trace);
}
