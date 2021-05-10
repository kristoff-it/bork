const std = @import("std");

pub const CaseFoldMap = @import("../../components.zig").CaseFoldMap;
pub const Cased = @import("../../components.zig").Cased;
pub const Lower = @import("../../components.zig").Lower;
pub const LowerMap = @import("../../components.zig").LowerMap;
pub const ModifierLetter = @import("../../components.zig").ModifierLetter;
pub const OtherLetter = @import("../../components.zig").OtherLetter;
pub const Title = @import("../../components.zig").Title;
pub const TitleMap = @import("../../components.zig").TitleMap;
pub const Upper = @import("../../components.zig").Upper;
pub const UpperMap = @import("../../components.zig").UpperMap;

const Self = @This();

fold_map: CaseFoldMap,
cased: Cased,
lower: Lower,
lower_map: LowerMap,
modifier_letter: ModifierLetter,
other_letter: OtherLetter,
title: Title,
title_map: TitleMap,
upper: Upper,
upper_map: UpperMap,

pub fn new() Self {
    return Self{
        .fold_map = CaseFoldMap{},
        .cased = Cased{},
        .lower = Lower{},
        .lower_map = LowerMap{},
        .modifier_letter = ModifierLetter{},
        .other_letter = OtherLetter{},
        .title = Title{},
        .title_map = TitleMap{},
        .upper = Upper{},
        .upper_map = UpperMap{},
    };
}

/// isCased detects cased letters.
pub fn isCased(self: Self, cp: u21) bool {
    // ASCII optimization.
    if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z')) return true;
    return self.cased.isCased(cp);
}

/// isLetter covers all letters in Unicode, not just ASCII.
pub fn isLetter(self: Self, cp: u21) bool {
    // ASCII optimization.
    if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z')) return true;
    return self.lower.isLowercaseLetter(cp) or self.modifier_letter.isModifierLetter(cp) or
        self.other_letter.isOtherLetter(cp) or self.title.isTitlecaseLetter(cp) or
        self.upper.isUppercaseLetter(cp);
}

/// isAscii detects ASCII only letters.
pub fn isAsciiLetter(cp: u21) bool {
    return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z');
}

/// isLower detects code points that are lowercase.
pub fn isLower(self: Self, cp: u21) bool {
    // ASCII optimization.
    if (cp >= 'a' and cp <= 'z') return true;
    return self.lower.isLowercaseLetter(cp) or !self.isCased(cp);
}

/// isAsciiLower detects ASCII only lowercase letters.
pub fn isAsciiLower(cp: u21) bool {
    return cp >= 'a' and cp <= 'z';
}

/// isTitle detects code points in titlecase.
pub fn isTitle(self: Self, cp: u21) bool {
    return self.title.isTitlecaseLetter(cp) or !self.isCased(cp);
}

/// isUpper detects code points in uppercase.
pub fn isUpper(self: Self, cp: u21) bool {
    // ASCII optimization.
    if (cp >= 'A' and cp <= 'Z') return true;
    return self.upper.isUppercaseLetter(cp) or !self.isCased(cp);
}

/// isAsciiUpper detects ASCII only uppercase letters.
pub fn isAsciiUpper(cp: u21) bool {
    return cp >= 'A' and cp <= 'Z';
}

/// toLower returns the lowercase code point for the given code point. It returns the same 
/// code point given if no mapping exists.
pub fn toLower(self: Self, cp: u21) u21 {
    // ASCII optimization.
    if (cp >= 'A' and cp <= 'Z') return cp ^ 32;
    // Only cased letters.
    if (!self.isCased(cp)) return cp;
    return self.lower_map.toLower(cp);
}

/// toAsciiLower converts an ASCII letter to lowercase.
pub fn toAsciiLower(self: Self, cp: u21) u21 {
    return if (cp >= 'A' and cp <= 'Z') cp ^ 32 else cp;
}

/// toTitle returns the titlecase code point for the given code point. It returns the same 
/// code point given if no mapping exists.
pub fn toTitle(self: Self, cp: u21) u21 {
    // Only cased letters.
    if (!self.isCased(cp)) return cp;
    return self.title_map.toTitle(cp);
}

/// toUpper returns the uppercase code point for the given code point. It returns the same 
/// code point given if no mapping exists.
pub fn toUpper(self: Self, cp: u21) u21 {
    // ASCII optimization.
    if (cp >= 'a' and cp <= 'z') return cp ^ 32;
    // Only cased letters.
    if (!self.isCased(cp)) return cp;
    return self.upper_map.toUpper(cp);
}

/// toAsciiUpper converts an ASCII letter to uppercase.
pub fn toAsciiUpper(self: Self, cp: u21) u21 {
    return if (cp >= 'a' and cp <= 'z') cp ^ 32 else cp;
}

