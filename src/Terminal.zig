const std = @import("std");
const zbox = @import("zbox");
const Channel = @import("utils/channel.zig").Channel;
const Chat = @import("Chat.zig");
const GlobalEventUnion = @import("main.zig").Event;

// We expose directly the event type produced by zbox
pub const Event = zbox.Event;
pub const getSize = zbox.size;

// State
log: std.fs.File.Writer,
output: zbox.Buffer,
chatBuf: zbox.Buffer,
ticker: @Frame(startTicking),
notifs: @Frame(notifyDisplayEvents),

const Self = @This();
var done_init = false;
pub fn init(alloc: *std.mem.Allocator, log: std.fs.File.Writer, ch: *Channel(GlobalEventUnion)) !Self {
    {
        if (done_init) @panic("Terminal should only be initialized once, like a singleton.");
        done_init = true;
        try log.writeAll("init terminal");
    }

    // Initialize zbox
    try zbox.init(alloc);
    errdefer zbox.deinit();

    // die on ctrl+C
    try zbox.handleSignalInput();
    try zbox.cursorHide();

    // 144fps repaints
    {
        // TODO: debug why some resizings corrupt everything irreversibly
        //       in the meantime users can press R to repaint everything.

        // std.os.sigaction(std.os.SIGWINCH, &std.os.Sigaction{
        //     .handler = .{ .handler = winchHandler },
        //     .mask = switch (std.builtin.os.tag) {
        //         .macos => 0,
        //         .linux => std.os.empty_sigset,
        //         .windows => @compileError(":3"),
        //         else => @compileError("os not supported"),
        //     },
        //     .flags = 0,
        // }, null);
    }

    // Init main buffer
    var size = try zbox.size();
    var output = try zbox.Buffer.init(alloc, size.height, size.width);
    errdefer output.deinit();

    // Setup the buffer for chat history
    var chatBuf = try zbox.Buffer.init(alloc, size.height - 2, size.width - 1);

    // NOTE: frames can't be copied so copy elision is required
    return Self{
        .log = log,
        .chatBuf = chatBuf,
        .output = output,
        .ticker = async startTicking(ch, log),
        .notifs = async notifyDisplayEvents(ch),
    };
}

// Flag touched by whichChandler and startTicking
var dirty: bool = false;
fn winchHandler(signum: c_int) callconv(.C) void {
    _ = @atomicRmw(bool, &dirty, .Xchg, true, .SeqCst);
}

pub fn startTicking(ch: *Channel(GlobalEventUnion), log: std.fs.File.Writer) void {
    const cooldown = 5;

    var chaos_cooldown: isize = -1;
    var last_size: @TypeOf(zbox.size()) = undefined;
    while (true) {
        std.time.sleep(100 * std.time.ns_per_ms);
        if (@atomicRmw(bool, &dirty, .Xchg, false, .SeqCst)) {
            // Flag was true, term is being resized
            ch.put(GlobalEventUnion{ .display = .chaos });
            if (chaos_cooldown > -1) {
                log.writeAll("ko, restarting!\n") catch unreachable;
            }
            chaos_cooldown = cooldown;
            last_size = zbox.size();
        } else if (chaos_cooldown > -1) {
            var new_size = zbox.size();
            if (std.meta.eql(new_size, last_size)) {
                if (chaos_cooldown == 0) {
                    ch.put(GlobalEventUnion{ .display = .calm });
                }
                chaos_cooldown -= 1;
            } else {
                last_size = new_size;
                chaos_cooldown = cooldown;
                log.writeAll("ko, restarting!\n") catch unreachable;
            }
        }
    }
}

pub fn notifyDisplayEvents(ch: *Channel(GlobalEventUnion)) !void {
    while (true) {
        ch.put(GlobalEventUnion{ .display = (try zbox.nextEvent()) orelse continue });
    }
}

pub fn deinit(self: *Self) void {
    self.log.writeAll("deinit terminal") catch {};
    self.output.deinit();
    zbox.deinit();
    // We're not awaiting .ticker nor .notifs, but if we're deiniting
    // it means the app is exiting and there's nothing
    // important to cleanup there.
}

pub fn sizeChanged(self: *Self) !void {
    self.log.writeAll("resizing\n") catch {};
    const size = try zbox.size();
    try self.output.resize(size.height, size.width);
    try self.chatBuf.resize(size.height - 2, size.width);
    self.output.clear();
}

