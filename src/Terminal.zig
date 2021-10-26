const std = @import("std");
const zbox = @import("zbox");
const Channel = @import("utils/channel.zig").Channel;
const Chat = @import("Chat.zig");
const GlobalEventUnion = @import("main.zig").Event;
const senseUrl = @import("./utils/url.zig").sense;

const ziglyph = @import("ziglyph");

// We expose directly the event type produced by zbox
pub const Event = zbox.Event;
pub const getSize = zbox.size;

pub const TerminalMessage = struct {
    chat_message: Chat.Message,
    buffer: zbox.Buffer,
    is_selected: bool = false,
};

pub const InteractiveElement = union(enum) {
    none,
    subscriber_badge: *TerminalMessage,
    username: *TerminalMessage,
    chat_message: *TerminalMessage,
    event_message: *TerminalMessage,
    button: union(enum) {
        // Message buttons
        del: *TerminalMessage,
    },
};

const EmoteCache = std.AutoHashMap(u32, void);

// State
streamer_name: []const u8,
allocator: *std.mem.Allocator,
output: zbox.Buffer,
chatBuf: zbox.Buffer,
overlayBuf: zbox.Buffer,
ticker: @Frame(startTicking),
active_interaction: InteractiveElement = .none,
emote_cache: EmoteCache,

// Static config
// The message is padded on each line
// by 6 spaces (HH:MM )
//              123456
const padding = 6;
var emulator: enum { kitty, other } = undefined;

const Self = @This();
var done_init = false;
var terminal_inited = false;
var notifs: @Frame(notifyDisplayEvents) = undefined;
pub fn init(alloc: *std.mem.Allocator, ch: *Channel(GlobalEventUnion), streamer_name: []const u8) !Self {
    {
        if (done_init) @panic("Terminal should only be initialized once, like a singleton.");
        done_init = true;
        std.log.debug("init terminal!", .{});
    }

    // Sense the terminal *emulator* we're running in.
    {
        // We're interested in sensing:
        // - Kitty
        const name = std.os.getenv("TERM") orelse std.os.getenv("TERM_PROGRAM") orelse "";
        if (std.mem.eql(u8, name, "xterm-kitty")) {
            emulator = .kitty;
            zbox.is_kitty = true;
        } else {
            emulator = .other;
        }

        std.log.debug("emulator = {}!", .{emulator});
    }

    // Initialize zbox
    try zbox.init(alloc);
    _ = @atomicRmw(bool, &terminal_inited, .Xchg, true, .SeqCst);
    errdefer zbox.deinit();
    errdefer _ = @atomicRmw(bool, &terminal_inited, .Xchg, false, .SeqCst);

    // die on ctrl+C
    // try zbox.handleSignalInput();
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
    errdefer chatBuf.deinit();

    var overlayBuf = try zbox.Buffer.init(alloc, size.height - 2, size.width - 2);
    errdefer overlayBuf.deinit();

    notifs = async notifyDisplayEvents(ch);
    return Self{
        .streamer_name = streamer_name,
        .allocator = alloc,
        .chatBuf = chatBuf,
        .output = output,
        .overlayBuf = overlayBuf,
        .ticker = undefined, //async startTicking(ch),
        .emote_cache = EmoteCache.init(alloc),
    };
}

// Flag touched by whichChandler and startTicking
var dirty: bool = false;
fn winchHandler(
    _: c_int, // signum
) callconv(.C) void {
    _ = @atomicRmw(bool, &dirty, .Xchg, true, .SeqCst);
}

// This function allocates a TerminalMessage and returns a pointer
// to the chat message field. Later, when rendering the application,
// we'll use @fieldParentPointer() to "navigate up" to the full
// scruture from the linked list that Chat keeps.
pub fn prepareMessage(self: *Self, chatMsg: Chat.Message) !*Chat.Message {
    var term_msg = try self.allocator.create(TerminalMessage);

    term_msg.* = switch (chatMsg.kind) {
        .raid,
        .resub,
        .sub,
        .sub_gift,
        .sub_mistery_gift,
        => .{
            .chat_message = chatMsg,
            .is_selected = true,
            .buffer = try zbox.Buffer.init(
                self.allocator,
                2,
                self.chatBuf.width,
            ),
        },
        .chat => |m| .{
            .chat_message = chatMsg,
            .is_selected = m.is_highlighted,
            .buffer = try zbox.Buffer.init(
                self.allocator,
                1,
                self.chatBuf.width - padding,
            ),
        },
        .line => .{
            .chat_message = chatMsg,
            .buffer = try zbox.Buffer.init(
                self.allocator,
                1,
                self.chatBuf.width - padding,
            ),
        },
    };

    try self.renderMessage(term_msg);

    return &term_msg.chat_message;
}

