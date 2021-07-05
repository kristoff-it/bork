const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

const Cats = @import("../../components.zig").DerivedGeneralCategory;
const EAW = @import("../../components.zig").DerivedEastAsianWidth;
const Emoji = @import("../../components.zig").EmojiData;
const GBP = @import("../../components.zig").GraphemeBreakProperty;
const GraphemeIterator = @import("../../components.zig").GraphemeIterator;
const isAsciiStr = @import("../../ascii.zig").isAsciiStr;

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
    } else if (Cats.isEnclosingMark(cp) or Cats.isNonspacingMark(cp)) {
        // Combining Marks.
        return 0;
    } else if (Cats.isFormat(cp) and (!(cp >= 0x0600 and cp <= 0x0605) and cp != 0x061C and
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
    } else if (EAW.isWide(cp) or EAW.isFullwidth(cp)) {
        return 2;
    } else if (GBP.isRegionalIndicator(cp)) {
        return 2;
    } else if (EAW.isAmbiguous(cp)) {
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

    var giter = try GraphemeIterator.new(str);

    while (giter.next()) |gc| {
        var cp_iter = (try unicode.Utf8View.init(gc.bytes)).iterator();

        while (cp_iter.nextCodepoint()) |cp| {
            var w = codePointWidth(cp, am_width);

            if (w != 0) {
                // Only adding width of first non-zero-width code point.
                if (Emoji.isExtendedPictographic(cp)) {
                    if (cp_iter.nextCodepoint()) |ncp| {
                        // Emoji text sequence.
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
pub fn center(allocator: *mem.Allocator, str: []const u8, total_width: usize, pad: []const u8) ![]u8 {
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
pub fn padLeft(allocator: *mem.Allocator, str: []const u8, total_width: usize, pad: []const u8) ![]u8 {
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
pub fn padRight(allocator: *mem.Allocator, str: []const u8, total_width: usize, pad: []const u8) ![]u8 {
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

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

test "Width Width" {
    try expectEqual(@as(i8, -1), codePointWidth(0x0008, .half)); // \b
    try expectEqual(@as(i8, 0), codePointWidth(0x0000, .half)); // null
    try expectEqual(@as(i8, 0), codePointWidth(0x0005, .half)); // Cf
    try expectEqual(@as(i8, 0), codePointWidth(0x0007, .half)); // \a BEL
    try expectEqual(@as(i8, 0), codePointWidth(0x000A, .half)); // \n LF
    try expectEqual(@as(i8, 0), codePointWidth(0x000B, .half)); // \v VT
    try expectEqual(@as(i8, 0), codePointWidth(0x000C, .half)); // \f FF
    try expectEqual(@as(i8, 0), codePointWidth(0x000D, .half)); // \r CR
    try expectEqual(@as(i8, 0), codePointWidth(0x000E, .half)); // SQ
    try expectEqual(@as(i8, 0), codePointWidth(0x000F, .half)); // SI

    try expectEqual(@as(i8, 0), codePointWidth(0x070F, .half)); // Cf
    try expectEqual(@as(i8, 1), codePointWidth(0x0603, .half)); // Cf Arabic

    try expectEqual(@as(i8, 1), codePointWidth(0x00AD, .half)); // soft-hyphen
    try expectEqual(@as(i8, 2), codePointWidth(0x2E3A, .half)); // two-em dash
    try expectEqual(@as(i8, 3), codePointWidth(0x2E3B, .half)); // three-em dash

    try expectEqual(@as(i8, 1), codePointWidth(0x00BD, .half)); // ambiguous halfwidth
    try expectEqual(@as(i8, 2), codePointWidth(0x00BD, .full)); // ambiguous fullwidth

    try expectEqual(@as(i8, 1), codePointWidth('é', .half));
    try expectEqual(@as(i8, 2), codePointWidth('😊', .half));
    try expectEqual(@as(i8, 2), codePointWidth('统', .half));

    try expectEqual(@as(usize, 5), try strWidth("Hello\r\n", .half));
    try expectEqual(@as(usize, 1), try strWidth("\u{0065}\u{0301}", .half));
    try expectEqual(@as(usize, 2), try strWidth("\u{1F476}\u{1F3FF}\u{0308}\u{200D}\u{1F476}\u{1F3FF}", .half));
    try expectEqual(@as(usize, 8), try strWidth("Hello 😊", .half));
    try expectEqual(@as(usize, 8), try strWidth("Héllo 😊", .half));
    try expectEqual(@as(usize, 8), try strWidth("Héllo :)", .half));
    try expectEqual(@as(usize, 8), try strWidth("Héllo 🇪🇸", .half));
    try expectEqual(@as(usize, 2), try strWidth("\u{26A1}", .half)); // Lone emoji
    try expectEqual(@as(usize, 1), try strWidth("\u{26A1}\u{FE0E}", .half)); // Text sequence
    try expectEqual(@as(usize, 2), try strWidth("\u{26A1}\u{FE0F}", .half)); // Presentation sequence
    try expectEqual(@as(usize, 0), try strWidth("A\x08", .half)); // Backspace
    try expectEqual(@as(usize, 0), try strWidth("\x7FA", .half)); // DEL
    try expectEqual(@as(usize, 0), try strWidth("\x7FA\x08\x08", .half)); // never less than o
}

test "Width center" {
    var allocator = std.testing.allocator;

    var centered = try center(allocator, "abc", 9, "*");
    defer allocator.free(centered);
    try expectEqualSlices(u8, "***abc***", centered);

    allocator.free(centered);
    centered = try center(allocator, "w😊w", 10, "-");
    try expectEqualSlices(u8, "---w😊w---", centered);
}

test "Width padLeft" {
    var allocator = std.testing.allocator;

    var right_aligned = try padLeft(allocator, "abc", 9, "*");
    defer allocator.free(right_aligned);
    try expectEqualSlices(u8, "******abc", right_aligned);

    allocator.free(right_aligned);
    right_aligned = try padLeft(allocator, "w😊w", 10, "-");
    try expectEqualSlices(u8, "------w😊w", right_aligned);
}

test "Width padRight" {
    var allocator = std.testing.allocator;

    var left_aligned = try padRight(allocator, "abc", 9, "*");
    defer allocator.free(left_aligned);
    try expectEqualSlices(u8, "abc******", left_aligned);

    allocator.free(left_aligned);
    left_aligned = try padRight(allocator, "w😊w", 10, "-");
    try expectEqualSlices(u8, "w😊w------", left_aligned);
}
