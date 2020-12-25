const std = @import("std");
const zbox = @import("zbox");
const Channel = @import("utils/channel.zig").Channel;
const Chat = @import("Chat.zig");
const GlobalEventUnion = @import("main.zig").Event;

// We expose directly the event type produced by zbox
pub const Event = zbox.Event;
pub const getSize = zbox.size;

pub const TerminalMessage = struct {
    chat_message: Chat.Message,
    buffer: zbox.Buffer,
};

// State
allocator: *std.mem.Allocator,
output: zbox.Buffer,
chatBuf: zbox.Buffer,
ticker: @Frame(startTicking),
notifs: @Frame(notifyDisplayEvents),
// Static config
// The message is padded on each line
// by 6 spaces (HH:MM )
//              123456
const padding = 6;
var emulator: enum { iterm, wez, kitty, other } = undefined;

const Self = @This();
var done_init = false;
pub fn init(alloc: *std.mem.Allocator, ch: *Channel(GlobalEventUnion)) !Self {
    {
        if (done_init) @panic("Terminal should only be initialized once, like a singleton.");
        done_init = true;
        std.log.debug("init terminal!", .{});
    }

    // Sense the terminal *emulator* we're running in.
    {
        // We're interested in sensing:
        // - iTerm2
        // - WezTerm
        // - Kitty
        const name = std.os.getenv("TERM_PROGRAM") orelse std.os.getenv("TERM") orelse "";
        if (std.mem.eql(u8, name, "WezTerm")) {
            emulator = .wez;
        } else if (std.mem.eql(u8, name, "iTerm.app")) {
            emulator = .iterm;
        } else if (std.mem.eql(u8, name, "xterm-kitty")) {
            emulator = .kitty;
            zbox.is_kitty = true;
        } else {
            emulator = .other;
        }

        std.log.debug("emulator = {}!", .{emulator});
    }

    // Initialize zbox
    try zbox.init(alloc);
    errdefer zbox.deinit();

    // die on ctrl+C
    try zbox.handleSignalInput();
    try zbox.cursorHide();

    // 144fps repaints
    {
        // TODO: debug why some resizings corrupt everything irreversibly;
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
    var chatBuf = try zbox.Buffer.init(alloc, size.height - 2, size.width - 2);

    // NOTE: frames can't be copied so copy elision is required
    return Self{
        .allocator = alloc,
        .chatBuf = chatBuf,
        .output = output,
        .ticker = async startTicking(ch),
        .notifs = async notifyDisplayEvents(ch),
    };
}

// Flag touched by whichChandler and startTicking
var dirty: bool = false;
fn winchHandler(signum: c_int) callconv(.C) void {
    _ = @atomicRmw(bool, &dirty, .Xchg, true, .SeqCst);
}

// This function allocates a TerminalMessage and returns a pointer
// to the chat message field. Later, when rendering the application,
// we'll use @fieldParentPointer() to "navigate up" to the full
// scruture from the linked list that Chat keeps.
pub fn prepareMessage(self: *Self, chatMsg: Chat.Message) !*Chat.Message {
    var term_msg = try self.allocator.create(TerminalMessage);

    term_msg.* = .{
        .chat_message = chatMsg,
        .buffer = try zbox.Buffer.init(self.allocator, 1, self.chatBuf.width - padding),
    };
    try renderMessage(self.allocator, term_msg);

    return &term_msg.chat_message;
}

fn setCellToEmote(cell: *zbox.Cell, emote: []const u8) void {
    cell.* = switch (emulator) {
        .wez, .iterm => .{
            .imageDecorationPre = "\x1b]1337;File=inline=1;preserveAspectRatio=1;height=1;size=2164;:",
            .image = emote,
            .imageDecorationPost = "\x07",
        },
        .kitty => .{
            .imageDecorationPre = "\x1b_Gf=100,t=d,a=T,r=1,c=2,q=1;",
            .image = emote,
            .imageDecorationPost = "\x1b\\",
        },
        .other => .{
            .char = ' ',
        },
    };
}

// NOTE: callers must clear the buffer when necessary (when size changes)
fn renderMessage(alloc: *std.mem.Allocator, msg: *TerminalMessage) !void {
    const width = msg.buffer.width;
    var height = msg.buffer.height;

    var cursor = msg.buffer.wrappedCursorAt(0, 0).writer();
    cursor.context.attribs = .{
        .normal = true,
    };
    std.log.debug("started rendering msg!", .{});
    switch (msg.chat_message.kind) {
        .line => {},
        .chat => |c| {
            var it = std.mem.tokenize(c.text, " ");
            var emote_idx: usize = 0;
            while (it.next()) |w| {
                std.log.debug("word: [{}]", .{w});

                if (emote_idx < c.meta.emotes.len and
                    c.meta.emotes[emote_idx].end == it.index - 1)
                {
                    const emote = c.meta.emotes[emote_idx].image orelse "⚡"; //@embedFile("../kappa.txt"); // ; //
                    const emote_len = 2;
                    emote_idx += 1;

                    if (emote_len <= width - cursor.context.col_num) {
                        // emote fits in this row
                        setCellToEmote(msg.buffer.cellRef(
                            cursor.context.row_num,
                            cursor.context.col_num,
                        ), emote);
                        cursor.context.col_num += 2;
                    } else {
                        // emote doesn't fit, let's add a line for it.
                        height += 1;
                        try msg.buffer.resize(height, width);

                        cursor.context.col_num = 2;
                        cursor.context.row_num += 1;
                        setCellToEmote(msg.buffer.cellRef(
                            cursor.context.row_num,
                            0,
                        ), emote);
                    }
                } else {
                    const word = w;
                    const word_len = try std.unicode.utf8CountCodepoints(w);

                    if (word_len >= width) {
                        // a link or a very big word

                        // How many rows considering that we might be on a row
                        // with something already written on it?
                        const rows = blk: {
                            const len = word_len + cursor.context.col_num;
                            const rows = @divTrunc(len, width) + if (len % width == 0)
                                @as(usize, 0)
                            else
                                @as(usize, 1);
                            break :blk rows;
                        };

                        // Ensure we have enough rows
                        {
                            const missing_rows: isize = @intCast(isize, cursor.context.row_num + rows) - @intCast(isize, height);
                            if (missing_rows > 0) {
                                height = height + @intCast(usize, missing_rows);
                                try msg.buffer.resize(height, width);
                                cursor = msg.buffer.wrappedCursorAt(
                                    cursor.context.row_num,
                                    cursor.context.col_num,
                                ).writer();
                            }
                        }

                        // Write the word, make use of the wrapping cursor
                        try cursor.writeAll(word);
                    } else if (word_len <= width - cursor.context.col_num) {
                        // word fits in this row
                        try cursor.writeAll(word);
                    } else {
                        // word fits the width (i.e. it shouldn't be broken up)
                        // but it doesn't fit, let's add a line for it.
                        height += 1;
                        try msg.buffer.resize(height, width);

                        // Add a newline if we're not at the end
                        if (cursor.context.col_num < width) try cursor.writeAll("\n");
                        try cursor.writeAll(word);
                    }
                }

                // If we're not at the end of the line, add a space
                if (cursor.context.col_num < width) {
                    try cursor.writeAll(" ");
                }
            }
        },
    }
    std.log.debug("done rendering msg!", .{});
}

pub fn startTicking(ch: *Channel(GlobalEventUnion)) void {
    const cooldown = 5;

    var chaos_cooldown: isize = -1;
    var last_size: @TypeOf(zbox.size()) = undefined;
    while (true) {
        std.time.sleep(100 * std.time.ns_per_ms);
        if (@atomicRmw(bool, &dirty, .Xchg, false, .SeqCst)) {
            // Flag was true, term is being resized
            ch.put(GlobalEventUnion{ .display = .chaos });
            if (chaos_cooldown > -1) {
                std.log.debug("ko, restarting", .{});
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
                std.log.debug("ko, restarting", .{});
            }
        }
    }
}

pub fn notifyDisplayEvents(ch: *Channel(GlobalEventUnion)) !void {
    std.event.Loop.instance.?.yield();
    while (true) {
        ch.put(GlobalEventUnion{ .display = (try zbox.nextEvent()) orelse continue });
    }
}

pub fn deinit(self: *Self) void {
    std.log.debug("deinit terminal!", .{});
    self.output.deinit();
    zbox.deinit();
    // We're not awaiting .ticker nor .notifs, but if we're deiniting
    // it means the app is exiting and there's nothing
    // important to cleanup there.
}

pub fn panic() void {
    zbox.deinit();
}

pub fn sizeChanged(self: *Self) !void {
    std.log.debug("resizing!", .{});
    const size = try zbox.size();
    if (size.width != self.output.width or size.height != self.output.height) {
        try self.output.resize(size.height, size.width);
        try self.chatBuf.resize(size.height - 2, size.width - 2);
        self.output.clear();
        try zbox.term.clear();
        try zbox.term.flush();
    }
}

pub fn renderChat(self: *Self, chat: *Chat) !void {
    std.log.debug("render!", .{});

    // TODO: this is a very inefficient way of using Kitty
    if (emulator == .kitty) {
        try zbox.term.send("\x1b_Ga=d\x1b\\");
    }

    // Add top bar
    {
        const emoji_column = @divTrunc(self.output.width, 2) - 1; // TODO: test this math lmao

        var i: usize = 1;
        while (i < self.output.width - 1) : (i += 1) {
            self.output.cellRef(0, i).* = .{
                .char = ' ',
                .attribs = .{ .bg_blue = true },
            };
        }
        var cur = self.output.cursorAt(0, emoji_column - 4);
        cur.attribs = .{
            .fg_black = true,
            .bg_blue = true,
        };
        // try cur.writer().writeAll("Zig");
        // cur.col_num = emoji_column + 2;
        // try cur.writer().writeAll("b0rk");
        self.output.cellRef(0, emoji_column).* = .{
            .image = "⚡",
            .attribs = .{
                .fg_yellow = true,
                .bg_blue = true,
            },
        };
    }

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

            // TODO: do something when the terminal has less than `padding` columns?
            const padded_width = self.chatBuf.width - padding;

            // write it
            switch (m.kind) {
                .line => {

                    // Update the row position
                    row -= 1;

                    // NOTE: since line takes only one row and we break when row == 0,
                    //       we don't have to check for space.
                    var col: usize = 1;
                    var cursor = self.chatBuf.cursorAt(row, col).writer();
                    while (col < self.chatBuf.width - 1) : (col += 1) {
                        try cursor.print("-", .{});
                    }

                    const msg = "[RECONNECTED]";
                    if (self.chatBuf.width > msg.len) {
                        var column = @divTrunc(self.chatBuf.width, 2) + (self.chatBuf.width % 2) - @divTrunc(msg.len, 2) - (msg.len % 2); // TODO: test this math lmao
                        try self.chatBuf.cursorAt(row, column).writer().writeAll(msg);
                    }
                },
                .chat => |c| {
                    var term_message = @fieldParentPtr(TerminalMessage, "chat_message", m);

                    // re-render the message if width changed in the meantime
                    if (padded_width != term_message.buffer.width) {
                        std.log.debug("must rerender msg!", .{});

                        term_message.buffer.deinit();
                        term_message.buffer = try zbox.Buffer.init(self.allocator, 1, padded_width);
                        try renderMessage(self.allocator, term_message);
                    }

                    // Update the row position
                    // NOTE: row stops at zero, but we want to blit at
                    //       negative coordinates if we have to.
                    const msg_height = term_message.buffer.height;
                    self.chatBuf.blit(
                        term_message.buffer,
                        @intCast(isize, row) - @intCast(isize, msg_height),
                        padding,
                    );

                    row -= std.math.min(msg_height, row);

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
                                        var cur = self.chatBuf.cursorAt(row, 0);
                                        cur.attribs = .{
                                            .fg_red = true,
                                        };
                                        try cur.writer().writeAll("   >>");
                                    } else {
                                        var cur = self.chatBuf.cursorAt(row, 0);
                                        cur.attribs = .{
                                            .feint = true,
                                        };
                                        try cur.writer().writeAll(&c.time);
                                    }
                                    break :blk;
                                }
                            }
                            row -= 1;
                            var nick = c.name[0..std.math.min(self.chatBuf.width, c.name.len)];
                            var cur = self.chatBuf.cursorAt(row, 0);
                            cur.attribs = .{
                                .bold = true,
                            };
                            try cur.writer().print(
                                "{} <{}>",
                                .{ c.time, nick },
                            );

                            // Prints a Kappa after every username
                            // self.chatBuf.cellRef(cur.row_num, self.chatBuf.width - 2).* = .{
                            //     .image = @embedFile("../kappa.txt"),
                            // };
                        }
                    }
                },
            }
        }
    }

    // Render the bottom bar
    {
        const width = self.output.width - 1;
        if (chat.disconnected) {
            const msg = "DISCONNECTED";
            if (width > msg.len) {
                var column = @divTrunc(width, 2) + (width % 2) - @divTrunc(msg.len, 2) - (msg.len % 2); // TODO: test this math lmao
                try self.output.cursorAt(self.output.height - 1, column).writer().writeAll(msg);
            }

            var i: usize = 1;
            while (i < width) : (i += 1) {
                self.output.cellRef(self.output.height - 1, i).attribs = .{
                    .bg_red = true,
                    .fg_black = true,
                };
            }
        } else if (chat.last_message == chat.bottom_message) {
            var i: usize = 1;
            while (i < width) : (i += 1) {
                self.output.cellRef(self.output.height - 1, i).* = .{
                    .char = ' ',
                    .attribs = .{ .bg_blue = true },
                };
            }
        } else {
            const msg = "DETACHED";
            var column: usize = 0;
            if (width > msg.len) {
                column = @divTrunc(width, 2) + (width % 2) - @divTrunc(msg.len, 2) - (msg.len % 2); // TODO: test this math lmao
                try self.output.cursorAt(self.output.height - 1, column).writer().writeAll(msg);
            }

            var i: usize = 1;
            while (i < width) : (i += 1) {
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

    self.output.blit(self.chatBuf, 1, 1);
    try zbox.push(self.output);
    std.log.debug("render completed!", .{});
}
