//! GraphemeIterator retrieves the grapheme clusters of a string, which may be composed of several 
//! code points each.

const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

const CodePointIterator = @import("CodePointIterator.zig");
const Cats = @import("../components.zig").DerivedGeneralCategory;
const GBP = @import("../components.zig").GraphemeBreakProperty;
const Emoji = @import("../components.zig").EmojiData;
pub const Grapheme = @import("Grapheme.zig");
const HangulMap = @import("../components.zig").HangulMap;

ascii_only: bool = false,
cp_iter: CodePointIterator,

const Self = @This();

pub fn new(str: []const u8) !Self {
    return newOpt(str, false);
}

pub fn newAscii(str: []const u8) !Self {
    return newOpt(str, true);
}

fn newOpt(str: []const u8, ascii_only: bool) !Self {
    return Self{
        .ascii_only = ascii_only,
        .cp_iter = try CodePointIterator.init(str),
    };
}

/// reinit reinitializes the iterator with a new string.
pub fn reinit(self: *Self, str: []const u8) !void {
    self.cp_iter = try CodePointIterator.init(str);
}

/// reset resets the iterator to start over.
pub fn reset(self: *Self) void {
    self.cp_iter.reset();
}

// Special code points.
const ZWJ: u21 = 0x200D;
const CR: u21 = 0x000D;
const LF: u21 = 0x000A;

const Slice = struct {
    start: usize,
    end: usize,
};

/// next retrieves the next grapheme cluster.
pub fn next(self: *Self) ?Grapheme {
    // ASCII is just bytes.
    if (self.ascii_only) {
        if (self.cp_iter.i >= self.cp_iter.bytes.len) return null;
        self.cp_iter.i += 1;
        return Grapheme{ .bytes = self.cp_iter.bytes[self.cp_iter.i - 1 .. self.cp_iter.i], .offset = self.cp_iter.i - 1 };
    }

    var cpo = self.cp_iter.next();
    if (cpo == null) return null;
    const cp = cpo.?;
    const cp_end = self.cp_iter.i;
    const cp_start = self.cp_iter.prev_i;
    const next_cp = self.cp_iter.peek();

    // GB9.2
    if (GBP.isPrepend(cp)) {
        if (next_cp) |ncp| {
            if (ncp == CR or ncp == LF or (Cats.isControl(ncp))) {
                return Grapheme{
                    .bytes = self.cp_iter.bytes[cp_start..cp_end],
                    .offset = cp_start,
                };
            }

            const pncp = self.cp_iter.next().?; // We know there's a next.
            const pncp_end = self.cp_iter.i;
            const pncp_start = self.cp_iter.prev_i;
            const pncp_next_cp = self.cp_iter.peek();
            const s = self.processNonPrepend(pncp, pncp_start, pncp_end, pncp_next_cp);
            return Grapheme{
                .bytes = self.cp_iter.bytes[cp_start..s.end],
                .offset = cp_start,
            };
        }

        return Grapheme{
            .bytes = self.cp_iter.bytes[cp_start..cp_end],
            .offset = cp_start,
        };
    }

    const s = self.processNonPrepend(cp, cp_start, cp_end, next_cp);
    return Grapheme{
        .bytes = self.cp_iter.bytes[s.start..s.end],
        .offset = s.start,
    };
}

fn processNonPrepend(
    self: *Self,
    cp: u21,
    cp_start: usize,
    cp_end: usize,
    next_cp: ?u21,
) Slice {
    // GB3, GB4, GB5
    if (cp == CR) {
        if (next_cp) |ncp| {
            if (ncp == LF) {
                _ = self.cp_iter.next(); // Advance past LF.
                return Slice{ .start = cp_start, .end = self.cp_iter.i };
            }
        }
        return Slice{ .start = cp_start, .end = cp_end };
    }

    if (cp == LF) {
        return Slice{ .start = cp_start, .end = cp_end };
    }

    if (Cats.isControl(cp)) {
        return Slice{ .start = cp_start, .end = cp_end };
    }

    // GB6, GB7, GB8
    if (HangulMap.syllableType(cp)) |hst| {
        if (next_cp) |ncp| {
            const ncp_hst = HangulMap.syllableType(ncp);

            if (ncp_hst) |nhst| {
                switch (hst) {
                    .L => {
                        if (nhst == .L or nhst == .V or nhst == .LV or nhst == .LVT) {
                            _ = self.cp_iter.next(); // Advance past next syllable.
                        }
                    },
                    .LV, .V => {
                        if (nhst == .V or nhst == .T) {
                            _ = self.cp_iter.next(); // Advance past next syllable.
                        }
                    },
                    .LVT, .T => {
                        if (nhst == .T) {
                            _ = self.cp_iter.next(); // Advance past next syllable.
                        }
                    },
                }
            }
        }

        // GB9
        self.fullAdvance();
        return Slice{ .start = cp_start, .end = self.cp_iter.i };
    }

    // GB11
    if (Emoji.isExtendedPictographic(cp)) {
        self.fullAdvance();
        if (self.cp_iter.prev) |pcp| {
            if (pcp == ZWJ) {
                if (self.cp_iter.peek()) |ncp| {
                    if (Emoji.isExtendedPictographic(ncp)) {
                        _ = self.cp_iter.next(); // Advance past end emoji.
                        // GB9
                        self.fullAdvance();
                    }
                }
            }
        }

        return Slice{ .start = cp_start, .end = self.cp_iter.i };
    }

    // GB12
    if (GBP.isRegionalIndicator(cp)) {
        if (next_cp) |ncp| {
            if (GBP.isRegionalIndicator(ncp)) {
                _ = self.cp_iter.next(); // Advance past 2nd RI.
            }
        }

        self.fullAdvance();
        return Slice{ .start = cp_start, .end = self.cp_iter.i };
    }

    // GB999
    self.fullAdvance();
    return Slice{ .start = cp_start, .end = self.cp_iter.i };
}

