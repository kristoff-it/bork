const std = @import("std");

pub const CaseFoldMap = @import("../../components.zig").CaseFoldMap;
pub const Props = @import("../../components.zig").DerivedCoreProperties;
pub const Cats = @import("../../components.zig").DerivedGeneralCategory;
pub const LowerMap = @import("../../components.zig").LowerMap;
pub const TitleMap = @import("../../components.zig").TitleMap;
pub const UpperMap = @import("../../components.zig").UpperMap;

const Self = @This();

/// isCased detects cased letters.
pub fn isCased(cp: u21) bool {
    // ASCII optimization.
    if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z')) return true;
    return Props.isCased(cp);
}

/// isLetter covers all letters in Unicode, not just ASCII.
pub fn isLetter(cp: u21) bool {
    // ASCII optimization.
    if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z')) return true;
    return Cats.isLowercaseLetter(cp) or Cats.isModifierLetter(cp) or Cats.isOtherLetter(cp) or
        Cats.isTitlecaseLetter(cp) or Cats.isUppercaseLetter(cp);
}

/// isAscii detects ASCII only letters.
pub fn isAsciiLetter(cp: u21) bool {
    return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z');
}

/// isLower detects code points that are lowercase.
pub fn isLower(cp: u21) bool {
    // ASCII optimization.
    if (cp >= 'a' and cp <= 'z') return true;
    return Cats.isLowercaseLetter(cp) or !isCased(cp);
}

/// isAsciiLower detects ASCII only lowercase letters.
pub fn isAsciiLower(cp: u21) bool {
    return cp >= 'a' and cp <= 'z';
}

/// isTitle detects code points in titlecase.
pub fn isTitle(cp: u21) bool {
    return Cats.isTitlecaseLetter(cp) or !isCased(cp);
}

/// isUpper detects code points in uppercase.
pub fn isUpper(cp: u21) bool {
    // ASCII optimization.
    if (cp >= 'A' and cp <= 'Z') return true;
    return Cats.isUppercaseLetter(cp) or !isCased(cp);
}

/// isAsciiUpper detects ASCII only uppercase letters.
pub fn isAsciiUpper(cp: u21) bool {
    return cp >= 'A' and cp <= 'Z';
}

/// toLower returns the lowercase code point for the given code point. It returns the same 
/// code point given if no mapping exists.
pub fn toLower(cp: u21) u21 {
    // ASCII optimization.
    if (cp >= 'A' and cp <= 'Z') return cp ^ 32;
    // Only cased letters.
    if (!isCased(cp)) return cp;
    return LowerMap.toLower(cp);
}

/// toAsciiLower converts an ASCII letter to lowercase.
pub fn toAsciiLower(_: Self, cp: u21) u21 {
    return if (cp >= 'A' and cp <= 'Z') cp ^ 32 else cp;
}

/// toTitle returns the titlecase code point for the given code point. It returns the same 
/// code point given if no mapping exists.
pub fn toTitle(cp: u21) u21 {
    // Only cased letters.
    if (!isCased(cp)) return cp;
    return TitleMap.toTitle(cp);
}

/// toUpper returns the uppercase code point for the given code point. It returns the same 
/// code point given if no mapping exists.
pub fn toUpper(cp: u21) u21 {
    // ASCII optimization.
    if (cp >= 'a' and cp <= 'z') return cp ^ 32;
    // Only cased letters.
    if (!isCased(cp)) return cp;
    return UpperMap.toUpper(cp);
}

/// toAsciiUpper converts an ASCII letter to uppercase.
pub fn toAsciiUpper(_: Self, cp: u21) u21 {
    return if (cp >= 'a' and cp <= 'z') cp ^ 32 else cp;
}

