const std = @import("std");
const options = @import("build_options");
const network = @import("network.zig");
const Channel = @import("channel.zig").Channel;
const Terminal = @import("render/Terminal.zig");
const Chat = @import("Chat.zig");
const Event = @import("events.zig").Event;

pub const io_mode = .evented;

var log: std.fs.File.Writer = undefined;

pub fn main() !void {
    var l = try std.fs.cwd().createFile("log.txt", .{ .truncate = true, .intended_io_mode = .blocking });
    log = l.writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var alloc = &arena.allocator;

    var buf: [24]Event = undefined;
    var ch = Channel(Event).init(&buf);

    // initialize the display with stdin/out
    var display = try Terminal.init(alloc, log, &ch);
    defer display.deinit();

    var display_runner = async getDisplayEvents(&ch);
    var network_runner = async getNetworkEvents(alloc, &ch);

    var chat = Chat{ .log = log };

    while (true) {
        var need_repaint = false;

        const event = ch.get();
        switch (event) {
            .resize => {
                _ = @atomicRmw(usize, &Terminal.tick_index, .Sub, 1, .SeqCst);
                log.writeAll("resize!!!\n") catch unreachable;
                need_repaint = true;
            },
            .display => |de| {
                switch (de) {
                    .up => {
                        need_repaint = chat.scroll(.up, 1);
                    },
                    .down => {
                        need_repaint = chat.scroll(.down, 1);
                    },
                    .right, .left, .other, .tick, .escape => {},
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

        if (need_repaint) try display.renderChat(&chat);
    }

    // TODO: implement real cleanup
    try await display_runner;
    try await network_runner;
}
fn getDisplayEvents(ch: *Channel(Event)) !void {
    while (true) {
        ch.put(Event{ .display = (try Terminal.nextEvent()) orelse continue });
    }
}

fn getNetworkEvents(alloc: *std.mem.Allocator, ch: *Channel(Event)) !void {
    var i: usize = 0;
    while (true) : (i += 1) {
        std.time.sleep(1000 * std.time.ns_per_ms);
        const b = try std.fmt.allocPrint(alloc, "msg #{}!\n", .{i});

        ch.put(Event{ .network = .{ .msg = b } });
    }
}