/// toCaseFold will convert a code point into its case folded equivalent. Note that this can result
/// in a mapping to more than one code point, known as the full case fold. The returned array has 3
/// elements and the code points span until the first element equal to 0 or the end, whichever is first.
pub fn toCaseFold(self: Self, cp: u21) [3]u21 {
    return self.fold_map.toCaseFold(cp);
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "Component struct" {
    var letter = new();

    const z = 'z';
    expect(letter.isLetter(z));
    expect(!letter.isUpper(z));
    const uz = letter.toUpper(z);
    expect(letter.isUpper(uz));
    expectEqual(uz, 'Z');
}

test "Component isCased" {
    var letter = new();

    expect(letter.isCased('a'));
    expect(letter.isCased('A'));
    expect(!letter.isCased('1'));
}

test "Component isLower" {
    var letter = new();

    expect(letter.isLower('a'));
    expect(letter.isLower('é'));
    expect(letter.isLower('i'));
    expect(!letter.isLower('A'));
    expect(!letter.isLower('É'));
    expect(!letter.isLower('İ'));
    // Numbers are lower, upper, and title all at once.
    expect(letter.isLower('1'));
}

const expectEqualSlices = std.testing.expectEqualSlices;

test "Component toCaseFold" {
    var letter = new();

    var result = letter.toCaseFold('A');
    expectEqualSlices(u21, &[_]u21{ 'a', 0, 0 }, &result);

    result = letter.toCaseFold('a');
    expectEqualSlices(u21, &[_]u21{ 'a', 0, 0 }, &result);

    result = letter.toCaseFold('1');
    expectEqualSlices(u21, &[_]u21{ '1', 0, 0 }, &result);

    result = letter.toCaseFold('\u{00DF}');
    expectEqualSlices(u21, &[_]u21{ 0x0073, 0x0073, 0 }, &result);

    result = letter.toCaseFold('\u{0390}');
    expectEqualSlices(u21, &[_]u21{ 0x03B9, 0x0308, 0x0301 }, &result);
}

test "Component toLower" {
    var letter = new();

    expectEqual(letter.toLower('a'), 'a');
    expectEqual(letter.toLower('A'), 'a');
    expectEqual(letter.toLower('İ'), 'i');
    expectEqual(letter.toLower('É'), 'é');
    expectEqual(letter.toLower(0x80), 0x80);
    expectEqual(letter.toLower(0x80), 0x80);
    expectEqual(letter.toLower('Å'), 'å');
    expectEqual(letter.toLower('å'), 'å');
    expectEqual(letter.toLower('\u{212A}'), 'k');
    expectEqual(letter.toLower('1'), '1');
}

test "Component isUpper" {
    var letter = new();

    expect(!letter.isUpper('a'));
    expect(!letter.isUpper('é'));
    expect(!letter.isUpper('i'));
    expect(letter.isUpper('A'));
    expect(letter.isUpper('É'));
    expect(letter.isUpper('İ'));
    // Numbers are lower, upper, and title all at once.
    expect(letter.isUpper('1'));
}

test "Component toUpper" {
    var letter = new();

    expectEqual(letter.toUpper('a'), 'A');
    expectEqual(letter.toUpper('A'), 'A');
    expectEqual(letter.toUpper('i'), 'I');
    expectEqual(letter.toUpper('é'), 'É');
    expectEqual(letter.toUpper(0x80), 0x80);
    expectEqual(letter.toUpper('Å'), 'Å');
    expectEqual(letter.toUpper('å'), 'Å');
    expectEqual(letter.toUpper('1'), '1');
}

test "Component isTitle" {
    var letter = new();

    expect(!letter.isTitle('a'));
    expect(!letter.isTitle('é'));
    expect(!letter.isTitle('i'));
    expect(letter.isTitle('\u{1FBC}'));
    expect(letter.isTitle('\u{1FCC}'));
    expect(letter.isTitle('ǈ'));
    // Numbers are lower, upper, and title all at once.
    expect(letter.isTitle('1'));
}

test "Component toTitle" {
    var letter = new();

    expectEqual(letter.toTitle('a'), 'A');
    expectEqual(letter.toTitle('A'), 'A');
    expectEqual(letter.toTitle('i'), 'I');
    expectEqual(letter.toTitle('é'), 'É');
    expectEqual(letter.toTitle('1'), '1');
}

test "Component isLetter" {
    var letter = new();

    var cp: u21 = 'a';
    while (cp <= 'z') : (cp += 1) {
        expect(letter.isLetter(cp));
    }

    cp = 'A';
    while (cp <= 'Z') : (cp += 1) {
        expect(letter.isLetter(cp));
    }

    expect(letter.isLetter('É'));
    expect(letter.isLetter('\u{2CEB3}'));
    expect(!letter.isLetter('\u{0003}'));
}
