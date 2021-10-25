//! `letter` provides functions for hte Letter (L) Unicode category.
//!
const std = @import("std");
const testing = std.testing;

const case_fold_map = @import("../ziglyph.zig").case_fold_map;
const props = @import("../ziglyph.zig").derived_core_properties;
const cats = @import("../ziglyph.zig").derived_general_category;
const lower_map = @import("../ziglyph.zig").lower_map;
const title_map = @import("../ziglyph.zig").title_map;
const upper_map = @import("../ziglyph.zig").upper_map;

/// `isCased` detects letters that can be either upper, lower, or title cased.
pub fn isCased(cp: u21) bool {
    // ASCII optimization.
    if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z')) return true;
    return props.isCased(cp);
}

/// `isLetter` covers all letters in Unicode, not just ASCII.
pub fn isLetter(cp: u21) bool {
    // ASCII optimization.
    if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z')) return true;
    return cats.isLowercaseLetter(cp) or cats.isModifierLetter(cp) or cats.isOtherLetter(cp) or
        cats.isTitlecaseLetter(cp) or cats.isUppercaseLetter(cp);
}

/// `isAscii` detects ASCII only letters.
pub fn isAsciiLetter(cp: u21) bool {
    return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z');
}

/// `isLower` detects code points that are lowercase.
pub fn isLower(cp: u21) bool {
    // ASCII optimization.
    if (cp >= 'a' and cp <= 'z') return true;
    return props.isLowercase(cp);
}

/// `isAsciiLower` detects ASCII only lowercase letters.
pub fn isAsciiLower(cp: u21) bool {
    return cp >= 'a' and cp <= 'z';
}

/// `isTitle` detects code points in titlecase.
pub fn isTitle(cp: u21) bool {
    return cats.isTitlecaseLetter(cp);
}

/// `isUpper` detects code points in uppercase.
pub fn isUpper(cp: u21) bool {
    // ASCII optimization.
    if (cp >= 'A' and cp <= 'Z') return true;
    return props.isUppercase(cp);
}

/// `isAsciiUpper` detects ASCII only uppercase letters.
pub fn isAsciiUpper(cp: u21) bool {
    return cp >= 'A' and cp <= 'Z';
}

/// `toLower` returns the lowercase mapping for the given code point, or itself if none found.
pub fn toLower(cp: u21) u21 {
    // ASCII optimization.
    if (cp >= 'A' and cp <= 'Z') return cp ^ 32;
    // Only cased letters.
    if (!props.isChangesWhenCasemapped(cp)) return cp;
    return lower_map.toLower(cp);
}

/// `toAsciiLower` converts an ASCII letter to lowercase.
pub fn toAsciiLower(cp: u21) u21 {
    return if (cp >= 'A' and cp <= 'Z') cp ^ 32 else cp;
}

/// `toTitle` returns the titlecase mapping for the given code point, or itself if none found.
pub fn toTitle(cp: u21) u21 {
    // Only cased letters.
    if (!props.isChangesWhenCasemapped(cp)) return cp;
    return title_map.toTitle(cp);
}

/// `toUpper` returns the uppercase mapping for the given code point, or itself if none found.
pub fn toUpper(cp: u21) u21 {
    // ASCII optimization.
    if (cp >= 'a' and cp <= 'z') return cp ^ 32;
    // Only cased letters.
    if (!props.isChangesWhenCasemapped(cp)) return cp;
    return upper_map.toUpper(cp);
}

/// `toAsciiUpper` converts an ASCII letter to uppercase.
pub fn toAsciiUpper(cp: u21) u21 {
    return if (cp >= 'a' and cp <= 'z') cp ^ 32 else cp;
}

/// `toCaseFold` will convert a code point into its case folded equivalent. Note that this can result
/// in a mapping to more than one code point, known as the full case fold. The returned array has 3
/// elements and the code points span until the first element equal to 0 or the end, whichever is first.
pub fn toCaseFold(cp: u21) [3]u21 {
    return case_fold_map.toCaseFold(cp);
}

