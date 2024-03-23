const builtin = @import("builtin");
const options = @import("build_options");
const std = @import("std");
const os = std.os;
const posix = std.posix;
const ziglyph = @import("ziglyph");
const dw = ziglyph.display_width;
const Grapheme = ziglyph.Grapheme;
const GraphemeIterator = Grapheme.GraphemeIterator;
// const Word = ziglyph.Word;
// const WordIterator = Word.WordIterator;
const main = @import("main.zig");
const url = @import("utils/url.zig");
const Config = @import("Config.zig");
const Chat = @import("Chat.zig");
const Channel = @import("utils/channel.zig").Channel;
const GlobalEventUnion = main.Event;

const log = std.log.scoped(.display);

var gpa: std.mem.Allocator = undefined;
var config: Config = undefined;
var ch: *Channel(GlobalEventUnion) = undefined;

var size: Size = undefined;
var tty: std.fs.File = undefined;
var original_termios: ?posix.termios = null;
var emulator_supports_emotes = false;
var message_rendering_buffer: std.ArrayListUnmanaged(u8) = .{};
var emote_cache: std.AutoHashMapUnmanaged(u32, void) = .{};
var chat: *Chat = undefined;
var elements: []InteractiveElement = &.{};
var active: InteractiveElement = .none;
var showing_quit_message: ?i64 = null;
var afk: ?Afk = null;

const Afk = struct {
    target_time: i64,
    title: []const u8 = "AFK",
    reason: []const u8 = "⏰",
};

const InteractiveElement = union(enum) {
    none,
    afk,
    nick: []const u8,
    message: *Chat.Message,

    pub fn eql(lhs: InteractiveElement, rhs: InteractiveElement) bool {
        if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
        return switch (lhs) {
            .none => true,
            .afk => false,
            .nick => std.mem.eql(u8, lhs.nick, rhs.nick),
            .message => lhs.message == rhs.message,
        };
    }
};

pub const Event = union(enum) {
    size_changed,
    tick,

    // user I/O
    ctrl_c,
    up,
    down,
    left,
    right,
    wheel_up,
    wheel_down,
    page_up,
    page_down,
    left_click: Position,

    pub const Position = struct { row: usize, col: usize };
};

pub fn setup(
    gpa_: std.mem.Allocator,
    ch_: *Channel(GlobalEventUnion),
    config_: Config,
    chat_: *Chat,
) !void {
    gpa = gpa_;
    ch = ch_;
    config = config_;
    chat = chat_;

    const name = std.posix.getenv("TERM") orelse
        std.posix.getenv("TERM_PROGRAM") orelse
        "";

    emulator_supports_emotes = std.mem.eql(u8, name, "xterm-ghostty") or
        std.mem.eql(u8, name, "xterm-kitty");
    log.debug("emulator emote support = {}", .{emulator_supports_emotes});

    tty = try std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write });
    errdefer tty.close();

    original_termios = try posix.tcgetattr(tty.handle);
    errdefer original_termios = null;

    var new_termios = original_termios.?;

    // termios flags for 'raw' mode.
    new_termios.iflag.IGNBRK = false;
    new_termios.iflag.BRKINT = false;
    new_termios.iflag.PARMRK = false;
    new_termios.iflag.ISTRIP = false;
    new_termios.iflag.INLCR = false;
    new_termios.iflag.IGNCR = false;
    new_termios.iflag.ICRNL = false;
    new_termios.iflag.IXON = false;

    new_termios.lflag.ICANON = false;
    new_termios.lflag.ECHO = false;
    new_termios.lflag.ECHONL = false;
    new_termios.lflag.IEXTEN = false;
    new_termios.lflag.ISIG = false;

    new_termios.oflag.OPOST = false;

    new_termios.cflag.CSIZE = .CS8;

    try posix.tcsetattr(tty.handle, .FLUSH, new_termios);
    errdefer posix.tcsetattr(tty.handle, .FLUSH, original_termios.?) catch {};

    try tty.writeAll(
        // enter alt screen
        "\x1B[s\x1B[?47h\x1B[?1049h" ++
            // dislable wrapping mode
            "\x1B[?7l" ++
            //  disable insert mode (replaces text)
            "\x1B[4l" ++
            // hide the cursor
            "\x1B[?25l" ++
            // mouse mode
            "\x1B[?1000h",
    );
    errdefer restoreModes();

    // resize handler
    try std.posix.sigaction(std.posix.SIG.WINCH, &std.posix.Sigaction{
        .handler = .{ .handler = winchHandler },
        .mask = switch (builtin.os.tag) {
            .macos => 0,
            .linux => std.posix.empty_sigset,
            .windows => @compileError("TODO: SIGWINCH support for windows"),
            else => @compileError("os not supported"),
        },
        .flags = 0,
    }, null);

    size = getTermSize();
    elements = try gpa.alloc(InteractiveElement, size.rows + 1);

    const input_thread = try std.Thread.spawn(.{}, readInput, .{});
    input_thread.detach();
    const ticker_thread = try std.Thread.spawn(.{}, tick, .{});
    ticker_thread.detach();
}

