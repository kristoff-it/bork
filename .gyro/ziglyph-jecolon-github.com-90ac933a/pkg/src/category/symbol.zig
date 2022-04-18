//! `symbol` contains functions for the Symbol (S) Unicode category.

const std = @import("std");
const testing = std.testing;

const ascii = @import("../ascii.zig");
const cats = @import("../ziglyph.zig").derived_general_category;

// `isSymbol` detects symbols which curiosly may include some code points commonly thought of as punctuation.
pub fn isSymbol(cp: u21) bool {
    return cats.isMathSymbol(cp) or cats.isModifierSymbol(cp) or cats.isCurrencySymbol(cp) or cats.isOtherSymbol(cp);
}

/// `isAsciiSymbol` detects ASCII only symbols.
pub fn isAsciiSymbol(cp: u21) bool {
    return ascii.isSymbol(@intCast(u8, cp));
}

test "symbol isSymbol" {
    try testing.expect(isAsciiSymbol('<'));
    try testing.expect(isSymbol('<'));
    try testing.expect(isSymbol('>'));
    try testing.expect(isSymbol('='));
    try testing.expect(isSymbol('$'));
    try testing.expect(isSymbol('^'));
    try testing.expect(isSymbol('+'));
    try testing.expect(isSymbol('|'));
    try testing.expect(!isSymbol('A'));
    try testing.expect(!isSymbol('?'));
}