fn setCellToEmote(cell: *zbox.Cell, emote_idx: u32) void {
    cell.* = .{
        .emote_idx = emote_idx,
    };
}

// NOTE: callers must clear the buffer when necessary (when size changes)
fn renderMessage(self: *Self, msg: *TerminalMessage) !void {
    var cursor = msg.buffer.wrappedCursorAt(0, 0).writer();
    cursor.context.attribs = .{
        .normal = true,
    };

    std.log.debug("started rendering msg!", .{});
    switch (msg.chat_message.kind) {
        // else => {
        //     std.log.debug("TODO(renderMessage): implement rendering for  {}", .{@tagName(msg.chat_message.kind)});
        // },
        .line => {},
        .raid => |g| {
            msg.buffer.fill(.{
                .interactive_element = .{
                    .event_message = msg,
                },
            });
            cursor.context.interactive_element = .{
                .event_message = msg,
            };
            cursor.context.attribs = .{
                .feint = true,
            };

            // Top line
            {
                const top_message_fmt = "«{s}»";
                const top_message_args = .{g.display_name};
                cursor.context.col_num = @divTrunc(msg.buffer.width + 2 - std.fmt.count(
                    top_message_fmt,
                    top_message_args,
                ), 2);
                try cursor.print(top_message_fmt, top_message_args);
            }

            // Bottom line
            {
                const message_fmt = "🚨 raiding with {d} people 🚨";
                const message_args = .{g.count};
                cursor.context.row_num = 1;
                cursor.context.col_num = @divTrunc(msg.buffer.width + 4 - std.fmt.count(
                    message_fmt,
                    message_args,
                ), 2);

                try cursor.print(message_fmt, message_args);
            }
        },
        .resub => |r| {
            msg.buffer.fill(.{
                .interactive_element = .{
                    .event_message = msg,
                },
            });
            cursor.context.interactive_element = .{
                .event_message = msg,
            };
            cursor.context.attribs = .{
                .feint = true,
            };
            const tier = switch (r.tier) {
                .prime => "Prime",
                .t1 => "T1",
                .t2 => "T2",
                .t3 => "T3",
            };

            // Top line
            {
                const message_fmt = "«{s}»";
                const message_args = .{r.display_name};
                cursor.context.col_num = @divTrunc(msg.buffer.width + 2 - std.fmt.count(
                    message_fmt,
                    message_args,
                ), 2);
                try cursor.print(message_fmt, message_args);
            }

            // Bottom line
            {
                const message_fmt = "🎉 {d}mo {s} resub! 🎉";
                const message_args = .{ r.count, tier };
                cursor.context.row_num = 1;
                cursor.context.col_num = @divTrunc(msg.buffer.width + 4 - std.fmt.count(
                    message_fmt,
                    message_args,
                ), 2);

                try cursor.print(message_fmt, message_args);
            }
        },
        .sub => |s| {
            msg.buffer.fill(.{
                .interactive_element = .{
                    .event_message = msg,
                },
            });
            cursor.context.interactive_element = .{
                .event_message = msg,
            };
            cursor.context.attribs = .{
                .feint = true,
            };
            const tier = switch (s.tier) {
                .prime => "Prime",
                .t1 => "T1",
                .t2 => "T2",
                .t3 => "T3",
            };

            // Top line
            {
                const message_fmt = "«{s}»";
                const message_args = .{s.display_name};
                cursor.context.col_num = @divTrunc(msg.buffer.width + 2 - std.fmt.count(
                    message_fmt,
                    message_args,
                ), 2);
                try cursor.print(message_fmt, message_args);
            }

            // Bottom line
            {
                const message_fmt = "🎊 is now a {s} sub! 🎊";
                const message_args = .{tier};
                cursor.context.row_num = 1;
                cursor.context.col_num = @divTrunc(msg.buffer.width + 4 - std.fmt.count(
                    message_fmt,
                    message_args,
                ), 2);

                try cursor.print(message_fmt, message_args);
            }
        },
        .sub_gift => |g| {
            msg.buffer.fill(.{
                .interactive_element = .{
                    .event_message = msg,
                },
            });
            cursor.context.interactive_element = .{
                .event_message = msg,
            };
            cursor.context.attribs = .{
                .feint = true,
            };
            const tier = switch (g.tier) {
                .prime => "Prime",
                .t1 => "T1",
                .t2 => "T2",
                .t3 => "T3",
            };

            // Top line
            {
                const message_fmt = "«{s}» 🎁 a {d}mo";
                const message_args = .{ g.sender_display_name, g.months };
                cursor.context.col_num = @divTrunc(msg.buffer.width + 4 - std.fmt.count(
                    message_fmt,
                    message_args,
                ), 2);
                try cursor.print(message_fmt, message_args);
            }

            // Bottom line
            {
                const message_fmt = "{s} Sub to «{s}»";
                const message_args = .{ tier, g.recipient_display_name };
                cursor.context.row_num = 1;
                cursor.context.col_num = @divTrunc(msg.buffer.width + 2 - std.fmt.count(
                    message_fmt,
                    message_args,
                ), 2);

                try cursor.print(message_fmt, message_args);
            }
        },
        .sub_mistery_gift => |g| {
            msg.buffer.fill(.{
                .interactive_element = .{
                    .event_message = msg,
                },
            });
            cursor.context.interactive_element = .{
                .event_message = msg,
            };
            cursor.context.attribs = .{
                .feint = true,
            };
            const tier = switch (g.tier) {
                .prime => "Prime",
                .t1 => "T1",
                .t2 => "T2",
                .t3 => "T3",
            };

            // todo: fallback when there's not enough space

            // Top line
            {
                const top_message_fmt = "«{s}»";
                const top_message_args = .{g.display_name};
                cursor.context.col_num = @divTrunc(msg.buffer.width + 2 - std.fmt.count(
                    top_message_fmt,
                    top_message_args,
                ), 2);
                try cursor.print(top_message_fmt, top_message_args);
            }

            // Bottom line
            {
                const message_fmt = "🎁 Gifted x{d} {s} Subs! 🎁";
                const message_args = .{
                    g.count,
                    tier,
                };
                cursor.context.row_num = 1;
                cursor.context.col_num = @divTrunc(msg.buffer.width + 4 - std.fmt.count(
                    message_fmt,
                    message_args,
                ), 2);

                try cursor.print(message_fmt, message_args);
            }
        },
        .chat => |c| {
            // Async emote image data transmission
            {
                var term_writer = zbox.term.getWriter();
                for (c.emotes) |e| {
                    if (e.img_data) |img| {
                        const entry = try self.emote_cache.getOrPut(e.idx);
                        if (!entry.found_existing) {
                            const single_chunk = img.len <= 4096;
                            if (single_chunk) {
                                std.log.debug("single chunk!", .{});
                                try term_writer.print(
                                    "\x1b_Gf=100,t=d,a=t,i={d};{s}\x1b\\",
                                    .{ e.idx, img },
                                );
                            } else {
                                var cur: usize = 4096;

                                // send first chunk
                                try term_writer.print(
                                    "\x1b_Gf=100,i={d},m=1;{s}\x1b\\",
                                    .{ e.idx, img[0..cur] },
                                );

                                // send remaining chunks
                                while (cur < img.len) : (cur += 4096) {
                                    const end = std.math.min(cur + 4096, img.len);
                                    const m = if (end == img.len) "0" else "1";

                                    // <ESC>_Gs=100,v=30,m=1;<encoded pixel data first chunk><ESC>\
                                    // <ESC>_Gm=1;<encoded pixel data second chunk><ESC>\
                                    // <ESC>_Gm=0;<encoded pixel data last chunk><ESC>\
                                    try term_writer.print(
                                        "\x1b_Gm={s};{s}\x1b\\",
                                        .{ m, img[cur..end] },
                                    );
                                }
                            }
                        }
                    } else {
                        // TODO: display placeholder or something
                    }
                }
            }

            msg.buffer.fill(.{
                .interactive_element = .{
                    .chat_message = msg,
                },
            });
            cursor.context.interactive_element = .{
                .chat_message = msg,
            };

            const action_preamble = "\x01ACTION ";
            if (std.mem.startsWith(u8, c.text, action_preamble) and
                std.mem.endsWith(u8, c.text, "\x01"))
            {
                cursor.context.attribs = .{ .fg_cyan = true };
                try printWordWrap(
                    self.allocator,
                    "*",
                    &[0]Chat.Message.Emote{},
                    &msg.buffer,
                    cursor,
                );

                cursor.context.attribs = .{ .feint = true };
                try printWordWrap(
                    self.allocator,
                    c.text[action_preamble.len .. c.text.len - 1],
                    c.emotes,
                    &msg.buffer,
                    cursor,
                );

                cursor.context.attribs = .{ .fg_cyan = true };
                try printWordWrap(
                    self.allocator,
                    "*",
                    &[0]Chat.Message.Emote{},
                    &msg.buffer,
                    cursor,
                );
            } else {
                try printWordWrap(
                    self.allocator,
                    c.text,
                    c.emotes,
                    &msg.buffer,
                    cursor,
                );
            }
        },
    }
    std.log.debug("done rendering msg!", .{});
}

