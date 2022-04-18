//! `number` contains functions related to Unicode numbers; category (N).

const std = @import("std");
const testing = std.testing;

const cats = @import("../ziglyph.zig").derived_general_category;
const numeric = @import("../ziglyph.zig").derived_numeric_type;
const props = @import("../ziglyph.zig").prop_list;

/// `isDecimal` detects all Unicode decimal numbers.
pub fn isDecimal(cp: u21) bool {
    // ASCII optimization.
    if (cp >= '0' and cp <= '9') return true;
    return numeric.isDecimal(cp);
}

/// `isDigit` detects all Unicode digits..
pub fn isDigit(cp: u21) bool {
    // ASCII optimization.
    if (cp >= '0' and cp <= '9') return true;
    return numeric.isDigit(cp) or isDecimal(cp);
}

/// `isAsciiDigit` detects ASCII only digits.
pub fn isAsciiDigit(cp: u21) bool {
    return cp >= '0' and cp <= '9';
}

/// `isHex` detects the 16 ASCII characters 0-9 A-F, and a-f.
pub fn isHexDigit(cp: u21) bool {
    // ASCII optimization.
    if ((cp >= 'a' and cp <= 'f') or (cp >= 'A' and cp <= 'F') or (cp >= '0' and cp <= '9')) return true;
    return props.isHexDigit(cp);
}

/// `isAsciiHexDigit` detects ASCII only hexadecimal digits.
pub fn isAsciiHexDigit(cp: u21) bool {
    return (cp >= 'a' and cp <= 'f') or (cp >= 'A' and cp <= 'F') or (cp >= '0' and cp <= '9');
}

/// `isNumber` covers all Unicode numbers, not just ASII.
pub fn isNumber(cp: u21) bool {
    // ASCII optimization.
    if (cp >= '0' and cp <= '9') return true;
    return isDecimal(cp) or isDigit(cp) or cats.isLetterNumber(cp) or cats.isOtherNumber(cp);
}

/// isAsciiNumber detects ASCII only numbers.
pub fn isAsciiNumber(cp: u21) bool {
    return cp >= '0' and cp <= '9';
}

test "number isDecimal" {
    var cp: u21 = '0';
    while (cp <= '9') : (cp += 1) {
        try testing.expect(isDecimal(cp));
        try testing.expect(isAsciiDigit(cp));
        try testing.expect(isAsciiNumber(cp));
    }

    try testing.expect(!isDecimal('\u{0003}'));
    try testing.expect(!isDecimal('A'));
}

test "number isHexDigit" {
    var cp: u21 = '0';
    while (cp <= '9') : (cp += 1) {
        try testing.expect(isHexDigit(cp));
    }

    try testing.expect(!isHexDigit('\u{0003}'));
    try testing.expect(!isHexDigit('Z'));
}

test "number isNumber" {
    var cp: u21 = '0';
    while (cp <= '9') : (cp += 1) {
        try testing.expect(isNumber(cp));
    }

    try testing.expect(!isNumber('\u{0003}'));
    try testing.expect(!isNumber('A'));
}
