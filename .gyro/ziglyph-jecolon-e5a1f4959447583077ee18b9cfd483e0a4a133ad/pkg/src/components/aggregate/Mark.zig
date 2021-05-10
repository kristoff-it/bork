const std = @import("std");

pub const Enclosing = @import("../../components.zig").Enclosing;
pub const Nonspacing = @import("../../components.zig").Nonspacing;
pub const Spacing = @import("../../components.zig").Spacing;

const Self = @This();

enclosing: Enclosing,
nonspacing: Nonspacing,
spacing: Spacing,

pub fn new() Self {
    return Self{
        .enclosing = Enclosing{},
        .nonspacing = Nonspacing{},
        .spacing = Spacing{},
    };
}

/// isMark detects special code points that serve as marks in different alphabets.
pub fn isMark(self: Self, cp: u21) bool {
    return self.spacing.isSpacingMark(cp) or self.nonspacing.isNonspacingMark(cp) or self.enclosing.isEnclosingMark(cp);
}

const expect = std.testing.expect;

test "Component isMark" {
    var mark = new();

    expect(mark.isMark('\u{20E4}'));
    expect(!mark.isMark('='));
}