fn printWordWrap(
    allocator: *std.mem.Allocator,
    text: []const u8,
    emotes: []const Chat.Message.Emote,
    buffer: *zbox.Buffer,
    cursor: zbox.Buffer.Writer,
) !void {
    const width = buffer.width;
    var height = buffer.height; // TODO: do we really need to track this?

    var it = std.mem.tokenize(u8, text, " ");
    var emote_array_idx: usize = 0;
    var codepoints: usize = 0;
    while (it.next()) |word| : (codepoints += 1) { // we add the space, twitch removes extra spaces
        std.log.debug("word: [{s}]", .{word});
        const word_len = try std.unicode.utf8CountCodepoints(word);
        codepoints += word_len;

        const word_width = @intCast(usize, try ziglyph.display_width.strWidth(
            allocator,
            word,
            .half,
        ));

        if (emulator == .kitty and emote_array_idx < emotes.len and
            emotes[emote_array_idx].end == codepoints - 1)
        {
            const emote = emotes[emote_array_idx].idx; //@embedFile("../kappa.txt"); // ; //
            const emote_len = 2;
            emote_array_idx += 1;

            if (emote_len <= width - cursor.context.col_num) {
                // emote fits in this row
                setCellToEmote(buffer.cellRef(
                    cursor.context.row_num,
                    cursor.context.col_num,
                ), emote);
                cursor.context.col_num += 2;
            } else {
                // emote doesn't fit, let's add a line for it.
                height += 1;
                try buffer.resize(height, width);

                cursor.context.col_num = 2;
                cursor.context.row_num += 1;
                setCellToEmote(buffer.cellRef(
                    cursor.context.row_num,
                    0,
                ), emote);
            }
        } else {
            if (word_width >= width) {
                // a link or a very big word
                const is_link = senseUrl(word);

                // How many rows considering that we might be on a row
                // with something already written on it?
                const rows = blk: {
                    const len = word_width + cursor.context.col_num;
                    const rows = @divTrunc(len, width) + if (len % width == 0)
                        @as(usize, 0)
                    else
                        @as(usize, 1);
                    break :blk rows;
                };

                // Ensure we have enough rows
                const missing_rows: isize = @intCast(isize, cursor.context.row_num + rows) - @intCast(isize, height);
                if (missing_rows > 0) {
                    height = height + @intCast(usize, missing_rows);
                    try buffer.resize(height, width);
                }

                // Write the word, make use of the wrapping cursor
                // add link markers if necessary
                if (is_link) {

                    // ignore enclosing parens
                    var start: usize = 0;
                    var end: usize = word.len;
                    const url = url: {
                        if (word[0] == '(') {
                            start = 1;
                            if (word[word.len - 1] == ')') {
                                end = word.len - 1;
                            }
                        }

                        break :url word[start..end];
                    };

                    if (start != 0) try cursor.writeAll("(");

                    cursor.context.link = url;
                    try cursor.writeAll(url[0..1]);
                    cursor.context.link = null;
                    try cursor.writeAll(url[1 .. url.len - 1]);
                    cursor.context.is_link_end = true;
                    try cursor.writeAll(url[url.len - 1 ..]);
                    cursor.context.is_link_end = false;

                    if (end != word.len) try cursor.writeAll(")");
                } else {
                    try cursor.writeAll(word);
                }
            } else if (word_width <= width - cursor.context.col_num) {
                // word fits in this row
                try cursor.writeAll(word);
            } else {
                // word fits the width (i.e. it shouldn't be broken up)
                // but it doesn't fit, let's add a line for it.
                height += 1;
                try buffer.resize(height, width);

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
    defer std.log.debug("notfyDisplayEvents returning", .{});
    std.event.Loop.instance.?.yield();
    while (true) {
        if (try zbox.nextEvent()) |event| {
            ch.put(GlobalEventUnion{ .display = event });
            if (event == .CTRL_C) return;
        }
    }
}

pub fn deinit(self: *Self) void {
    std.log.debug("deinit terminal!", .{});
    zbox.cursorShow() catch {};
    self.output.deinit();
    zbox.deinit();
    std.log.debug("done cleaning term", .{});

    // Why is this a deadlock?
    await notifs catch {};
    std.log.debug("done await", .{});
}

pub fn panic() void {
    if (@atomicRmw(bool, &terminal_inited, .Xchg, false, .SeqCst)) {
        zbox.deinit();
    }
}

pub fn sizeChanged(self: *Self) !void {
    std.log.debug("resizing!", .{});
    const size = try zbox.size();
    if (size.width != self.output.width or size.height != self.output.height) {
        try self.output.resize(size.height, size.width);
        try self.chatBuf.resize(size.height - 2, size.width - 2);
        try self.overlayBuf.resize(size.height - 2, size.width - 2);
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
            .char = '⚡',
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
        self.chatBuf.clear();
        self.overlayBuf.fill(.{
            .is_transparent = true,
        });

        var row = self.chatBuf.height;
        var i: usize = 0;
        var message = chat.bottom_message;
        while (message) |m| : (message = m.prev) {
            // Break if we dont' have more space
            if (row == 0) break;
            i += 1;

            // TODO: do something when the terminal has less than `padding` columns?
            const padded_width = self.chatBuf.width - padding;
            var term_message = @fieldParentPtr(TerminalMessage, "chat_message", m);

            // write it
            switch (m.kind) {
                // else => {
                //     std.log.debug("TODO: implement rendering for  {}", .{@tagName(m.kind)});
                // },
                .raid,
                .resub,
                .sub,
                .sub_gift,
                .sub_mistery_gift,
                => {
                    // re-render the message if width changed in the meantime
                    if (self.chatBuf.width != term_message.buffer.width) {
                        std.log.debug("must rerender msg!", .{});

                        term_message.buffer.deinit();
                        term_message.buffer = try zbox.Buffer.init(self.allocator, 2, self.chatBuf.width);
                        try self.renderMessage(term_message);
                    }

                    const msg_height = term_message.buffer.height;
                    self.chatBuf.blit(
                        term_message.buffer,
                        @intCast(isize, row) - @intCast(isize, msg_height),
                        0,
                    );

                    // If the message is selected, time to invert everything!
                    if (term_message.is_selected) {
                        var rx: usize = row - std.math.min(msg_height, row);
                        while (rx < row) : (rx += 1) {
                            var cx: usize = 0;
                            while (cx < self.chatBuf.width) : (cx += 1) {
                                self.chatBuf.cellRef(rx, cx).attribs.reverse = true;
                            }
                        }
                    }

                    row -= std.math.min(msg_height, row);
                },
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
                    // re-render the message if width changed in the meantime
                    if (padded_width != term_message.buffer.width) {
                        std.log.debug("must rerender msg!", .{});

                        term_message.buffer.deinit();
                        term_message.buffer = try zbox.Buffer.init(self.allocator, 1, padded_width);
                        try self.renderMessage(term_message);
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

                    // If the message is selected, time to invert everything!
                    if (term_message.is_selected) {
                        var rx: usize = row - std.math.min(msg_height, row);
                        while (rx < row) : (rx += 1) {
                            var cx: usize = padding - 1;
                            while (cx < self.chatBuf.width) : (cx += 1) {
                                self.chatBuf.cellRef(rx, cx).attribs.reverse = true;
                            }
                        }
                    }

                    row -= std.math.min(msg_height, row);

                    // Do we have space for the nickname?
                    blk: {
                        if (row > 0) {
                            if (m.prev) |prev| {
                                if (std.mem.eql(u8, m.login_name, prev.login_name)) {
                                    const prev_time = prev.time;

                                    if (std.meta.eql(prev_time, m.time)) {
                                        var cur = self.chatBuf.cursorAt(row, 0);
                                        cur.attribs = .{
                                            .fg_blue = true,
                                        };
                                        try cur.writer().writeAll("   >>");
                                    } else {
                                        var cur = self.chatBuf.cursorAt(row, 0);
                                        cur.attribs = .{
                                            .feint = true,
                                        };
                                        try cur.writer().writeAll(&m.time);
                                    }
                                    break :blk;
                                }
                            }
                            row -= 1;
                            var nick = c.display_name[0..std.math.min(self.chatBuf.width - 5, c.display_name.len)];
                            var cur = self.chatBuf.cursorAt(row, 0);
                            cur.attribs = .{
                                .bold = true,
                            };

                            // Time
                            {
                                try cur.writer().print(
                                    "{s} ",
                                    .{m.time},
                                );
                            }

                            // Nickname
                            var nickname_end_col: usize = undefined;
                            {
                                var nick_left = "«";
                                var nick_right = "»";
                                var highligh_nick = false;
                                switch (self.active_interaction) {
                                    else => {},
                                    .username => |tm| {
                                        if (tm == term_message) {
                                            highligh_nick = true;
                                            nick_right = "«";
                                            nick_left = "»";
                                        }
                                    },
                                }

                                cur.attribs = .{
                                    .fg_yellow = true,
                                    .reverse = highligh_nick,
                                };
                                cur.interactive_element = .{
                                    .username = term_message,
                                };
                                try cur.writer().print("{s}", .{nick_left});

                                {
                                    cur.attribs = .{
                                        .fg_yellow = highligh_nick,
                                        .reverse = highligh_nick,
                                    };

                                    try cur.writer().print("{s}", .{nick});
                                    nickname_end_col = cur.col_num;
                                }

                                cur.attribs = .{
                                    .fg_yellow = true,
                                    .reverse = highligh_nick,
                                };
                                try cur.writer().print("{s}", .{nick_right});
                                cur.interactive_element = .none;
                            }

                            // Badges
                            const badges_width: usize = if (c.is_mod) 4 else 3;
                            if (c.sub_months > 0 and
                                !std.mem.eql(u8, self.streamer_name, m.login_name))
                            {
                                var sub_cur = self.chatBuf.cursorAt(
                                    cur.row_num,
                                    self.chatBuf.width - badges_width,
                                );

                                try sub_cur.writer().print("[", .{});
                                // Subscriber badge
                                {
                                    sub_cur.interactive_element = .{
                                        .subscriber_badge = term_message,
                                    };
                                    if (c.is_founder) {
                                        sub_cur.attribs = .{
                                            .fg_yellow = true,
                                        };
                                    }
                                    try sub_cur.writer().print("S", .{});
                                    sub_cur.interactive_element = .none;
                                    sub_cur.attribs = .{};
                                }

                                // Mod badge
                                if (c.is_mod) {
                                    // sub_cur.interactive_element = .none;
                                    // TODO: interactive element for mods
                                    try sub_cur.writer().print("M", .{});
                                    sub_cur.interactive_element = .none;
                                }
                                try sub_cur.writer().print("]", .{});
                            }

                            switch (self.active_interaction) {
                                else => {},
                                .subscriber_badge => |tm| {
                                    if (tm == term_message) {
                                        try renderSubBadgeOverlay(
                                            c.sub_months,
                                            &self.overlayBuf,
                                            if (cur.row_num >= 3)
                                                cur.row_num - 3
                                            else
                                                0,
                                            badges_width,
                                        );
                                    }
                                },
                                .username => |_| {

                                    // if (tm == term_message) {
                                    //     try renderUserActionsOverlay(
                                    //         c,
                                    //         &self.overlayBuf,
                                    //         cur.row_num,
                                    //         nickname_end_col + 1,
                                    //     );
                                    // }
                                },
                            }
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
    self.output.blit(self.overlayBuf, 1, 1);
    try zbox.push(self.output);
    std.log.debug("render completed!", .{});
}

pub fn handleClick(self: *Self, row: usize, col: usize) !bool {
    // Find the element that was clicked,
    // do the corresponding action.
    const cell = zbox.front.cellRef(
        std.math.min(row, zbox.front.height - 1),
        std.math.min(col, zbox.front.width - 1),
    );
    std.log.debug("cell clicked: {s}", .{@tagName(cell.interactive_element)});

    if (self.active_interaction == .none and
        cell.interactive_element == .none)
    {
        return false;
    }

    var old_action = self.active_interaction;
    self.active_interaction = if (std.meta.eql(
        self.active_interaction,
        cell.interactive_element,
    ))
        .none
    else
        cell.interactive_element;

    // Special rule when going from username to chat_message.
    // This makes clicking on a message disable the username selection
    // without immediately triggering the single-message selection.
    if (old_action == .username) {
        switch (self.active_interaction) {
            else => {},
            .chat_message => |tm| {
                if (tm.is_selected) {
                    self.active_interaction = .none;
                }
            },
        }
    }

    if (!std.meta.eql(old_action, self.active_interaction)) {
        // Perform element-specific cleanup for the old element
        switch (old_action) {
            .none, .button, .subscriber_badge, .event_message => {},
            .chat_message => |tm| {
                tm.is_selected = false;
            },
            .username => |tm| {
                // Username elements can't point to .line messages
                tm.is_selected = false;

                const name = tm.chat_message.login_name;
                var next = tm.chat_message.next;
                while (next) |n| : (next = n.next) {
                    switch (n.kind) {
                        else => break,
                        .chat => {
                            if (!std.mem.eql(u8, n.login_name, name)) break;
                            var term_message = @fieldParentPtr(TerminalMessage, "chat_message", n);
                            term_message.is_selected = false;
                        },
                    }
                }
            },
        }

        // Perform element-specific setup for the new element
        switch (self.active_interaction) {
            .none, .button, .subscriber_badge => {},
            .chat_message => |tm| {
                // If the message came in highlighted we must clear
                // it and also clear the active interaction.
                if (tm.is_selected) {
                    tm.is_selected = false;
                    self.active_interaction = .none;
                } else {
                    tm.is_selected = true;
                }
            },
            .event_message => |tm| {
                tm.is_selected = false;
                if (tm.chat_message.kind == .sub_mistery_gift) {
                    var next = tm.chat_message.next;
                    while (next) |n| : (next = n.next) {
                        switch (n.kind) {
                            else => break,
                            .sub_gift => |_| {
                                var term_message = @fieldParentPtr(TerminalMessage, "chat_message", n);
                                term_message.is_selected = false;
                            },
                        }
                    }
                }
            },
            .username => |tm| {
                // Username elements can't point to .line messages
                tm.is_selected = true;

                const name = tm.chat_message.login_name;
                var next = tm.chat_message.next;
                while (next) |n| : (next = n.next) {
                    switch (n.kind) {
                        else => break,
                        .chat => {
                            if (!std.mem.eql(u8, n.login_name, name)) break;
                            var term_message = @fieldParentPtr(TerminalMessage, "chat_message", n);
                            term_message.is_selected = true;
                        },
                    }
                }
            },
        }
    }

    return true;
}

pub fn clearActiveInteraction(self: *Self, all_or_name: ?[]const u8) void {
    if (all_or_name) |name| {
        const msg_name = switch (self.active_interaction) {
            .subscriber_badge => |m| m.chat_message.login_name,
            .username => |m| m.chat_message.login_name,
            .chat_message => |m| m.chat_message.login_name,
            .event_message => |m| m.chat_message.login_name,
            else => return,
        };

        if (!std.mem.eql(u8, name, msg_name)) {
            return;
        }
    }

    self.active_interaction = .none;
}

fn renderSubBadgeOverlay(months: usize, buf: *zbox.Buffer, row: usize, badges_width: usize) !void {
    const fmt = " Sub for {d} months ";
    const fmt_len = std.fmt.count(fmt, .{months});
    const space_needed = (fmt_len + badges_width + 1);
    if (space_needed >= buf.width) return;
    const left = buf.width - space_needed;

    var cur = buf.cursorAt(row + 1, left);
    try cur.writer().print(fmt, .{months});

    while (cur.col_num < buf.width - badges_width) {
        try cur.writer().print(" ", .{});
    }

    Box.draw(.double, buf, row, left - 1, fmt_len + 1, 3);
}

fn renderUserActionsOverlay(
    _: Chat.Message.Comment,
    buf: *zbox.Buffer,
    row: usize,
    col: usize,
) !void {
    if (row <= 4 or buf.width - col <= 5) return;

    Box.draw(.single, buf, row - 4, col + 1, 4, 5);
    const btns = .{
        .{ "BAN", "fg_red" },
        .{ "MOD", "fg_yellow" },
        .{ "VIP", "fg_blue" },
    };

    var cur: zbox.Buffer.WriteCursor = undefined;
    inline for (btns) |button, i| {
        cur = buf.cursorAt(row - 3 + i, col + 2);
        @field(cur.attribs, button[1]) = true;
        try cur.writer().print(button[0], .{});
    }
    cur.row_num += 1;
    cur.col_num = col;
    cur.attribs = .{};
    try cur.writer().print("─┺", .{});

    //     var cur: zbox.Buffer.WriteCursor = undefined;
    //     inline for (btns) |button, i| {
    //         cur = buf.cursorAt(row - 3 + i, 1);
    //         @field(cur.attribs, button[1]) = true;
    //         try cur.writer().print(button[0], .{});
    //     }
    //     cur.row_num += 1;
    //     cur.attribs = .{};
    //     try cur.writer().print("┹─", .{});
}

fn renderMessageActionsOverlay(
    _: Chat.Message.Comment,
    buf: *zbox.Buffer,
    row: usize,
) !void {
    Box.draw(.single, buf, row - 4, 0, 4, 5);
    const btns = .{
        .{ "DEL", "fg_red" },
        .{ "PIN", "fg_blue" },
    };

    var cur: zbox.Buffer.WriteCursor = undefined;
    inline for (btns) |button, i| {
        cur = buf.cursorAt(row - 3 + i, 1);
        @field(cur.attribs, button[1]) = true;
        try cur.writer().print(button[0], .{});
    }
    cur.row_num += 1;
    cur.attribs = .{};
    try cur.writer().print("┹─", .{});
}

const Box = struct {
    //                      0    1    2    3    4    5
    const double = [6]u21{ '╔', '╗', '╚', '╝', '═', '║' };
    const single = [6]u21{ '┏', '┓', '┗', '┛', '━', '┃' };

    fn draw(comptime set: @Type(.EnumLiteral), buf: *zbox.Buffer, row: usize, col: usize, width: usize, height: usize) void {
        const char_set = @field(Box, @tagName(set));

        {
            var i: usize = col;
            while (i < col + width) : (i += 1) {
                buf.cellRef(row, i).* = .{ .char = char_set[4] };
                buf.cellRef(row + height - 1, i).* = .{ .char = char_set[4] };
            }
        }

        {
            var i: usize = row;
            while (i < row + height - 1) : (i += 1) {
                buf.cellRef(i, col).* = .{ .char = char_set[5] };
                buf.cellRef(i, col + width).* = .{ .char = char_set[5] };
            }
        }

        buf.cellRef(row, col).* = .{ .char = char_set[0] };
        buf.cellRef(row, col + width).* = .{ .char = char_set[1] };

        buf.cellRef(row + height - 1, col).* = .{ .char = char_set[2] };
        buf.cellRef(row + height - 1, col + width).* = .{ .char = char_set[3] };
    }
};