pub fn renderChat(self: *Self, chat: *Chat) !void {
    try self.log.writeAll("render\n");

    // Add top bar
    {
        var i: usize = 1;
        while (i < self.output.width) : (i += 1) {
            self.output.cellRef(0, i).* = .{
                .char = ' ',
                .attribs = .{ .bg_blue = true },
            };
        }
    }
    try self.log.writeAll("###1\n");

    // Render the chat history
    {
        // NOTE: chat history is rendered bottom-up, starting from the newest
        //       message visible at the bottom, going up to the oldest.
        //       within the context of each message, instead, rendering
        //       is top-down, starting from the first line of the message,
        //       progressing down to the last.
        self.chatBuf.clear();
        var message = chat.bottom_message;
        var row = self.chatBuf.height;
        var i: usize = 0;
        while (message) |m| : (message = m.prev) {
            // Break if we dont' have more space
            if (row == 0) break;

            i += 1;

            // Compute how much space msg will take.
            // NOTE: The message is padded on each line
            // by 6 spaces (HH:MM )
            //              123456
            const padding = 6;

            // TODO: do something when the terminal has less than `padding` columns?
            const padded_width = self.chatBuf.width - padding;
            const lines: usize = switch (m.kind) {
                .line => 1,
                .chat => |c| blk: {
                    // Get unicode length of the message
                    const msg_len = try std.unicode.utf8CountCodepoints(c.text);
                    break :blk @divTrunc(msg_len, padded_width) + if (msg_len % padded_width == 0)
                        @as(usize, 0)
                    else
                        @as(usize, 1);
                },
            };

            const end_row = row;
            row -= std.math.min(row, lines);

            // write it
            switch (m.kind) {
                .line => {
                    // NOTE: since line takes only one row and we break when row == 0,
                    //       we don't have to check for space.
                    var col: usize = 1;
                    var cursor = self.chatBuf.cursorAt(row, col).writer();
                    while (col < self.chatBuf.width - 1) : (col += 1) {
                        try cursor.print("-", .{});
                    }

                    const msg = "[RECONNECTED]";
                    if (self.chatBuf.width > msg.len) {
                        var column = @divTrunc(self.chatBuf.width, 2) + (self.chatBuf.width % 2) - @divTrunc(msg.len, 2) - (msg.len % 2) - 1; // TODO: test this math lmao
                        try self.chatBuf.cursorAt(row, column).writer().writeAll(msg);
                    }
                },
                .chat => |c| {
                    // NOTE: we might not have enough space for the whole message,
                    //       in which case we need to skip the first line(s) and only
                    //       print the last (few).
                    var cp_iter = (try std.unicode.Utf8View.init(c.text)).iterator();
                    {
                        var idx = if (lines > end_row)
                            (lines - end_row) * padded_width
                        else
                            @as(usize, 0);

                        while (idx > 0) : (idx -= 1) {
                            _ = cp_iter.nextCodepoint();
                        }
                    }

                    var current_row = row;
                    while (current_row < end_row) : (current_row += 1) {
                        var rowCells = self.chatBuf.row(current_row);

                        for (rowCells) |*cell, cell_idx| {
                            if (cell_idx < padding) {
                                cell.* = .{
                                    .char = ' ',
                                };
                            } else {
                                if (cp_iter.nextCodepoint()) |cp| {
                                    cell.* = .{
                                        .char = cp,
                                    };
                                } else {
                                    cell.* = .{
                                        .char = ' ',
                                    };
                                }
                            }
                        }
                    }

                    // Do we have space for the nickname?
                    blk: {
                        if (row > 0) {
                            if (m.prev) |prev| {
                                const same_name = switch (prev.kind) {
                                    .line => false,
                                    .chat => |c_prev| std.mem.eql(u8, c.name, c_prev.name),
                                };
                                if (same_name) {
                                    const prev_time = prev.kind.chat.time;
                                    if (std.meta.eql(prev_time, c.time)) {
                                        try self.chatBuf.cursorAt(row, 0).writer().writeAll("   >>");
                                    } else {
                                        try self.chatBuf.cursorAt(row, 0).writer().writeAll(&c.time);
                                    }
                                    break :blk;
                                }
                            }
                            row -= 1;
                            var nick = c.name[0..std.math.min(self.chatBuf.width, c.name.len)];
                            try self.chatBuf.cursorAt(row, 0).writer().print(
                                "{} <{}>",
                                .{ c.time, nick },
                            );
                        }
                    }

                    // self.chatBuf.cellRef(row, msg.text.len + msg.name.len + 4).* = .{
                    //     .image = @embedFile("../kappa.txt"),
                    // };

                    // self.chatBuf.cellRef(row, msg.text.len + msg.name.len + 4 + 1).* = .{
                    //     .char = ' ',
                    // };
                },
            }
        }
    }

    try self.log.writeAll("###2\n");
    // Render the bottom bar
    {
        if (chat.disconnected) {
            const msg = "DISCONNECTED";
            if (self.output.width > msg.len) {
                var column = @divTrunc(self.output.width, 2) + (self.chatBuf.width % 2) - @divTrunc(msg.len, 2) - (msg.len % 2); // TODO: test this math lmao
                try self.output.cursorAt(self.output.height - 1, column).writer().writeAll(msg);
            }

            var i: usize = 1;
            while (i < self.output.width) : (i += 1) {
                self.output.cellRef(self.output.height - 1, i).attribs = .{
                    .bg_red = true,
                    .fg_black = true,
                };
            }
        } else if (chat.last_message == chat.bottom_message) {
            var i: usize = 1;
            while (i < self.output.width) : (i += 1) {
                self.output.cellRef(self.output.height - 1, i).* = .{
                    .char = ' ',
                    .attribs = .{ .bg_blue = true },
                };
            }
        } else {
            const msg = "DETACHED";
            var column: usize = 0;
            if (self.output.width > msg.len) {
                column = @divTrunc(self.output.width, 2) + (self.chatBuf.width % 2) - @divTrunc(msg.len, 2) - (msg.len % 2); // TODO: test this math lmao
                try self.output.cursorAt(self.output.height - 1, column).writer().writeAll(msg);
            }

            var i: usize = 1;
            while (i < self.output.width) : (i += 1) {
                var cell = self.output.cellRef(self.output.height - 1, i);
                cell.attribs = .{
                    .bg_yellow = true,
                    .fg_black = true,
                    // TODO: why is bold messing around with fg?
                    // .bold = true,
                };
                if (i < column or i >= column + msg.len) {
                    cell.char = ' ';
                }
            }
        }
    }
    try self.log.writeAll("###3\n");

    {}

    self.output.blit(self.chatBuf, 1, 1);
    try zbox.push(self.output);
    try self.log.writeAll("render complete\n");
}
