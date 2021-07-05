const std = @import("std");

pub const Cats = @import("../../components.zig").DerivedGeneralCategory;

/// isMark detects special code points that serve as marks in different alphabets.
pub fn isMark(cp: u21) bool {
    return Cats.isSpacingMark(cp) or Cats.isNonspacingMark(cp) or Cats.isEnclosingMark(cp);
}

const expect = std.testing.expect;

test "Component isMark" {
    try expect(isMark('\u{20E4}'));
    try expect(!isMark('='));
}
