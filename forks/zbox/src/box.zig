const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;
const Allocator = mem.Allocator;
pub const term = @import("prim.zig");

// promote some primitive ops
pub const size = term.size;
pub const ignoreSignalInput = term.ignoreSignalInput;
pub const handleSignalInput = term.handleSignalInput;
pub const cursorShow = term.cursorShow;
pub const cursorHide = term.cursorHide;
pub const nextEvent = term.nextEvent;
pub const clear = term.clear;
pub const Event = term.Event;

pub const ErrorSet = struct {
    pub const Term = term.ErrorSet;
    pub const Write = Term.Write || std.os.WriteError;
    pub const Utf8Encode = error{
        Utf8CannotEncodeSurrogateHalf,
        CodepointTooLarge,
    };
};

usingnamespace @import("util.zig");

// Pizzatime!
pub var is_kitty = false;
const InteractiveElement = @import("../../../src/Terminal.zig").InteractiveElement;

/// must be called before any buffers are `push`ed to the terminal.
pub fn init(allocator: *Allocator) ErrorSet.Term.Setup!void {
    front = try Buffer.init(allocator, 24, 80);
    errdefer front.deinit();

    try term.setup(allocator);
}

/// should be called prior to program exit
pub fn deinit() void {
    front.deinit();
    term.teardown();
}

/// compare state of input buffer to a buffer tracking display state
/// and send changes to the terminal.
pub fn push(buffer: Buffer) (Allocator.Error || ErrorSet.Utf8Encode || ErrorSet.Write)!void {

    // resizing the front buffer naively can lead to artifacting
    // if we do not clear the terminal here.
    if ((buffer.width != front.width) or (buffer.height != front.height)) {
        try term.clear();
        front.clear();
    }

    try front.resize(buffer.height, buffer.width);
    var row: usize = 0;

    try term.beginSync();
    while (row < buffer.height) : (row += 1) {
        var col: usize = 0;
        var last_touched: usize = 0; // out of bounds, can't match col
        var last_image_out = false;
        while (col < buffer.width) : (col += 1) {
            const must_repaint = last_image_out;
            if ((front.cell(row, col).emote_idx != 0) and
                (buffer.cell(row, col).emote_idx == 0))
            {
                last_image_out = true;
            }

            // go to the next character if these are the same.
            if ((!must_repaint and !is_kitty) and Cell.eql(
                front.cell(row, col),
                buffer.cell(row, col),
            )) continue;

            // only send cursor movement sequence if the last modified
            // cell was not the immediately previous cell in this row
            if (last_touched != col)
                try term.cursorTo(row, col);

            last_touched = col;

            const cell = buffer.cell(row, col);
            front.cellRef(row, col).* = cell;
            if (cell.emote_idx != 0) {
                try term.sendSGR(cell.attribs);
                try term.getWriter().print(
                    "\x1b_Gf=100,t=d,a=p,r=1,c=2,i={d};\x1b\\",
                    .{cell.emote_idx},
                );
                if (is_kitty) {
                    try term.cursorTo(row, col);
                    try term.send(" ");
                } else {
                    col += 1;
                    const c = buffer.cell(row, col);
                    front.cellRef(row, col).* = c;
                    last_touched = col;
                }
            } else {
                var codepoint: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(cell.char, &codepoint);

                try term.sendSGR(cell.attribs);
                try term.send(codepoint[0..len]);
            }
        }
    }
    try term.endSync();

    try term.flush();
}

/// structure that represents a single textual character on screen
pub const Cell = struct {
    attribs: term.SGR = term.SGR{},
    char: u21 = ' ',
    emote_idx: u32 = 0,

    interactive_element: InteractiveElement = .none,

    is_transparent: bool = false,

    // TODO: differing metadata should not issue a terminal reprint,
    //       it should just cause the cell to be transferred over to
    //       the front buffer.
    fn eql(self: Cell, other: Cell) bool {
        return self.char == other.char and
            self.attribs.eql(other.attribs) and
            self.emote_idx == other.emote_idx and
            std.meta.eql(self.interactive_element, other.interactive_element);
    }
};

