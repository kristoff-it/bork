const std = @import("std");
const zbox = @import("zbox");
const Channel = @import("../channel.zig").Channel;
const Chat = @import("../Chat.zig");
const GlobalEvent = @import("../events.zig").Event;

// We expose directly the event type produced by zbox
pub const Event = zbox.Event;
pub const nextEvent = zbox.nextEvent;

// State
log: std.fs.File.Writer,
output: zbox.Buffer,
chatBuf: zbox.Buffer,

const Self = @This();
var done_init = false;
var logger: std.fs.File.Writer = undefined;
pub fn init(alloc: *std.mem.Allocator, log: std.fs.File.Writer, ch: *Channel(GlobalEvent)) !Self {
    logger = log;
    {
        if (done_init) @panic("Terminal should only be initialized once, like a singleton.");
        done_init = true;
        try log.writeAll("init terminal");
    }

    // Initialize zbox
    try zbox.init(alloc);
    errdefer zbox.deinit();

    // 144fps repaints
    {
        frames[0] = async addResizeEvent(ch, 0);
        frames[1] = async addResizeEvent(ch, 1);
        // switch (std.builtin.os.tag) {
        //     .macos => {},
        //     .linux => {
        //         std.os.sigaction(std.os.SIGWINCH, &std.os.Sigaction{
        //             .sigaction = linuxWinchHandler,
        //             .mask = std.os.empty_sigset,
        //             .flags = 0,
        //         }, null);
        //     },
        //     else => {},
        // }

        std.os.sigaction(std.os.SIGWINCH, &std.os.Sigaction{
            .handler = .{ .handler = darwinWinchHandler },
            .mask = 0,
            .flags = 0,
        }, null);
    }

    // die on ctrl+C
    try zbox.handleSignalInput();
    try zbox.cursorHide();

    // Init main buffer
    var size = try zbox.size();
    var output = try zbox.Buffer.init(alloc, size.height, size.width);
    errdefer output.deinit();

    // Add top and bottom bars
    {
        var i: usize = 1;
        while (i < size.width) : (i += 1) {
            output.cellRef(0, i).* = .{
                .char = ' ',
                .attribs = .{ .bg_blue = true },
            };
            output.cellRef(size.height - 1, i).* = .{
                .char = ' ',
                .attribs = .{ .bg_blue = true },
            };
        }
    }

    // Setup the buffer for chat history
    var chatBuf = try zbox.Buffer.init(alloc, size.height - 2, size.width);

    return Self{
        .log = log,
        .chatBuf = chatBuf,
        .output = output,
    };
}

pub fn deinit(self: *Self) void {
    self.output.deinit();
    zbox.deinit();
    self.log.writeAll("deinit terminal") catch {};
}

pub fn renderChat(self: *Self, chat: *Chat) !void {
    try self.log.writeAll("render\n");
    const size = try zbox.size();
    if (self.output.height != size.height or self.output.width != size.width) {
        self.log.writeAll("resizing\n") catch {};
        try self.output.resize(size.height, size.width);
        try self.chatBuf.resize(size.height - 2, size.width);
        self.output.clear();
    }

    // Render the chat history
    {
        self.chatBuf.clear();

        var message = chat.bottom_message;
        var row = self.chatBuf.height;
        var i: usize = 0;
        while (message) |m| : (message = m.prev) {
            i += 1;
            // Compute how much space msg will take
            var lines: usize = 1;

            // stop when no more space available.
            if (lines > row) return;
            row -= lines;

            // write it
            try self.chatBuf.cursorAt(row, 1).writer().print("[nick]: {}", .{m.text});
        }
    }

    // Render the bottom bar
    {
        if (chat.last_message == chat.bottom_message) {
            var i: usize = 1;
            while (i < size.width) : (i += 1) {
                self.output.cellRef(size.height - 1, i).* = .{
                    .char = ' ',
                    .attribs = .{ .bg_blue = true },
                };
            }
        } else {
            const msg = "DETACHED";
            if (size.width > msg.len) {
                var column = @divTrunc(size.width, 2) - 4; // TODO: test this math lmao
                try self.output.cursorAt(size.height - 1, column).writer().writeAll(msg);
            }

            var i: usize = 1;
            while (i < size.width) : (i += 1) {
                self.output.cellRef(size.height - 1, i).attribs = .{
                    .bg_yellow = true,
                    .fg_black = true,
                    // TODO: why is bold messing around with fg?
                    // .bold = true,
                };
            }
        }
    }

    {}

    self.output.blit(self.chatBuf, 1, 1);
    try zbox.push(self.output);
}

pub var tick_index: usize = 0;
var frames: [2]@Frame(addResizeEvent) = undefined;
var nodes: [2]std.event.Loop.NextTickNode = undefined;

fn darwinWinchHandler(signum: c_int) callconv(.C) void {
    const old = @atomicRmw(usize, &tick_index, .Add, 1, .SeqCst);
    if (old < nodes.len) {
        std.event.Loop.instance.?.onNextTick(&nodes[old]);
    } else {
        _ = @atomicRmw(usize, &tick_index, .Sub, 1, .SeqCst);
    }
}

fn addResizeEvent(ch: *Channel(GlobalEvent), index: usize) void {
    nodes[index].data = @frame();
    while (true) {
        suspend;
        ch.put(GlobalEvent.resize);
    }
}