fn lexRun(
    self: *Self,
    comptime predicate: fn (cp: u21) bool,
) void {
    while (self.cp_iter.peek()) |ncp| {
        if (!predicate(ncp)) break;
        _ = self.cp_iter.next();
    }
}

fn fullAdvance(self: *Self) void {
    const next_cp = self.cp_iter.peek();
    // Base case.
    if (next_cp) |ncp| {
        if (ncp != ZWJ and !GBP.isExtend(ncp) and !Cats.isSpacingMark(ncp)) return;
    } else {
        return;
    }

    // Recurse.
    const ncp = next_cp.?; // We now we have next.

    if (ncp == ZWJ) {
        _ = self.cp_iter.next();
        self.fullAdvance();
    } else if (GBP.isExtend(ncp)) {
        self.lexRun(GBP.isExtend);
        self.fullAdvance();
    } else if (Cats.isSpacingMark(ncp)) {
        self.lexRun(Cats.isSpacingMark);
        self.fullAdvance();
    }
}

test "Grapheme ASCII" {
    var iter = try newAscii("Hi!");

    try std.testing.expectEqualStrings(iter.next().?.bytes, "H");
    try std.testing.expectEqualStrings(iter.next().?.bytes, "i");
    try std.testing.expectEqualStrings(iter.next().?.bytes, "!");
    try std.testing.expect(iter.next() == null);
}

test "Grapheme iterator" {
    var path_buf: [1024]u8 = undefined;
    var path = try std.fs.cwd().realpath(".", &path_buf);
    // Check if testing in this library path.
    if (!mem.endsWith(u8, path, "ziglyph")) return;

    var allocator = std.testing.allocator;
    var file = try std.fs.cwd().openFile("src/data/ucd/GraphemeBreakTest.txt", .{});
    defer file.close();
    var buf_reader = std.io.bufferedReader(file.reader());
    var input_stream = buf_reader.reader();

    var buf: [640]u8 = undefined;
    var line_no: usize = 1;

    while (try input_stream.readUntilDelimiterOrEof(&buf, '\n')) |raw| : (line_no += 1) {
        // Skip comments or empty lines.
        if (raw.len == 0 or raw[0] == '#' or raw[0] == '@') continue;

        // Clean up.
        var line = mem.trimLeft(u8, raw, "÷ ");
        if (mem.indexOf(u8, line, " ÷\t#")) |octo| {
            line = line[0..octo];
        }

        // Iterate over fields.
        var want = std.ArrayList(Grapheme).init(allocator);
        defer {
            for (want.items) |gc| {
                allocator.free(gc.bytes);
            }
            want.deinit();
        }
        var all_bytes = std.ArrayList(u8).init(allocator);
        defer all_bytes.deinit();
        var graphemes = mem.split(line, " ÷ ");
        var bytes_index: usize = 0;

        while (graphemes.next()) |field| {
            var code_points = mem.split(field, " ");
            var cp_buf: [4]u8 = undefined;
            var cp_index: usize = 0;
            var first: u21 = undefined;
            var cp_bytes = std.ArrayList(u8).init(allocator);
            defer cp_bytes.deinit();

            while (code_points.next()) |code_point| {
                if (mem.eql(u8, code_point, "×")) continue;
                const cp: u21 = try std.fmt.parseInt(u21, code_point, 16);
                if (cp_index == 0) first = cp;
                const len = try unicode.utf8Encode(cp, &cp_buf);
                try all_bytes.appendSlice(cp_buf[0..len]);
                try cp_bytes.appendSlice(cp_buf[0..len]);
                cp_index += len;
            }

            try want.append(Grapheme{
                .bytes = cp_bytes.toOwnedSlice(),
                .offset = bytes_index,
            });

            bytes_index += cp_index;
        }

        var giter = try new(all_bytes.items);

        // Chaeck.
        for (want.items) |w| {
            const g = (giter.next()).?;
            //std.debug.print("line {d}: w:({s}), g:({s})\n", .{ line_no, w.bytes, g.bytes });
            try std.testing.expect(w.eql(g.bytes));
            try std.testing.expectEqual(w.offset, g.offset);
        }
    }
}
