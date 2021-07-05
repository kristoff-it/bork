const std = @import("std");
const ascii = @import("../../ascii.zig");

pub const Cats = @import("../../components.zig").DerivedGeneralCategory;

// isSymbol detects symbols which curiosly may include some code points commonly thought of as
// punctuation.
pub fn isSymbol(cp: u21) bool {
    return Cats.isMathSymbol(cp) or Cats.isModifierSymbol(cp) or Cats.isCurrencySymbol(cp) or Cats.isOtherSymbol(cp);
}

/// isAsciiSymbol detects ASCII only symbols.
pub fn isAsciiSymbol(cp: u21) bool {
    return if (cp < 128) ascii.isSymbol(@intCast(u8, cp)) else false;
}

const expect = std.testing.expect;

test "Component isSymbol" {
    try expect(isSymbol('<'));
    try expect(isSymbol('>'));
    try expect(isSymbol('='));
    try expect(isSymbol('$'));
    try expect(isSymbol('^'));
    try expect(isSymbol('+'));
    try expect(isSymbol('|'));
    try expect(!isSymbol('A'));
    try expect(!isSymbol('?'));
}