// handles window resize
fn winchHandler(_: c_int) callconv(.C) void {
    ch.tryPut(.{ .display = .size_changed }) catch {};
}

fn tick() void {
    while (true) {
        ch.tryPut(.{ .display = .tick }) catch {};
        std.time.sleep(250 * std.time.ns_per_ms);
    }
}

pub fn teardown() void {
    log.debug("display teardown!", .{});
    if (original_termios) |og| {
        restoreModes();
        posix.tcsetattr(tty.handle, .FLUSH, og) catch std.process.exit(1);
        message_rendering_buffer.deinit(gpa);
        original_termios = null;
    }
}

fn restoreModes() void {
    tty.writeAll(
        // exit alt screen
        "\x1B[u\x1B[?47l\x1B[?1049l" ++
            // enable wrapping mode
            "\x1B[?7h" ++
            // show the cursor
            "\x1B[?25h" ++
            // disable mouse mode
            "\x1B[?1000l" ++
            // exit sync mode
            "\x1B[?2026l",
    ) catch std.process.exit(1);
}

pub fn readInput() !void {
    var buffered_reader = std.io.bufferedReader(tty.reader());
    const r = buffered_reader.reader();
    while (true) {
        const event = parseEvent(r) catch |err| {
            log.debug("readInput errored out: {}", .{err});
            if (err == error.NotOpenForReading) return;
            return err;
        };
        log.debug("event: {any}", .{event});
        ch.put(.{ .display = event });
    }
}

fn moveCursor(w: Writer, row: usize, col: usize) !void {
    try w.print("\x1B[{};{}H", .{ row, col });
}
const Writer = std.io.BufferedWriter(4096, std.fs.File.Writer).Writer;
const Size = struct {
    rows: usize,
    cols: usize,
    pub fn eql(lhs: Size, rhs: Size) bool {
        return lhs.rows == rhs.rows and
            lhs.cols == rhs.cols;
    }
};

