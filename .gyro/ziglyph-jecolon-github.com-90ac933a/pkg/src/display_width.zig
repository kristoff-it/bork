//! `display_width` provides functions that calculate the display width of a code point or string when displayed in a
//! fixed-width font.

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const unicode = std.unicode;

const cats = @import("ziglyph.zig").derived_general_category;
const eaw = @import("ziglyph.zig").derived_east_asian_width;
const emoji = @import("ziglyph.zig").emoji_data;
const gbp = @import("ziglyph.zig").grapheme_break_property;
const GraphemeIterator = @import("ziglyph.zig").GraphemeIterator;
const isAsciiStr = @import("ascii.zig").isAsciiStr;
const Word = @import("ziglyph.zig").Word;
const WordIterator = Word.WordIterator;

/// AmbiguousWidth determines the width of ambiguous characters according to the context. In an 
/// East Asian context, the width of ambiguous code points should be 2 (full), and 1 (half) 
/// in non-East Asian contexts. The most common use case is `half`.
pub const AmbiguousWidth = enum(u2) {
    half = 1,
    full = 2,
};

/// codePointWidth returns how many cells (or columns) wide `cp` should be when rendered in a
/// fixed-width font.
pub fn codePointWidth(cp: u21, am_width: AmbiguousWidth) i3 {
    if (cp == 0x000 or cp == 0x0005 or cp == 0x0007 or (cp >= 0x000A and cp <= 0x000F)) {
        // Control.
        return 0;
    } else if (cp == 0x0008 or cp == 0x007F) {
        // backspace and DEL
        return -1;
    } else if (cp == 0x00AD) {
        // soft-hyphen
        return 1;
    } else if (cp == 0x2E3A) {
        // two-em dash
        return 2;
    } else if (cp == 0x2E3B) {
        // three-em dash
        return 3;
    } else if (cats.isEnclosingMark(cp) or cats.isNonspacingMark(cp)) {
        // Combining Marks.
        return 0;
    } else if (cats.isFormat(cp) and (!(cp >= 0x0600 and cp <= 0x0605) and cp != 0x061C and
        cp != 0x06DD and cp != 0x08E2))
    {
        // Format except Arabic.
        return 0;
    } else if ((cp >= 0x1160 and cp <= 0x11FF) or (cp >= 0x2060 and cp <= 0x206F) or
        (cp >= 0xFFF0 and cp <= 0xFFF8) or (cp >= 0xE0000 and cp <= 0xE0FFF))
    {
        // Hangul syllable and ignorable.
        return 0;
    } else if ((cp >= 0x3400 and cp <= 0x4DBF) or (cp >= 0x4E00 and cp <= 0x9FFF) or
        (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0x20000 and cp <= 0x2FFFD) or
        (cp >= 0x30000 and cp <= 0x3FFFD))
    {
        return 2;
    } else if (eaw.isWide(cp) or eaw.isFullwidth(cp)) {
        return 2;
    } else if (gbp.isRegionalIndicator(cp)) {
        return 2;
    } else if (eaw.isAmbiguous(cp)) {
        return @enumToInt(am_width);
    } else {
        return 1;
    }
}

/// strWidth returns how many cells (or columns) wide `str` should be when rendered in a
/// fixed-width font.
pub fn strWidth(str: []const u8, am_width: AmbiguousWidth) !usize {
    var total: isize = 0;

    // ASCII bytes are all width == 1.
    if (try isAsciiStr(str)) {
        for (str) |b| {
            // Backspace and DEL
            if (b == 8 or b == 127) {
                total -= 1;
                continue;
            }

            // Control
            if (b < 32) continue;

            // All other ASCII.
            total += 1;
        }

        return if (total > 0) @intCast(usize, total) else 0;
    }

    var giter = try GraphemeIterator.init(str);

    while (giter.next()) |gc| {
        var cp_iter = (try unicode.Utf8View.init(gc.bytes)).iterator();

        while (cp_iter.nextCodepoint()) |cp| {
            var w = codePointWidth(cp, am_width);

            if (w != 0) {
                // Only adding width of first non-zero-width code point.
                if (emoji.isExtendedPictographic(cp)) {
                    if (cp_iter.nextCodepoint()) |ncp| {
                        // emoji text sequence.
                        if (ncp == 0xFE0E) w = 1;
                    }
                }
                total += w;
                break;
            }
        }
    }

    return if (total > 0) @intCast(usize, total) else 0;
}