/// structure on which terminal drawing and printing operations are performed.
pub const Buffer = struct {
    data: []Cell,
    height: usize,
    width: usize,

    allocator: *Allocator,

    pub const Writer = std.io.Writer(
        *WriteCursor,
        WriteCursor.Error,
        WriteCursor.writeFn,
    );

    /// State tracking for an `io.Writer` into a `Buffer`. Buffers do not hold onto
    /// any information about cursor position, so a sequential operations like writing to
    /// it is not well defined without a helper like this.
    pub const WriteCursor = struct {
        row_num: usize,
        col_num: usize,
        /// wrap determines how to continue writing when the the text meets
        /// the last column in a row. In truncate mode, the text until the next newline
        /// is dropped. In wrap mode, input is moved to the first column of the next row.
        wrap: bool = false,

        attribs: term.SGR = term.SGR{},
        buffer: *Buffer,

        interactive_element: InteractiveElement = .none,

        const Error = error{ InvalidUtf8, InvalidCharacter };

        fn writeFn(self: *WriteCursor, bytes: []const u8) Error!usize {
            if (self.row_num >= self.buffer.height) return 0;

            var cp_iter = (try std.unicode.Utf8View.init(bytes)).iterator();
            var bytes_written: usize = 0;
            while (cp_iter.nextCodepoint()) |cp| {
                if (self.col_num >= self.buffer.width and self.wrap) {
                    self.col_num = 0;
                    self.row_num += 1;
                }
                if (self.row_num >= self.buffer.height) return bytes_written;

                switch (cp) {
                    //TODO: handle other line endings and return an error when
                    // encountering unpritable or width-breaking codepoints.
                    '\n' => {
                        self.col_num = 0;
                        self.row_num += 1;
                    },
                    else => {
                        if (self.col_num < self.buffer.width)
                            self.buffer.cellRef(self.row_num, self.col_num).* = .{
                                .char = cp,
                                .attribs = self.attribs,
                                .interactive_element = self.interactive_element,
                                .is_transparent = false,
                            };
                        self.col_num += 1;
                    },
                }
                bytes_written = cp_iter.i;
            }
            return bytes_written;
        }

        pub fn writer(self: *WriteCursor) Writer {
            return .{ .context = self };
        }
    };

    /// constructs a `WriteCursor` for the buffer at a given offset.
    pub fn cursorAt(self: *Buffer, row_num: usize, col_num: usize) WriteCursor {
        return .{
            .row_num = row_num,
            .col_num = col_num,
            .buffer = self,
        };
    }

    /// constructs a `WriteCursor` for the buffer at a given offset. data written
    /// through a wrapped cursor wraps around to the next line when it reaches the right
    /// edge of the row.
    pub fn wrappedCursorAt(self: *Buffer, row_num: usize, col_num: usize) WriteCursor {
        var cursor = self.cursorAt(row_num, col_num);
        cursor.wrap = true;
        return cursor;
    }

    pub fn clear(self: *Buffer) void {
        mem.set(Cell, self.data, .{});
    }

    pub fn init(allocator: *Allocator, height: usize, width: usize) Allocator.Error!Buffer {
        var self = Buffer{
            .data = try allocator.alloc(Cell, width * height),
            .width = width,
            .height = height,
            .allocator = allocator,
        };
        self.clear();
        return self;
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.data);
    }

    /// return a slice representing a row at a given context. Generic over the constness
    /// of self; if the buffer is const, the slice elements are const.
    pub fn row(self: anytype, row_num: usize) RowType: {
        switch (@typeInfo(@TypeOf(self))) {
            .Pointer => |p| {
                if (p.child != Buffer) @compileError("expected Buffer");
                if (p.is_const)
                    break :RowType []const Cell
                else
                    break :RowType []Cell;
            },
            else => {
                if (@TypeOf(self) != Buffer) @compileError("expected Buffer");
                break :RowType []const Cell;
            },
        }
    } {
        assert(row_num < self.height);
        const row_idx = row_num * self.width;
        return self.data[row_idx .. row_idx + self.width];
    }

    /// return a reference to the cell at the given row and column number. generic over
    /// the constness of self; if self is const, the cell pointed to is also const.
    pub fn cellRef(self: anytype, row_num: usize, col_num: usize) RefType: {
        switch (@typeInfo(@TypeOf(self))) {
            .Pointer => |p| {
                if (p.child != Buffer) @compileError("expected Buffer");
                if (p.is_const)
                    break :RefType *const Cell
                else
                    break :RefType *Cell;
            },
            else => {
                if (@TypeOf(self) != Buffer) @compileError("expected Buffer");
                break :RefType *const Cell;
            },
        }
    } {
        assert(col_num < self.width);

        return &self.row(row_num)[col_num];
    }

    /// return a copy of the cell at a given offset
    pub fn cell(self: Buffer, row_num: usize, col_num: usize) Cell {
        assert(col_num < self.width);
        return self.row(row_num)[col_num];
    }

    /// fill a buffer with the given cell
    pub fn fill(self: *Buffer, a_cell: Cell) void {
        mem.set(Cell, self.data, a_cell);
    }

    /// grows or shrinks a cell buffer ensuring alignment by line and column
    /// data is lost in shrunk dimensions, and new space is initialized
    /// as the default cell in grown dimensions.
    pub fn resize(self: *Buffer, height: usize, width: usize) Allocator.Error!void {
        if (self.height == height and self.width == width) return;
        //TODO: figure out more ways to minimize unnecessary reallocation and
        //redrawing here. for instance:
        // `if self.width < width and self.height < self.height` no redraw or
        // realloc required
        // more difficult:
        // `if self.width * self.height >= width * height` requires redraw
        // but could possibly use some sort of scratch buffer thing.
        const old = self.*;
        self.* = .{
            .allocator = old.allocator,
            .width = width,
            .height = height,
            .data = try old.allocator.alloc(Cell, width * height),
        };

        if (width > old.width or
            height > old.height) self.clear();

        const min_height = math.min(old.height, height);
        const min_width = math.min(old.width, width);

        var n: usize = 0;
        while (n < min_height) : (n += 1) {
            mem.copy(Cell, self.row(n), old.row(n)[0..min_width]);
        }
        self.allocator.free(old.data);
    }

    // draw the contents of 'other' on top of the contents of self at the provided
    // offset. anything out of bounds of the destination is ignored. row_num and col_num
    // are still 1-indexed; this means 0 is out of bounds by 1, and -1 is out of bounds
    // by 2. This may change.
    pub fn blit(self: *Buffer, other: Buffer, row_num: isize, col_num: isize) void {
        var self_row_idx = row_num;
        var other_row_idx: usize = 0;

        while (self_row_idx < self.height and other_row_idx < other.height) : ({
            self_row_idx += 1;
            other_row_idx += 1;
        }) {
            if (self_row_idx < 0) continue;

            var self_col_idx = col_num;
            var other_col_idx: usize = 0;

            while (self_col_idx < self.width and other_col_idx < other.width) : ({
                self_col_idx += 1;
                other_col_idx += 1;
            }) {
                if (self_col_idx < 0) continue;

                if (other.cell(other_row_idx, other_col_idx).is_transparent) {
                    continue;
                }

                self.cellRef(
                    @intCast(usize, self_row_idx),
                    @intCast(usize, self_col_idx),
                ).* = other.cell(other_row_idx, other_col_idx);
            }
        }
    }

    // std.fmt compatibility for debugging
    pub fn format(
        self: Buffer,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        var row_num: usize = 0;
        try writer.print("\n\x1B[4m|", .{});

        while (row_num < self.height) : (row_num += 1) {
            for (self.row(row_num)) |this_cell| {
                var utf8Seq: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(this_cell.char, &utf8Seq) catch unreachable;
                try writer.print("{}|", .{utf8Seq[0..len]});
            }

            if (row_num != self.height - 1)
                try writer.print("\n|", .{});
        }

        try writer.print("\x1B[0m\n", .{});
    }
};