fn getTermSize() Size {
    var winsize = std.mem.zeroes(posix.system.winsize);

    const err = posix.system.ioctl(tty.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (posix.errno(err) == .SUCCESS) {
        return Size{ .rows = winsize.ws_row, .cols = winsize.ws_col };
    }

    log.err("updateTermSize failed!", .{});
    std.process.exit(1);
}

pub fn sizeChanged() bool {
    const new = getTermSize();

    log.debug("size changed! {} {}", .{ new, size });

    if (new.eql(size)) return false;

    if (size.rows > elements.len) {
        elements = gpa.realloc(elements, size.rows + 1) catch
            @panic("oom");
    }
    size = new;
    return true;
}

const window_title_width = window_title.len - 2;
const window_title: []const u8 = blk: {
    var v = std.mem.tokenize(u8, options.version, ".");
    const major = v.next().?;
    const minor = v.next().?;
    const patch = v.next().?;
    const dev = v.next() != null;
    const more = if (dev or patch[0] != '0') "+" else "";

    break :blk std.fmt.comptimePrint("bork ⚡ v{s}.{s}{s}", .{ major, minor, more });
};

var placement_id: usize = 0;
const HeadingStyle = enum { nick, arrows, time };
pub fn render() !void {
    placement_id = 0;
    log.debug("RENDER!\n {?any}", .{chat.last_message});

    var buffered_writer = std.io.bufferedWriter(tty.writer());
    var w = buffered_writer.writer();

    // enter sync mode
    try w.writeAll("\x1B[?2026h");

    // cursor to the top left and clear the screen below
    try moveCursor(w, 1, 1);
    try w.writeAll("\x1B[0J");
    try w.writeAll("\x1B_Ga=d\x1B\\");

    @memset(elements, .none);

    try writeStyle(w, .{ .bg = .blue, .fg = .white });
    if (window_title_width < size.cols) {
        const padding = (size.cols -| window_title_width) / 2;
        for (0..padding) |_| try w.writeAll(" ");
        try w.writeAll(window_title);
        for (0..padding + 1) |_| try w.writeAll(" ");
    } else {
        try w.writeAll(window_title);
    }

    if (size.rows > 1) {
        try moveCursor(w, size.rows, 1);

        const last_is_bottom = chat.last_message == chat.bottom_message;
        if (showing_quit_message) |timeout| {
            const now = std.time.timestamp();
            if (timeout <= now) showing_quit_message = null;
        }
        if (showing_quit_message != null) {
            const msg = "run `bork quit`";
            try writeStyle(w, .{ .bg = .white, .fg = .red });
            const padding = (size.cols -| msg.len) / 2;
            for (0..padding) |_| try w.writeAll(" ");
            try w.writeAll(msg);
            for (0..padding + 1) |_| try w.writeAll(" ");
        } else if (chat.disconnected) {
            const msg = "DISCONNECTED";
            try writeStyle(w, .{ .bg = .red, .fg = .black });
            const padding = (size.cols -| msg.len) / 2;
            for (0..padding) |_| try w.writeAll(" ");
            try w.writeAll(msg);
            for (0..padding + 1) |_| try w.writeAll(" ");
        } else if (last_is_bottom and chat.scroll_offset == 0) {
            for (0..size.cols) |_| try w.writeAll(" ");
        } else {
            const msg = "DETACHED";
            try writeStyle(w, .{ .bg = .yellow, .fg = .black });
            const padding = (size.cols -| msg.len) / 2;
            for (0..padding) |_| try w.writeAll(" ");
            try w.writeAll(msg);
            for (0..padding + 1) |_| try w.writeAll(" ");
        }
    }

    try writeStyle(w, .{});

    var row: usize = size.rows;

    // afk message
    if (afk) |a| blk: {
        if (row < 7) break :blk;

        row -|= 5;
        try moveCursor(w, row, 1);

        // top line
        try w.writeAll("╔");
        for (0..size.cols) |_| try w.writeAll("═");
        try w.writeAll("╗\r\n");

        // central lines
        try w.writeAll("║");
        {
            const width = try dw.strWidth(a.title, .half);
            const padding = (size.cols -| width) / 2;
            for (0..padding -| 1) |_| try w.writeAll(" ");
            try w.print("{s}", .{a.title});
            for (0..padding) |_| try w.writeAll(" ");
        }
        try w.writeAll("║\r\n");
        try w.writeAll("║");
        {
            const now = std.time.timestamp();
            const remaining = @max(a.target_time - now, 0);
            var timer: [9]u8 = undefined;
            {
                const cd = @as(usize, @intCast(remaining));
                const h = @divTrunc(cd, 60 * 60);
                const m = @divTrunc(@mod(cd, 60 * 60), 60);
                const s = @mod(cd, 60);
                _ = std.fmt.bufPrint(&timer, "{:0>2}h{:0>2}m{:0>2}s", .{
                    h, m, s,
                }) catch unreachable; // we know we have the space
            }
            const width = timer.len + 8;
            const padding = (size.cols -| width) / 2;
            for (0..padding -| 1) |_| try w.writeAll(" ");
            try w.print("--- {s} ---", .{timer});
            for (0..padding) |_| try w.writeAll(" ");
        }
        try w.writeAll("║\r\n");
        try w.writeAll("║");
        {
            const width = try dw.strWidth(a.reason, .half);
            const padding = (size.cols -| width) / 2;
            for (0..padding -| 1) |_| try w.writeAll(" ");
            try w.print("{s}", .{a.reason});
            for (0..padding) |_| try w.writeAll(" ");
        }
        try w.writeAll("║\r\n");

        // bottom line
        try w.writeAll("╚");
        for (0..size.cols) |_| try w.writeAll("═");
        try w.writeAll("╝\r\n");
        for (row..row + 5) |idx| elements[idx] = .afk;
    }

    var current_message = chat.bottom_message;
    var scroll_offset = chat.scroll_offset;
    while (current_message) |msg| : (current_message = msg.prev) {
        if (row == 1) break;

        const heading_style: HeadingStyle = if (msg.prev) |p| blk: {
            if (std.mem.eql(u8, msg.login_name, p.login_name)) {
                if (std.mem.eql(u8, &msg.time, &p.time)) {
                    break :blk .arrows;
                } else break :blk .time;
            } else break :blk .nick;
        } else .nick;

        const info = try renderMessage(size.cols, msg, heading_style);

        var msg_bytes = info.bytes;
        var msg_rows = info.rows;
        log.debug("scroll_offset {}, rows {}", .{ scroll_offset, msg_rows });

        if (scroll_offset >= info.rows) {
            const change = chat.scrollBottomMessage(.up);
            if (change) {
                log.debug("change", .{});
                chat.scroll_offset -|= @intCast(info.rows);
                scroll_offset -|= @intCast(info.rows);
                continue;
            } else {
                log.debug("no change", .{});
                chat.scroll_offset = @intCast(info.rows -| 1);
                scroll_offset = chat.scroll_offset;
            }
        }

        if (scroll_offset > 0) {
            var it = std.mem.splitScalar(u8, info.bytes, '\n');
            const skip = info.rows -| @as(usize, @intCast(scroll_offset));
            for (0..skip) |_| _ = it.next();
            msg_bytes = info.bytes[0..it.index.?];
            msg_rows -|= @intCast(scroll_offset);
            scroll_offset = 0;
        } else if (chat.scroll_offset < 0) {
            var it = std.mem.splitScalar(u8, info.bytes, '\n');
            const keep = @min(info.rows, @as(usize, @intCast(-scroll_offset)));
            msg_bytes.len = 0;
            for (0..keep) |_| msg_bytes.len += it.next().?.len;
            chat.scroll_offset = @intCast(msg_rows -| keep);
            msg_rows = keep;
            scroll_offset = 0;
        }

        if (msg_rows + 1 >= row) {
            var it = std.mem.splitScalar(u8, msg_bytes, '\n');
            const skip = (msg_rows + 2) -| row;
            for (0..skip) |_| _ = it.next();
            try moveCursor(w, 2, 1);
            try w.writeAll(it.rest());
            for (0..msg_rows -| skip + 1) |idx| {
                elements[row + idx] = .{ .message = msg };
            }
            break;
        } else {
            row = row -| msg_rows;
            try moveCursor(w, row, 1);
            try w.writeAll(msg_bytes);
            if (heading_style == .nick and msg.kind == .chat) {
                elements[row] = .{ .nick = msg.login_name };
            } else {
                elements[row] = .{ .message = msg };
            }
            for (0..msg_rows -| 1) |idx| {
                elements[row + 1 + idx] = .{ .message = msg };
            }
        }
    }

    // exit sync mode
    try w.writeAll("\x1B[?2026l");
    try buffered_writer.flush();
}

const RenderInfo = struct {
    rows: usize,
    bytes: []const u8,
};

fn renderMessage(
    cols: usize,
    msg: *Chat.Message,
    heading_style: HeadingStyle,
) !RenderInfo {
    message_rendering_buffer.clearRetainingCapacity();
    const w = message_rendering_buffer.writer(gpa);
    const nick_selected = switch (active) {
        .nick => |n| std.mem.eql(u8, n, msg.login_name),
        else => false,
    };
    switch (msg.kind) {
        .chat => |c| {
            // Async emote image data transmission
            for (c.emotes) |e| {
                const img = e.img_data orelse {
                    // TODO: display placeholder or something
                    continue;
                };
                const entry = try emote_cache.getOrPut(gpa, e.idx);
                if (entry.found_existing) continue;

                log.debug("uploading emote!", .{});

                if (img.len <= 4096) {
                    try w.print(
                        "\x1b_Gf=100,t=d,a=t,i={d};{s}\x1b\\",
                        .{ e.idx, img },
                    );
                } else {
                    var cur: usize = 4096;

                    // send first chunk
                    try w.print(
                        "\x1b_Gf=100,i={d},m=1;{s}\x1b\\",
                        .{ e.idx, img[0..cur] },
                    );

                    // send remaining chunks
                    while (cur < img.len) : (cur += 4096) {
                        const end = @min(cur + 4096, img.len);
                        const m = if (end == img.len) "0" else "1";

                        // <ESC>_Gs=100,v=30,m=1;<encoded pixel data first chunk><ESC>\
                        // <ESC>_Gm=1;<encoded pixel data second chunk><ESC>\
                        // <ESC>_Gm=0;<encoded pixel data last chunk><ESC>\
                        try w.print(
                            "\x1b_Gm={s};{s}\x1b\\",
                            .{ m, img[cur..end] },
                        );
                    }
                }
            }

            switch (heading_style) {
                .nick => {
                    try writeStyle(w, .{ .weight = .bold });
                    try w.print("{s} ", .{&msg.time});
                    if (nick_selected) try writeStyle(w, .{
                        .weight = .bold,
                        .fg = .yellow,
                        .reverse = true,
                    });
                    try w.print("«{s}»", .{c.display_name});
                    try writeStyle(w, .{});
                    try w.print("\r\n      ", .{});
                },

                .time => {
                    try writeStyle(w, .{ .weight = .feint });
                    try w.print("{s} ", .{&msg.time});
                    try writeStyle(w, .{});
                },

                .arrows => {
                    try writeStyle(w, .{ .fg = .magenta });
                    try w.print("   >> ", .{});
                    try writeStyle(w, .{});
                },
            }
            const hl = c.is_highlighted or switch (active) {
                .message => |m| m == msg,
                .nick => nick_selected,
                else => false,
            };

            const body_rows = try printWrap(
                cols,
                w,
                c.text,
                c.emotes,
                hl,
            );
            var rows = body_rows;
            if (heading_style == .nick) rows += 1;

            return .{
                .rows = rows,
                .bytes = message_rendering_buffer.items,
            };
        },

        inline .charity,
        .follow,
        .raid,
        .sub,
        .resub,
        .sub_gift,
        .sub_mistery_gift,
        => |x, tag| {
            try writeStyle(w, .{
                .reverse = true,
                .weight = .bold,
            });

            // Top line
            {
                const fmt = "«{s}»";
                const args = switch (tag) {
                    .sub_gift => .{x.sender_display_name},
                    else => .{x.display_name},
                };
                const width = try dw.strWidth(args[0], .half) + 2;
                const padding = (size.cols -| width) / 2;
                for (0..padding) |_| try w.writeAll(" ");
                try w.print(fmt, args);
                for (0..padding + 1) |_| try w.writeAll(" ");
            }

            try w.writeAll("\r\n");
            try writeStyle(w, .{
                .reverse = true,
                .weight = .bold,
            });

            // Bottom line
            {
                const emoji = switch (tag) {
                    .raid => "🚨",
                    .sub_gift, .sub_mistery_gift => "🎁",
                    .charity => "💝",
                    else => "🎉",
                };
                const emoji_width = comptime dw.strWidth(
                    emoji,
                    .half,
                ) catch unreachable;

                const fmt = switch (tag) {
                    .charity => " {s} charity donation! ",
                    .follow => " Is now a follower! ",
                    .raid => " Raiding with {} people! ",
                    .sub => " Is now a {s} subscriber! ",
                    .resub => " Resubbed at {s}! ",
                    .sub_gift => " Gifted a {s} sub to «{s}»! ",
                    .sub_mistery_gift => " Gifted x{} {s} Subs! ",
                    else => unreachable,
                };
                const args = switch (tag) {
                    .charity => .{x.amount},
                    .follow => .{},
                    .raid => .{x.count},
                    .sub => .{x.tier.name()},
                    .resub => .{x.tier.name()},
                    .sub_gift => .{
                        x.tier.name(),
                        x.recipient_display_name,
                    },
                    .sub_mistery_gift => .{ x.count, x.tier.name() },
                    else => unreachable,
                };

                const width = switch (tag) {
                    .sub_gift => std.fmt.count(fmt, .{
                        x.tier.name(),
                        "",
                    }) + try dw.strWidth(x.recipient_display_name, .half),
                    else => std.fmt.count(fmt, args) + (emoji_width * 2),
                };
                const padding = (size.cols -| width) / 2;
                for (0..padding) |_| try w.writeAll(" ");
                try w.writeAll(emoji);
                try w.print(fmt, args);
                try w.writeAll(emoji);
                for (0..padding + 1) |_| try w.writeAll(" ");
            }
            try writeStyle(w, .{});
            return .{
                .rows = 2,
                .bytes = message_rendering_buffer.items,
            };
        },
        .line => {
            return .{ .rows = 0, .bytes = &.{} };
        },
    }
}

fn printWrap(
    cols: usize,
    w: std.ArrayListUnmanaged(u8).Writer,
    text: []const u8,
    emotes: []const Chat.Message.Emote,
    // message is highlighted
    hl: bool,
) !usize {
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    var current_col: usize = 6;
    var total_rows: usize = 1;
    if (hl) try writeStyle(w, .{ .reverse = true });
    var emote_array_idx: usize = 0;
    var cp: usize = 0;
    while (it.next()) |word| : (cp += 1) {
        cp += try std.unicode.utf8CountCodepoints(word);

        const word_width: usize = @intCast(try dw.strWidth(word, .half));

        if (emulator_supports_emotes and emote_array_idx < emotes.len and
            emotes[emote_array_idx].end == cp - 1)
        {
            const emote_idx = emotes[emote_array_idx].idx;
            log.debug("rendering emote {s} ({})", .{ word, emote_idx });
            emote_array_idx += 1;
            current_col += 2;

            if (current_col >= cols) {
                if (hl) try writeStyle(w, .{});
                try w.writeAll("\r\n      ");
                if (hl) try writeStyle(w, .{ .reverse = true });
                current_col = 6;
                total_rows += 1;
            }
            try w.print(
                "\x1b_Gf=100,t=d,a=p,r=1,c=2,i={d},p={};\x1b\\",
                .{ emote_idx, placement_id },
            );
            placement_id += 1;
            current_col += 2;
        } else if (word_width >= cols) {
            // a link or a very big word
            const is_link = url.sense(word);
            if (is_link) {
                var start: usize = 0;
                var end: usize = word.len;
                const link = blk: {
                    if (word[0] == '(') {
                        start = 1;
                        if (word[word.len - 1] == ')') {
                            end = word.len - 1;
                        }
                    }

                    break :blk word[start..end];
                };

                if (start != 0) {
                    if (current_col >= cols) {
                        if (hl) try writeStyle(w, .{});
                        try w.writeAll("\r\n      ");
                        if (hl) try writeStyle(w, .{ .reverse = true });
                        current_col = 6;
                        total_rows += 1;
                    }
                    try w.writeAll("(");
                    current_col += 1;
                }

                var git = GraphemeIterator.init(link);
                var url_is_off = true;
                while (git.next()) |grapheme| {
                    const bytes = grapheme.slice(link);
                    const remaining = cols -| current_col;
                    const grapheme_cols = try dw.strWidth(bytes, .half);
                    if (grapheme_cols > remaining) {
                        if (!url_is_off) {
                            url_is_off = true;
                            try w.writeAll("\x1b]8;;\x1b\\");
                        }
                        if (hl) {
                            for (0..remaining) |_| try w.writeAll(" ");
                            try writeStyle(w, .{});
                        }
                        try w.writeAll("\r\n      ");
                        if (hl) try writeStyle(w, .{ .reverse = true });
                        current_col = 6;
                        total_rows += 1;
                    }

                    if (url_is_off) {
                        url_is_off = false;
                        try w.print(
                            "\x1b]8;id={};{s}\x1b\\",
                            .{
                                std.hash.Crc32.hash(link),
                                link,
                            },
                        );
                    }

                    try w.writeAll(bytes);
                    current_col += grapheme_cols;
                }

                if (!url_is_off) {
                    try w.writeAll("\x1b]8;;\x1b\\");
                }

                if (end != word.len) {
                    if (current_col >= cols) {
                        if (hl) try writeStyle(w, .{});
                        try w.writeAll("\r\n      ");
                        if (hl) try writeStyle(w, .{ .reverse = true });
                        current_col = 6;
                        total_rows += 1;
                    }
                    try w.writeAll(")");
                    current_col += 1;
                }
            } else {
                var git = GraphemeIterator.init(word);
                while (git.next()) |grapheme| {
                    const bytes = grapheme.slice(word);
                    const remaining = cols -| current_col;
                    const grapheme_cols = try dw.strWidth(bytes, .half);
                    if (grapheme_cols > remaining) {
                        if (hl) {
                            for (0..remaining) |_| try w.writeAll(" ");
                            try writeStyle(w, .{});
                        }
                        try w.writeAll("\r\n      ");
                        if (hl) try writeStyle(w, .{ .reverse = true });
                        current_col = 6;
                        total_rows += 1;
                    }

                    try w.writeAll(bytes);
                    current_col += grapheme_cols;
                }
            }
        } else if (word_width <= cols -| current_col) {
            // word fits in this row
            try w.writeAll(word);
            current_col += word_width;
        } else {
            // word fits the width (i.e. it shouldn't be broken up)
            // but it doesn't fit, let's add a line for it.
            total_rows += 1;

            if (hl) {
                for (0..(cols -| current_col)) |_| try w.writeAll(" ");
                try writeStyle(w, .{});
            }
            try w.writeAll("\r\n      ");
            if (hl) try writeStyle(w, .{ .reverse = true });
            try w.writeAll(word);
            current_col = 6 + word_width;
        }

        if (current_col < cols) {
            try w.writeAll(" ");
            current_col += 1;
        }
    }

    if (hl) {
        for (0..(cols -| current_col)) |_| try w.writeAll(" ");
        try writeStyle(w, .{});
    }

    return total_rows;
}
pub fn setAfkMessage(
    target_time: i64,
    reason: []const u8,
    title: []const u8,
) !void {
    log.debug("afk: {d}, {s}", .{ target_time, reason });

    afk = .{ .target_time = target_time };

    if (title.len > 0) afk.?.title = title;
    if (reason.len > 0) afk.?.reason = reason;
}

pub fn showCtrlCMessage() !bool {
    log.debug("show ctrlc message", .{});
    showing_quit_message = std.time.timestamp() + 3;
    return true;
}

pub fn handleClick(row: usize, col: usize) !bool {
    log.debug("click {},{}!", .{ row, col });

    var new = elements[row];

    switch (new) {
        .none => {},
        .afk => {
            active = .none;
            afk = null;
            return true;
        },
        .nick => |n| {
            if (col < 6 or col > 6 + 1 + try dw.strWidth(n, .half) + 1) {
                new = .none;
            }
        },
        .message => {
            if (col < 6) new = .none;
        },
    }

    if (new == .none and active == .none) {
        return false;
    }

    if (active.eql(new)) {
        active = .none;
    } else {
        active = new;
    }

    log.debug("new active element: {any}", .{active});
    return true;
}

pub fn prepareMessage(m: Chat.Message) !*Chat.Message {
    const result = try gpa.create(Chat.Message);
    result.* = m;
    return result;
}

pub fn clearActiveInteraction(c: ?[]const u8) void {
    _ = c;
}

pub fn wantTick() bool {
    return afk != null or showing_quit_message != null;
}

pub fn panic() void {
    // if (global_term) |t| {
    //     t.currently_rendering = false;
    //     t.deinit();
    // }
}

pub const Style = struct {
    weight: enum { none, bold, normal, feint } = .none,
    italics: bool = false,
    underline: bool = false,
    reverse: bool = false,
    fg: Color = .none,
    bg: Color = .none,

    pub const Color = enum {
        none,
        black,
        red,
        green,
        yellow,
        blue,
        magenta,
        cyan,
        white,
    };
};

pub fn writeStyle(w: anytype, comptime style: Style) !void {
    try w.writeAll("\x1B[0"); // always clear

    switch (style.weight) {
        .none => {},
        .bold => try w.writeAll(";1"),
        .normal => try w.writeAll(";22"),
        .feint => try w.writeAll(";2"),
    }

    switch (style.fg) {
        .none => {},
        .black => try w.writeAll(";30"),
        .red => try w.writeAll(";31"),
        .green => try w.writeAll(";32"),
        .yellow => try w.writeAll(";33"),
        .blue => try w.writeAll(";34"),
        .magenta => try w.writeAll(";35"),
        .cyan => try w.writeAll(";36"),
        .white => try w.writeAll(";37"),
    }

    switch (style.bg) {
        .none => {},
        .black => try w.writeAll(";40"),
        .red => try w.writeAll(";41"),
        .green => try w.writeAll(";42"),
        .yellow => try w.writeAll(";43"),
        .blue => try w.writeAll(";44"),
        .magenta => try w.writeAll(";45"),
        .cyan => try w.writeAll(";46"),
        .white => try w.writeAll(";47"),
    }

    if (style.italics) try w.writeAll(";3");
    if (style.underline) try w.writeAll(";4");
    if (style.reverse) try w.writeAll(";7");

    try w.writeAll("m");
}

fn parseEvent(
    r: std.io.BufferedReader(4096, std.fs.File.Reader).Reader,
) !Event {
    var state: enum {
        start,
        escape,
        event,
    } = .start;
    while (true) {
        const b = try r.readByte();
        switch (state) {
            .start => switch (b) {
                else => {},
                '\x1b' => state = .escape,
                '\x03' => return .ctrl_c,
            },

            .escape => switch (b) {
                else => state = .start,
                '[', 'O' => state = .event,
                '\x1b' => {},
            },
            .event => switch (b) {
                else => state = .start,
                'A' => return .up,
                'B' => return .down,
                'C' => return .right,
                'D' => return .left,
                '5', '6' => {
                    _ = try r.readByte();
                    switch (b) {
                        '5' => return .page_up,
                        '6' => return .page_down,
                        else => unreachable,
                    }
                },
                'M' => {
                    const button = try r.readByte();
                    switch (button) {
                        else => state = .start,
                        '`' => return .wheel_up,
                        'a' => return .wheel_down,
                        ' ' => {
                            const col = try r.readByte();
                            const row = try r.readByte();
                            return .{
                                .left_click = .{
                                    .row = row - 31,
                                    .col = col - 31,
                                },
                            };
                        },
                    }
                },
            },
        }
    }
}