/// centers `str` in a new string of width `total_width` (in display cells) using `pad` as padding.
/// Caller must free returned bytes.
pub fn center(allocator: mem.Allocator, str: []const u8, total_width: usize, pad: []const u8) ![]u8 {
    var str_width = try strWidth(str, .half);
    if (str_width > total_width) return error.StrTooLong;

    var pad_width = try strWidth(pad, .half);
    if (pad_width > total_width or str_width + pad_width > total_width) return error.PadTooLong;

    const margin_width = @divFloor((total_width - str_width), 2);
    if (pad_width > margin_width) return error.PadTooLong;

    const pads = @divFloor(margin_width, pad_width) * 2;

    var result = try allocator.alloc(u8, pads * pad.len + str.len);
    var bytes_index: usize = 0;
    var pads_index: usize = 0;

    while (pads_index < pads / 2) : (pads_index += 1) {
        mem.copy(u8, result[bytes_index..], pad);
        bytes_index += pad.len;
    }

    mem.copy(u8, result[bytes_index..], str);
    bytes_index += str.len;

    pads_index = 0;
    while (pads_index < pads / 2) : (pads_index += 1) {
        mem.copy(u8, result[bytes_index..], pad);
        bytes_index += pad.len;
    }

    return result;
}

/// padLeft returns a new string of width `total_width` (in display cells) using `pad` as padding
/// on the left side.  Caller must free returned bytes.
pub fn padLeft(allocator: mem.Allocator, str: []const u8, total_width: usize, pad: []const u8) ![]u8 {
    var str_width = try strWidth(str, .half);
    if (str_width > total_width) return error.StrTooLong;

    var pad_width = try strWidth(pad, .half);
    if (pad_width > total_width or str_width + pad_width > total_width) return error.PadTooLong;

    const margin_width = total_width - str_width;
    if (pad_width > margin_width) return error.PadTooLong;

    const pads = @divFloor(margin_width, pad_width);

    var result = try allocator.alloc(u8, pads * pad.len + str.len);
    var bytes_index: usize = 0;
    var pads_index: usize = 0;

    while (pads_index < pads) : (pads_index += 1) {
        mem.copy(u8, result[bytes_index..], pad);
        bytes_index += pad.len;
    }

    mem.copy(u8, result[bytes_index..], str);

    return result;
}

/// padRight returns a new string of width `total_width` (in display cells) using `pad` as padding
/// on the right side.  Caller must free returned bytes.
pub fn padRight(allocator: mem.Allocator, str: []const u8, total_width: usize, pad: []const u8) ![]u8 {
    var str_width = try strWidth(str, .half);
    if (str_width > total_width) return error.StrTooLong;

    var pad_width = try strWidth(pad, .half);
    if (pad_width > total_width or str_width + pad_width > total_width) return error.PadTooLong;

    const margin_width = total_width - str_width;
    if (pad_width > margin_width) return error.PadTooLong;

    const pads = @divFloor(margin_width, pad_width);

    var result = try allocator.alloc(u8, pads * pad.len + str.len);
    var bytes_index: usize = 0;
    var pads_index: usize = 0;

    mem.copy(u8, result[bytes_index..], str);
    bytes_index += str.len;

    while (pads_index < pads) : (pads_index += 1) {
        mem.copy(u8, result[bytes_index..], pad);
        bytes_index += pad.len;
    }

    return result;
}

/// Wraps a string approximately at the given number of colums per line. Threshold defines how far the last column of
/// the last word can be from the edge. Caller must free returned bytes.
pub fn wrap(allocator: std.mem.Allocator, str: []const u8, columns: usize, threshold: usize) ![]u8 {
    var iter = try WordIterator.init(str);
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    var line_width: usize = 0;

    while (iter.next()) |word| {
        if (isLineBreak(word.bytes)) {
            try result.append(' ');
            continue;
        }
        try result.appendSlice(word.bytes);
        line_width += try strWidth(word.bytes, .half);

        if (line_width > columns or columns - line_width <= threshold) {
            try result.append('\n');
            line_width = 0;
        }
    }

    return result.toOwnedSlice();
}

fn isLineBreak(str: []const u8) bool {
    if (std.mem.eql(u8, str, "\r\n")) {
        return true;
    } else if (std.mem.eql(u8, str, "\r")) {
        return true;
    } else if (std.mem.eql(u8, str, "\n")) {
        return true;
    } else {
        return false;
    }
}

