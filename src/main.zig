const std = @import("std");
const options = @import("build_options");
const Channel = @import("utils/channel.zig").Channel;
const network = @import("network.zig");
const Terminal = @import("Terminal.zig");
const Chat = @import("Chat.zig");

pub const io_mode = .evented;

var log: std.fs.File.Writer = undefined;

pub const Event = union(enum) {
    display: Terminal.Event,
    network: network.Event,
};

pub fn main() !void {
    var l = try std.fs.cwd().createFile("foo.log", .{ .truncate = true, .intended_io_mode = .blocking });
    log = l.writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var alloc = &arena.allocator;

    var buf: [24]Event = undefined;
    var ch = Channel(Event).init(&buf);

    var display = try Terminal.init(alloc, log, &ch);
    defer display.deinit();

    var network_runner = async getNetworkEvents(alloc, &ch);

    var chat = Chat{ .log = log };

    var chaos = false;
    while (true) {
        var need_repaint = false;

        const event = ch.get();
        switch (event) {
            .display => |de| {
                switch (de) {
                    .chaos => {
                        chaos = true;
                        log.writeAll("CHAOS!\n") catch unreachable;
                    },
                    .calm => {
                        log.writeAll("CALM!\n") catch unreachable;
                        chaos = false;
                        try display.sizeChanged();
                        need_repaint = true;
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
            .network => |ne| {
                var memory = try arena.allocator.alignedAlloc(
                    u8,
                    @alignOf(Chat.Message),
                    @sizeOf(Chat.Message) + ne.msg.len,
                );

                std.mem.copy(u8, memory[memory.len - ne.msg.len ..], ne.msg);
                var message = @ptrCast(*Chat.Message, memory);
                message.* = .{
                    .text = memory[memory.len - ne.msg.len ..],
                };

                need_repaint = chat.addMessage(message);
            },
        }

        if (need_repaint and !chaos) {
            try display.renderChat(&chat);
        }
    }

    // TODO: implement real cleanup
    try await network_runner;
}

fn getNetworkEvents(alloc: *std.mem.Allocator, ch: *Channel(Event)) !void {
    var i: usize = 0;
    while (true) : (i += 1) {
        std.time.sleep(1000 * std.time.ns_per_ms);
        const b = try std.fmt.allocPrint(alloc, "msg #{}!\n", .{i});

        ch.put(Event{ .network = .{ .msg = b } });
    }
}