test "letter" {
    const z = 'z';
    try testing.expect(isLetter(z));
    try testing.expect(!isUpper(z));
    const uz = toUpper(z);
    try testing.expect(isUpper(uz));
    try testing.expectEqual(uz, 'Z');
}

test "letter isCased" {
    try testing.expect(isCased('a'));
    try testing.expect(isCased('A'));
    try testing.expect(!isCased('1'));
}

test "letter isLower" {
    try testing.expect(isLower('a'));
    try testing.expect(isAsciiLower('a'));
    try testing.expect(isLower('é'));
    try testing.expect(isLower('i'));
    try testing.expect(!isLower('A'));
    try testing.expect(!isLower('É'));
    try testing.expect(!isLower('İ'));
}

const expectEqualSlices = std.testing.expectEqualSlices;

test "letter toCaseFold" {
    var result = toCaseFold('A');
    try testing.expectEqualSlices(u21, &[_]u21{ 'a', 0, 0 }, &result);

    result = toCaseFold('a');
    try testing.expectEqualSlices(u21, &[_]u21{ 'a', 0, 0 }, &result);

    result = toCaseFold('1');
    try testing.expectEqualSlices(u21, &[_]u21{ '1', 0, 0 }, &result);

    result = toCaseFold('\u{00DF}');
    try testing.expectEqualSlices(u21, &[_]u21{ 0x0073, 0x0073, 0 }, &result);

    result = toCaseFold('\u{0390}');
    try testing.expectEqualSlices(u21, &[_]u21{ 0x03B9, 0x0308, 0x0301 }, &result);
}

test "letter toLower" {
    try testing.expectEqual(toLower('a'), 'a');
    try testing.expectEqual(toLower('A'), 'a');
    try testing.expectEqual(toLower('İ'), 'i');
    try testing.expectEqual(toLower('É'), 'é');
    try testing.expectEqual(toLower(0x80), 0x80);
    try testing.expectEqual(toLower(0x80), 0x80);
    try testing.expectEqual(toLower('Å'), 'å');
    try testing.expectEqual(toLower('å'), 'å');
    try testing.expectEqual(toLower('\u{212A}'), 'k');
    try testing.expectEqual(toLower('1'), '1');
}

test "letter isUpper" {
    try testing.expect(!isUpper('a'));
    try testing.expect(!isAsciiUpper('a'));
    try testing.expect(!isUpper('é'));
    try testing.expect(!isUpper('i'));
    try testing.expect(isUpper('A'));
    try testing.expect(isUpper('É'));
    try testing.expect(isUpper('İ'));
}

test "letter toUpper" {
    try testing.expectEqual(toUpper('a'), 'A');
    try testing.expectEqual(toUpper('A'), 'A');
    try testing.expectEqual(toUpper('i'), 'I');
    try testing.expectEqual(toUpper('é'), 'É');
    try testing.expectEqual(toUpper(0x80), 0x80);
    try testing.expectEqual(toUpper('Å'), 'Å');
    try testing.expectEqual(toUpper('å'), 'Å');
    try testing.expectEqual(toUpper('1'), '1');
}

test "letter isTitle" {
    try testing.expect(!isTitle('a'));
    try testing.expect(!isTitle('é'));
    try testing.expect(!isTitle('i'));
    try testing.expect(isTitle('\u{1FBC}'));
    try testing.expect(isTitle('\u{1FCC}'));
    try testing.expect(isTitle('ǈ'));
}

test "letter toTitle" {
    try testing.expectEqual(toTitle('a'), 'A');
    try testing.expectEqual(toTitle('A'), 'A');
    try testing.expectEqual(toTitle('i'), 'I');
    try testing.expectEqual(toTitle('é'), 'É');
    try testing.expectEqual(toTitle('1'), '1');
}

test "letter isLetter" {
    var cp: u21 = 'a';
    while (cp <= 'z') : (cp += 1) {
        try testing.expect(isLetter(cp));
    }

    cp = 'A';
    while (cp <= 'Z') : (cp += 1) {
        try testing.expect(isLetter(cp));
    }

    try testing.expect(isLetter('É'));
    try testing.expect(isLetter('\u{2CEB3}'));
    try testing.expect(!isLetter('\u{0003}'));
}