test "display_width Width" {
    try testing.expectEqual(@as(i8, -1), codePointWidth(0x0008, .half)); // \b
    try testing.expectEqual(@as(i8, 0), codePointWidth(0x0000, .half)); // null
    try testing.expectEqual(@as(i8, 0), codePointWidth(0x0005, .half)); // Cf
    try testing.expectEqual(@as(i8, 0), codePointWidth(0x0007, .half)); // \a BEL
    try testing.expectEqual(@as(i8, 0), codePointWidth(0x000A, .half)); // \n LF
    try testing.expectEqual(@as(i8, 0), codePointWidth(0x000B, .half)); // \v VT
    try testing.expectEqual(@as(i8, 0), codePointWidth(0x000C, .half)); // \f FF
    try testing.expectEqual(@as(i8, 0), codePointWidth(0x000D, .half)); // \r CR
    try testing.expectEqual(@as(i8, 0), codePointWidth(0x000E, .half)); // SQ
    try testing.expectEqual(@as(i8, 0), codePointWidth(0x000F, .half)); // SI

    try testing.expectEqual(@as(i8, 0), codePointWidth(0x070F, .half)); // Cf
    try testing.expectEqual(@as(i8, 1), codePointWidth(0x0603, .half)); // Cf Arabic

    try testing.expectEqual(@as(i8, 1), codePointWidth(0x00AD, .half)); // soft-hyphen
    try testing.expectEqual(@as(i8, 2), codePointWidth(0x2E3A, .half)); // two-em dash
    try testing.expectEqual(@as(i8, 3), codePointWidth(0x2E3B, .half)); // three-em dash

    try testing.expectEqual(@as(i8, 1), codePointWidth(0x00BD, .half)); // ambiguous halfwidth
    try testing.expectEqual(@as(i8, 2), codePointWidth(0x00BD, .full)); // ambiguous fullwidth

    try testing.expectEqual(@as(i8, 1), codePointWidth('é', .half));
    try testing.expectEqual(@as(i8, 2), codePointWidth('😊', .half));
    try testing.expectEqual(@as(i8, 2), codePointWidth('统', .half));

    try testing.expectEqual(@as(usize, 5), try strWidth("Hello\r\n", .half));
    try testing.expectEqual(@as(usize, 1), try strWidth("\u{0065}\u{0301}", .half));
    try testing.expectEqual(@as(usize, 2), try strWidth("\u{1F476}\u{1F3FF}\u{0308}\u{200D}\u{1F476}\u{1F3FF}", .half));
    try testing.expectEqual(@as(usize, 8), try strWidth("Hello 😊", .half));
    try testing.expectEqual(@as(usize, 8), try strWidth("Héllo 😊", .half));
    try testing.expectEqual(@as(usize, 8), try strWidth("Héllo :)", .half));
    try testing.expectEqual(@as(usize, 8), try strWidth("Héllo 🇪🇸", .half));
    try testing.expectEqual(@as(usize, 2), try strWidth("\u{26A1}", .half)); // Lone emoji
    try testing.expectEqual(@as(usize, 1), try strWidth("\u{26A1}\u{FE0E}", .half)); // Text sequence
    try testing.expectEqual(@as(usize, 2), try strWidth("\u{26A1}\u{FE0F}", .half)); // Presentation sequence
    try testing.expectEqual(@as(usize, 0), try strWidth("A\x08", .half)); // Backspace
    try testing.expectEqual(@as(usize, 0), try strWidth("\x7FA", .half)); // DEL
    try testing.expectEqual(@as(usize, 0), try strWidth("\x7FA\x08\x08", .half)); // never less than o
}

test "display_width center" {
    var allocator = std.testing.allocator;

    var centered = try center(allocator, "abc", 9, "*");
    defer allocator.free(centered);
    try testing.expectEqualSlices(u8, "***abc***", centered);

    allocator.free(centered);
    centered = try center(allocator, "w😊w", 10, "-");
    try testing.expectEqualSlices(u8, "---w😊w---", centered);
}

test "display_width padLeft" {
    var allocator = std.testing.allocator;

    var right_aligned = try padLeft(allocator, "abc", 9, "*");
    defer allocator.free(right_aligned);
    try testing.expectEqualSlices(u8, "******abc", right_aligned);

    allocator.free(right_aligned);
    right_aligned = try padLeft(allocator, "w😊w", 10, "-");
    try testing.expectEqualSlices(u8, "------w😊w", right_aligned);
}

test "display_width padRight" {
    var allocator = std.testing.allocator;

    var left_aligned = try padRight(allocator, "abc", 9, "*");
    defer allocator.free(left_aligned);
    try testing.expectEqualSlices(u8, "abc******", left_aligned);

    allocator.free(left_aligned);
    left_aligned = try padRight(allocator, "w😊w", 10, "-");
    try testing.expectEqualSlices(u8, "w😊w------", left_aligned);
}

test "display_width wrap" {
    var allocator = std.testing.allocator;
    var input = "The quick brown fox\r\njumped over the lazy dog!";
    var got = try wrap(allocator, input, 10, 3);
    defer allocator.free(got);
    var want = "The quick\n brown \nfox jumped\n over the\n lazy dog\n!";
    try testing.expectEqualStrings(want, got);
}
