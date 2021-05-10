//! GraphemeIterator retrieves the grapheme clusters of a string, which may be composed of several 
//! code points each.

const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

const CodePointIterator = @import("CodePointIterator.zig");
const Control = @import("../components.zig").Control;
const Extend = @import("../components.zig").Extend;
const ExtPic = @import("../components.zig").ExtPic;
pub const Grapheme = @import("Grapheme.zig");
const HangulMap = @import("../components.zig").HangulMap;
const Prepend = @import("../components.zig").Prepend;
const Regional = @import("../components.zig").Regional;
const Spacing = @import("../components.zig").Spacing;

control: Control,
cp_iter: CodePointIterator,
extend: Extend,
extpic: ExtPic,
hangul_map: HangulMap,
prepend: Prepend,
regional: Regional,
spacing: Spacing,

const Self = @This();

pub fn new(str: []const u8) !Self {
    return Self{
        .control = Control{},
        .cp_iter = try CodePointIterator.init(str),
        .extend = Extend{},
        .extpic = ExtPic{},
        .hangul_map = HangulMap{},
        .prepend = Prepend{},
        .regional = Regional{},
        .spacing = Spacing{},
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
    var cpo = self.cp_iter.next();
    if (cpo == null) return null;
    const cp = cpo.?;
    const cp_end = self.cp_iter.i;
    const cp_start = self.cp_iter.prev_i;
    const next_cp = self.cp_iter.peek();

    // GB9.2
    if (self.prepend.isPrepend(cp)) {
        if (next_cp) |ncp| {
            if (ncp == CR or ncp == LF or (self.control.isControl(ncp))) {
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

    if (self.control.isControl(cp)) {
        return Slice{ .start = cp_start, .end = cp_end };
    }

    // GB6, GB7, GB8
    if (self.hangul_map.syllableType(cp)) |hst| {
        if (next_cp) |ncp| {
            const ncp_hst = self.hangul_map.syllableType(ncp);

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
    if (self.extpic.isExtendedPictographic(cp)) {
        self.fullAdvance();
        if (self.cp_iter.prev) |pcp| {
            if (pcp == ZWJ) {
                if (self.cp_iter.peek()) |ncp| {
                    if (self.extpic.isExtendedPictographic(ncp)) {
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
    if (self.regional.isRegionalIndicator(cp)) {
        if (next_cp) |ncp| {
            if (self.regional.isRegionalIndicator(ncp)) {
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
    ctx: anytype,
    comptime predicate: fn (ctx: @TypeOf(ctx), cp: u21) bool,
) void {
    while (self.cp_iter.peek()) |ncp| {
        if (!predicate(ctx, ncp)) break;
        _ = self.cp_iter.next();
    }
}

fn fullAdvance(self: *Self) void {
    const next_cp = self.cp_iter.peek();
    // Base case.
    if (next_cp) |ncp| {
        if (ncp != ZWJ and !self.extend.isExtend(ncp) and !self.spacing.isSpacingMark(ncp)) return;
    } else {
        return;
    }

    // Recurse.
    const ncp = next_cp.?; // We now we have next.

    if (ncp == ZWJ) {
        _ = self.cp_iter.next();
        self.fullAdvance();
    } else if (self.extend.isExtend(ncp)) {
        self.lexRun(self.extend, Extend.isExtend);
        self.fullAdvance();
    } else if (self.spacing.isSpacingMark(ncp)) {
        self.lexRun(self.spacing, Spacing.isSpacingMark);
        self.fullAdvance();
    }
}

test "Grapheme iterator" {
    var allocator = std.testing.allocator;
    var file = try std.fs.cwd().openFile("src/data/ucd/auxiliary/GraphemeBreakTest.txt", .{});
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
            std.testing.expect(w.sameAs(g));
        }
    }
}

test "Grapheme width" {
    _ = @import("../components/aggregate/Width.zig");
}