const Size = struct {
    height: usize,
    width: usize,
};
/// represents the last drawn state of the terminal
pub var front: Buffer = undefined;

// tests ///////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
test "Buffer.resize()" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    // newly initialized buffer should have all cells set to default value
    for (buffer.data) |cell| {
        std.testing.expectEqual(Cell{}, cell);
    }
    for (buffer.row(4)[0..3]) |*cell| {
        cell.char = '.';
    }

    try buffer.resize(5, 12);

    // make sure data is preserved between resizes
    for (buffer.row(4)[0..3]) |cell| {
        std.testing.expectEqual(@as(u21, '.'), cell.char);
    }

    // ensure nothing weird was written to expanded rows
    for (buffer.row(2)[3..]) |cell| {
        std.testing.expectEqual(Cell{}, cell);
    }
}

// most useful tests of this are function tests
// see `examples/`
test "buffer.cellRef()" {
    var buffer = try Buffer.init(std.testing.allocator, 1, 1);
    defer buffer.deinit();

    const ref = buffer.cellRef(0, 0);
    ref.* = Cell{ .char = '.' };

    std.testing.expectEqual(@as(u21, '.'), buffer.cell(0, 0).char);
}

test "buffer.cursorAt()" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    var cursor = buffer.cursorAt(9, 5);
    const n = try cursor.writer().write("hello!!!!!\n!!!!");

    std.debug.print("{}", .{buffer});

    std.testing.expectEqual(@as(usize, 11), n);
}

test "Buffer.blit()" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var alloc = &arena.allocator;
    var buffer1 = try Buffer.init(alloc, 10, 10);
    var buffer2 = try Buffer.init(alloc, 5, 5);
    buffer2.fill(.{ .char = '#' });
    std.debug.print("{}", .{buffer2});
    std.debug.print("blit(-2,6)", .{});
    buffer1.blit(buffer2, -2, 6);
    std.debug.print("{}", .{buffer1});
}

test "wrappedWrite" {
    var buffer = try Buffer.init(std.testing.allocator, 5, 5);
    defer buffer.deinit();

    var cursor = buffer.wrappedCursorAt(4, 0);

    const n = try cursor.writer().write("hello!!!!!");

    std.debug.print("{}", .{buffer});

    std.testing.expectEqual(@as(usize, 5), n);
}

test "static anal" {
    std.meta.refAllDecls(@This());
    std.meta.refAllDecls(Cell);
    std.meta.refAllDecls(Buffer);
    std.meta.refAllDecls(Buffer.WriteCursor);
}
