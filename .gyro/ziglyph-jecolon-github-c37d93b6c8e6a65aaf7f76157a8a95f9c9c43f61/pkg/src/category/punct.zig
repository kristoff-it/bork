//! `punct` containes functions related to Unicode punctuation code points; category (P).

const std = @import("std");
const testing = std.testing;

const ascii = @import("../ascii.zig");
const cats = @import("../ziglyph.zig").derived_general_category;

/// `isPunct` detects punctuation characters. Note some punctuation maybe considered symbols by Unicode.
pub fn isPunct(cp: u21) bool {
    return cats.isClosePunctuation(cp) or cats.isConnectorPunctuation(cp) or
        cats.isDashPunctuation(cp) or cats.isFinalPunctuation(cp) or
        cats.isInitialPunctuation(cp) or cats.isOpenPunctuation(cp) or
        cats.isOtherPunctuation(cp);
}

/// `isAsciiPunct` detects ASCII only punctuation.
pub fn isAsciiPunct(cp: u21) bool {
    return ascii.isPunct(@intCast(u8, cp));
}

test "punct isPunct" {
    try testing.expect(isAsciiPunct('!'));
    try testing.expect(isPunct('!'));
    try testing.expect(isPunct('?'));
    try testing.expect(isPunct(','));
    try testing.expect(isPunct('.'));
    try testing.expect(isPunct(':'));
    try testing.expect(isPunct(';'));
    try testing.expect(isPunct('\''));
    try testing.expect(isPunct('"'));
    try testing.expect(isPunct('¿'));
    try testing.expect(isPunct('¡'));
    try testing.expect(isPunct('-'));
    try testing.expect(isPunct('('));
    try testing.expect(isPunct(')'));
    try testing.expect(isPunct('{'));
    try testing.expect(isPunct('}'));
    try testing.expect(isPunct('–'));
    // Punct? in Unicode.
    try testing.expect(isPunct('@'));
    try testing.expect(isPunct('#'));
    try testing.expect(isPunct('%'));
    try testing.expect(isPunct('&'));
    try testing.expect(isPunct('*'));
    try testing.expect(isPunct('_'));
    try testing.expect(isPunct('/'));
    try testing.expect(isPunct('\\'));
    try testing.expect(!isPunct('\u{0003}'));
}