/// toCaseFold will convert a code point into its case folded equivalent. Note that this can result
/// in a mapping to more than one code point, known as the full case fold. The returned array has 3
/// elements and the code points span until the first element equal to 0 or the end, whichever is first.
pub fn toCaseFold(cp: u21) [3]u21 {
    return CaseFoldMap.toCaseFold(cp);
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "Component struct" {
    const z = 'z';
    try expect(isLetter(z));
    try expect(!isUpper(z));
    const uz = toUpper(z);
    try expect(isUpper(uz));
    try expectEqual(uz, 'Z');
}

test "Component isCased" {
    try expect(isCased('a'));
    try expect(isCased('A'));
    try expect(!isCased('1'));
}

test "Component isLower" {
    try expect(isLower('a'));
    try expect(isLower('é'));
    try expect(isLower('i'));
    try expect(!isLower('A'));
    try expect(!isLower('É'));
    try expect(!isLower('İ'));
    // Numbers are lower, upper, and title all at once.
    try expect(isLower('1'));
}

const expectEqualSlices = std.testing.expectEqualSlices;

test "Component toCaseFold" {
    var result = toCaseFold('A');
    try expectEqualSlices(u21, &[_]u21{ 'a', 0, 0 }, &result);

    result = toCaseFold('a');
    try expectEqualSlices(u21, &[_]u21{ 'a', 0, 0 }, &result);

    result = toCaseFold('1');
    try expectEqualSlices(u21, &[_]u21{ '1', 0, 0 }, &result);

    result = toCaseFold('\u{00DF}');
    try expectEqualSlices(u21, &[_]u21{ 0x0073, 0x0073, 0 }, &result);

    result = toCaseFold('\u{0390}');
    try expectEqualSlices(u21, &[_]u21{ 0x03B9, 0x0308, 0x0301 }, &result);
}

test "Component toLower" {
    try expectEqual(toLower('a'), 'a');
    try expectEqual(toLower('A'), 'a');
    try expectEqual(toLower('İ'), 'i');
    try expectEqual(toLower('É'), 'é');
    try expectEqual(toLower(0x80), 0x80);
    try expectEqual(toLower(0x80), 0x80);
    try expectEqual(toLower('Å'), 'å');
    try expectEqual(toLower('å'), 'å');
    try expectEqual(toLower('\u{212A}'), 'k');
    try expectEqual(toLower('1'), '1');
}

test "Component isUpper" {
    try expect(!isUpper('a'));
    try expect(!isUpper('é'));
    try expect(!isUpper('i'));
    try expect(isUpper('A'));
    try expect(isUpper('É'));
    try expect(isUpper('İ'));
    // Numbers are lower, upper, and title all at once.
    try expect(isUpper('1'));
}

test "Component toUpper" {
    try expectEqual(toUpper('a'), 'A');
    try expectEqual(toUpper('A'), 'A');
    try expectEqual(toUpper('i'), 'I');
    try expectEqual(toUpper('é'), 'É');
    try expectEqual(toUpper(0x80), 0x80);
    try expectEqual(toUpper('Å'), 'Å');
    try expectEqual(toUpper('å'), 'Å');
    try expectEqual(toUpper('1'), '1');
}

test "Component isTitle" {
    try expect(!isTitle('a'));
    try expect(!isTitle('é'));
    try expect(!isTitle('i'));
    try expect(isTitle('\u{1FBC}'));
    try expect(isTitle('\u{1FCC}'));
    try expect(isTitle('ǈ'));
    // Numbers are lower, upper, and title all at once.
    try expect(isTitle('1'));
}

test "Component toTitle" {
    try expectEqual(toTitle('a'), 'A');
    try expectEqual(toTitle('A'), 'A');
    try expectEqual(toTitle('i'), 'I');
    try expectEqual(toTitle('é'), 'É');
    try expectEqual(toTitle('1'), '1');
}

test "Component isLetter" {
    var cp: u21 = 'a';
    while (cp <= 'z') : (cp += 1) {
        try expect(isLetter(cp));
    }

    cp = 'A';
    while (cp <= 'Z') : (cp += 1) {
        try expect(isLetter(cp));
    }

    try expect(isLetter('É'));
    try expect(isLetter('\u{2CEB3}'));
    try expect(!isLetter('\u{0003}'));
}
