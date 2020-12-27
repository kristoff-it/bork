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

pub const Event = union(enum) {
    display: Terminal.Event,
    network: Network.Event,
};

var log_level: std.log.Level = .warn;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = &gpa.allocator;

    const nick = nick: {
        var it = std.process.ArgIterator.init();
        var exe_name = try (it.next(alloc) orelse @panic("no executable name as first argument!?")); // burn exe name
        defer alloc.free(exe_name);

        break :nick try (it.next(alloc) orelse {
            std.debug.print("Usage: ./bork your_channel_name\n", .{});
            return;
        });
    };

    const auth = std.os.getenv("TWITCH_OAUTH") orelse {
        std.debug.print(
            \\To connect to Twitch, bork needs to authenticate as you.
            \\Please place your OAuth token in an env variable named:
            \\                       TWITCH_OAUTH
            \\
            \\Here's an official tool that can quickly generate a token
            \\for you: https://twitchapps.com/tmi/
            \\
            \\It might be a good idea to save the token in a dotfile
            \\and then refer to your token through it:
            \\
            \\       TWITCH_OAUTH="$(cat ~/.twitch_oauth)" ./bork
            \\
            \\Or, even better, consider adding this line to your shell
            \\startup file:
            \\
            \\       export TWITCH_OAUTH="$(cat ~/.twitch_oauth)"
            \\
        , .{});
        std.os.exit(1);
    };

    if (!std.mem.startsWith(u8, auth, "oauth:")) {
        std.debug.print("TWITCH_OAUTH needs to start with `oauth:`\n", .{});
        std.os.exit(1);
    }

    var buf: [24]Event = undefined;
    var ch = Channel(Event).init(&buf);

    var display = try Terminal.init(alloc, &ch, nick);
    defer display.deinit();

    var network: Network = undefined;
    try network.init(alloc, &ch, nick, auth, senseUserTZ());
    defer network.deinit();

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
                        switch (c[0]) {
                            'r', 'R' => {
                                try display.sizeChanged();
                                need_repaint = true;
                                chaos = false;
                            },
                            else => {},
                        }
                    },
                    .leftClick => |pos| {
                        std.log.debug("click at {}", .{pos});
                        need_repaint = try display.handleClick(pos.row - 1, pos.col - 1);
                    },
                    .CTRL_C => return,
                    .up, .wheelUp, .pageUp => {
                        need_repaint = chat.scroll(.up, 1);
                    },
                    .down, .wheelDown, .pageDown => {
                        need_repaint = chat.scroll(.down, 1);
                    },
                    .escape, .right, .left, .tick => {},
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
    nosuspend {
        const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
        const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;
        const held = std.debug.getStderrMutex().acquire();
        defer held.release();
        const logfile = std.fs.cwd().createFile("bork.log", .{ .truncate = false, .intended_io_mode = .blocking }) catch return;
        defer logfile.close();
        const writer = logfile.writer();
        const end = logfile.getEndPos() catch return;
        logfile.seekTo(end) catch return;
        writer.print(prefix ++ format ++ "\n", args) catch return;
    }
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    nosuspend Terminal.panic();
    log(.emerg, .default, "{}", .{msg});
    std.builtin.default_panic(msg, trace);
}
