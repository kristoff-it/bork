//! `mark` contains a function to detect Unicode marks, category (M).

const std = @import("std");
const testing = std.testing;

const cats = @import("../ziglyph.zig").derived_general_category;

/// `isMark` detects any type of Unicode mark (M) code point.
pub fn isMark(cp: u21) bool {
    return cats.isSpacingMark(cp) or cats.isNonspacingMark(cp) or cats.isEnclosingMark(cp);
}

test "mark isMark" {
    try testing.expect(isMark('\u{20E4}'));
    try testing.expect(isMark(0x0301));
    try testing.expect(!isMark('='));
}
