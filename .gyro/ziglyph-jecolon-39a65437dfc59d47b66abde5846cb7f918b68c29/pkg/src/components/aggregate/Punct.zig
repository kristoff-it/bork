const std = @import("std");
const ascii = @import("../../ascii.zig");

pub const Cats = @import("../../components.zig").DerivedGeneralCategory;

/// isPunct detects punctuation characters. Note some punctuation maybe considered symbols by Unicode.
pub fn isPunct(cp: u21) bool {
    return Cats.isClosePunctuation(cp) or Cats.isConnectorPunctuation(cp) or
        Cats.isDashPunctuation(cp) or Cats.isFinalPunctuation(cp) or
        Cats.isInitialPunctuation(cp) or Cats.isOpenPunctuation(cp) or
        Cats.isOtherPunctuation(cp);
}

/// isAsciiPunct detects ASCII only punctuation.
pub fn isAsciiPunct(cp: u21) bool {
    return if (cp < 128) ascii.isPunct(@intCast(u8, cp)) else false;
}

const expect = std.testing.expect;

test "Component isPunct" {
    try expect(isPunct('!'));
    try expect(isPunct('?'));
    try expect(isPunct(','));
    try expect(isPunct('.'));
    try expect(isPunct(':'));
    try expect(isPunct(';'));
    try expect(isPunct('\''));
    try expect(isPunct('"'));
    try expect(isPunct('¿'));
    try expect(isPunct('¡'));
    try expect(isPunct('-'));
    try expect(isPunct('('));
    try expect(isPunct(')'));
    try expect(isPunct('{'));
    try expect(isPunct('}'));
    try expect(isPunct('–'));
    // Punct? in Unicode.
    try expect(isPunct('@'));
    try expect(isPunct('#'));
    try expect(isPunct('%'));
    try expect(isPunct('&'));
    try expect(isPunct('*'));
    try expect(isPunct('_'));
    try expect(isPunct('/'));
    try expect(isPunct('\\'));
    try expect(!isPunct('\u{0003}'));
}
