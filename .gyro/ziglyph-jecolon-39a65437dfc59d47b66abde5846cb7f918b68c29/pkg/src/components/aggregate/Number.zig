const std = @import("std");

pub const Cats = @import("../../components.zig").DerivedGeneralCategory;
pub const Numeric = @import("../../components.zig").DerivedNumericType;
pub const Props = @import("../../components.zig").PropList;

// isDecimal detects all Unicode digits.
pub fn isDecimal(cp: u21) bool {
    // ASCII optimization.
    if (cp < 128 and (cp >= '0' and cp <= '9')) return true;
    return Numeric.isDecimal(cp);
}

// isDigit detects all Unicode digits, which don't include the ASCII digits..
pub fn isDigit(cp: u21) bool {
    // ASCII optimization.
    if (cp < 128 and (cp >= '0' and cp <= '9')) return true;
    return Numeric.isDigit(cp) or isDecimal(cp);
}

/// isAsciiAlphabetic detects ASCII only letters.
pub fn isAsciiDigit(cp: u21) bool {
    return cp < 128 and (cp >= '0' and cp <= '9');
}

// isHex detects the 16 ASCII characters 0-9 A-F, and a-f.
pub fn isHexDigit(cp: u21) bool {
    // ASCII optimization.
    if (cp < 128 and ((cp >= 'a' and cp <= 'f') or (cp >= 'A' and cp <= 'F') or (cp >= '0' and cp <= '9'))) return true;
    return Props.isHexDigit(cp);
}

/// isAsciiHexDigit detects ASCII only hexadecimal digits.
pub fn isAsciiHexDigit(cp: u21) bool {
    return cp < 128 and ((cp >= 'a' and cp <= 'f') or (cp >= 'A' and cp <= 'F') or (cp >= '0' and cp <= '9'));
}

/// isNumber covers all Unicode numbers, not just ASII.
pub fn isNumber(cp: u21) bool {
    // ASCII optimization.
    if (cp < 128 and (cp >= '0' and cp <= '9')) return true;
    return Numeric.isDecimal(cp) or Cats.isLetterNumber(cp) or Cats.isOtherNumber(cp);
}

/// isAsciiNumber detects ASCII only numbers.
pub fn isAsciiNumber(cp: u21) bool {
    return cp < 128 and (cp >= '0' and cp <= '9');
}

const expect = std.testing.expect;

test "Component isDecimal" {
    var cp: u21 = '0';
    while (cp <= '9') : (cp += 1) {
        try expect(isDecimal(cp));
    }

    try expect(!isDecimal('\u{0003}'));
    try expect(!isDecimal('A'));
}

test "Component isHexDigit" {
    var cp: u21 = '0';
    while (cp <= '9') : (cp += 1) {
        try expect(isHexDigit(cp));
    }

    try expect(!isHexDigit('\u{0003}'));
    try expect(!isHexDigit('Z'));
}

test "Component isNumber" {
    var cp: u21 = '0';
    while (cp <= '9') : (cp += 1) {
        try expect(isNumber(cp));
    }

    try expect(!isNumber('\u{0003}'));
    try expect(!isNumber('A'));
}
