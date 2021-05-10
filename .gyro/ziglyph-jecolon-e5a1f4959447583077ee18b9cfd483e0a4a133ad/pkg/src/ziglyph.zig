//! Ziglyph provides Unicode processing in Zig.

const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const ascii = @import("ascii.zig");

/// Library Components
pub const Alphabetic = @import("components.zig").Alphabetic;
pub const CccMap = @import("components.zig").CccMap;
pub const Control = @import("components.zig").Control;
pub const DecomposeMap = @import("components.zig").DecomposeMap;
pub const GraphemeIterator = @import("components.zig").GraphemeIterator;
pub const Extend = @import("components.zig").Extend;
pub const ExtPic = @import("components.zig").ExtPic;
pub const Format = @import("components.zig").Format;
pub const HangulMap = @import("components.zig").HangulMap;
pub const Prepend = @import("components.zig").Prepend;
pub const Regional = @import("components.zig").Regional;
pub const Width = @import("components.zig").Width;
// Letter
pub const CaseFoldMap = @import("components.zig").CaseFoldMap;
pub const CaseFold = CaseFoldMap.CaseFold;
pub const Cased = @import("components.zig").Cased;
pub const Lower = @import("components.zig").Lower;
pub const LowerMap = @import("components.zig").LowerMap;
pub const ModifierLetter = @import("components.zig").ModifierLetter;
pub const OtherLetter = @import("components.zig").OtherLetter;
pub const Title = @import("components.zig").Title;
pub const TitleMap = @import("components.zig").TitleMap;
pub const Upper = @import("components.zig").Upper;
pub const UpperMap = @import("components.zig").UpperMap;
// Aggregates
pub const Letter = @import("components.zig").Letter;
pub const Mark = @import("components.zig").Mark;
pub const Number = @import("components.zig").Number;
pub const Punct = @import("components.zig").Punct;
pub const Symbol = @import("components.zig").Symbol;
// Mark
pub const Enclosing = @import("components.zig").Enclosing;
pub const Nonspacing = @import("components.zig").Nonspacing;
pub const Spacing = @import("components.zig").Spacing;
// Number
pub const Decimal = @import("components.zig").Decimal;
pub const Digit = @import("components.zig").Digit;
pub const Hex = @import("components.zig").Hex;
pub const LetterNumber = @import("components.zig").LetterNumber;
pub const OtherNumber = @import("components.zig").OtherNumber;
// Punct
pub const Close = @import("components.zig").Close;
pub const Connector = @import("components.zig").Connector;
pub const Dash = @import("components.zig").Dash;
pub const Final = @import("components.zig").Final;
pub const Initial = @import("components.zig").Initial;
pub const Open = @import("components.zig").Open;
pub const OtherPunct = @import("components.zig").OtherPunct;
// Space
pub const WhiteSpace = @import("components.zig").WhiteSpace;
// Symbol
pub const Currency = @import("components.zig").Currency;
pub const Math = @import("components.zig").Math;
pub const ModifierSymbol = @import("components.zig").ModifierSymbol;
pub const OtherSymbol = @import("components.zig").OtherSymbol;
// Width
pub const Ambiguous = @import("components.zig").Ambiguous;
pub const Fullwidth = @import("components.zig").Fullwidth;
pub const Wide = @import("components.zig").Wide;
// UTF-8 string struct
pub const Zigstr = @import("components.zig").Zigstr;

/// Ziglyph consolidates frequently-used Unicode utility functions in one place.
pub const Ziglyph = struct {
    alphabetic: Alphabetic,
    control: Control,
    letter: Letter,
    mark: Mark,
    number: Number,
    punct: Punct,
    space: WhiteSpace,
    symbol: Symbol,

    const Self = @This();

    pub fn new() Self {
        return Self{
            .alphabetic = Alphabetic{},
            .control = Control{},
            .letter = Letter.new(),
            .mark = Mark.new(),
            .number = Number.new(),
            .punct = Punct.new(),
            .space = WhiteSpace{},
            .symbol = Symbol.new(),
        };
    }

    pub fn isAlphabetic(self: Self, cp: u21) bool {
        return self.alphabetic.isAlphabetic(cp);
    }

    pub fn isAsciiAlphabetic(cp: u21) bool {
        return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z');
    }

    pub fn isAlphaNum(self: Self, cp: u21) bool {
        return self.isAlphabetic(cp) or self.isNumber(cp);
    }

    pub fn isAsciiAlphaNum(cp: u21) bool {
        return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z') or (cp >= '0' and cp <= '9');
    }

    /// isCased detects cased code points, usually letters.
    pub fn isCased(self: Self, cp: u21) bool {
        return self.letter.isCased(cp);
    }

    /// isDecimal detects all Unicode decimal numbers.
    pub fn isDecimal(self: Self, cp: u21) bool {
        return self.number.isDecimal(cp);
    }

    /// isDigit detects all Unicode digits, which curiosly don't include the ASCII digits.
    pub fn isDigit(self: Self, cp: u21) bool {
        return self.number.isDigit(cp);
    }

    pub fn isAsciiDigit(cp: u21) bool {
        return cp >= '0' and cp <= '9';
    }

    /// isGraphic detects any code point that can be represented graphically, including spaces.
    pub fn isGraphic(self: Self, cp: u21) bool {
        return self.isPrint(cp) or self.isWhiteSpace(cp);
    }

    pub fn isAsciiGraphic(cp: u21) bool {
        return if (cp < 128) ascii.isGraph(@intCast(u8, cp)) else false;
    }

    // isHex detects hexadecimal code points.
    pub fn isHexDigit(self: Self, cp: u21) bool {
        return self.number.isHexDigit(cp);
    }

    pub fn isAsciiHexDigit(cp: u21) bool {
        return (cp >= 'a' and cp <= 'f') or (cp >= 'A' and cp <= 'F') or (cp >= '0' and cp <= '9');
    }

    /// isPrint detects any code point that can be printed, excluding spaces.
    pub fn isPrint(self: Self, cp: u21) bool {
        return self.isAlphaNum(cp) or self.isMark(cp) or self.isPunct(cp) or
            self.isSymbol(cp) or self.isWhiteSpace(cp);
    }

    pub fn isAsciiPrint(cp: u21) bool {
        return if (cp < 128) ascii.isPrint(@intCast(u8, cp)) else false;
    }

    pub fn isControl(self: Self, cp: u21) bool {
        return self.control.isControl(cp);
    }

    pub fn isAsciiControl(cp: u21) bool {
        return if (cp < 128) ascii.isCntrl(@intCast(u8, cp)) else false;
    }

    pub fn isLetter(self: Self, cp: u21) bool {
        return self.letter.isLetter(cp);
    }

    pub fn isAsciiLetter(cp: u21) bool {
        return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z');
    }

    /// isLower detects code points that are lowercase.
    pub fn isLower(self: Self, cp: u21) bool {
        return self.letter.isLower(cp);
    }

    pub fn isAsciiLower(cp: u21) bool {
        return cp >= 'a' and cp <= 'z';
    }

    /// isMark detects special code points that serve as marks in different alphabets.
    pub fn isMark(self: Self, cp: u21) bool {
        return self.mark.isMark(cp);
    }

    pub fn isNumber(self: Self, cp: u21) bool {
        return self.number.isNumber(cp);
    }

    pub fn isAsciiNumber(cp: u21) bool {
        return cp >= '0' and cp <= '9';
    }

    /// isPunct detects punctuation characters. Note some punctuation may be considered as symbols by Unicode.
    pub fn isPunct(self: Self, cp: u21) bool {
        return self.punct.isPunct(cp);
    }

    pub fn isAsciiPunct(cp: u21) bool {
        return if (cp < 128) ascii.isPunct(@intCast(u8, cp)) else false;
    }

    /// isWhiteSpace detects code points that have the Unicode *WhiteSpace* property.
    pub fn isWhiteSpace(self: Self, cp: u21) bool {
        return self.space.isWhiteSpace(cp);
    }

    pub fn isAsciiWhiteSpace(cp: u21) bool {
        return if (cp < 128) ascii.isSpace(@intCast(u8, cp)) else false;
    }

    // isSymbol detects symbols which may include code points commonly considered punctuation.
    pub fn isSymbol(self: Self, cp: u21) bool {
        return self.symbol.isSymbol(cp);
    }

    pub fn isAsciiSymbol(cp: u21) bool {
        return if (cp < 128) ascii.isSymbol(@intCast(u8, cp)) else false;
    }

    /// isTitle detects code points in titlecase.
    pub fn isTitle(self: Self, cp: u21) bool {
        return self.letter.isTitle(cp);
    }

    /// isUpper detects code points in uppercase.
    pub fn isUpper(self: Self, cp: u21) bool {
        return self.letter.isUpper(cp);
    }

    pub fn isAsciiUpper(cp: u21) bool {
        return cp >= 'A' and cp <= 'Z';
    }

    /// toLower returns the lowercase code point for the given code point. It returns the same 
    /// code point given if no mapping exists.
    pub fn toLower(self: Self, cp: u21) u21 {
        return self.letter.toLower(cp);
    }

    pub fn toAsciiLower(cp: u21) u21 {
        return if (cp >= 'A' and cp <= 'Z') cp ^ 32 else cp;
    }

    /// toTitle returns the titlecase code point for the given code point. It returns the same 
    /// code point given if no mapping exists.
    pub fn toTitle(self: Self, cp: u21) u21 {
        return self.letter.toTitle(cp);
    }

    /// toUpper returns the uppercase code point for the given code point. It returns the same 
    /// code point given if no mapping exists.
    pub fn toUpper(self: Self, cp: u21) u21 {
        return self.letter.toUpper(cp);
    }

    pub fn toAsciiUpper(cp: u21) u21 {
        return if (cp >= 'a' and cp <= 'z') cp ^ 32 else cp;
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "Ziglyph ASCII methods" {
    const z = 'F';
    expect(Ziglyph.isAsciiAlphabetic(z));
    expect(Ziglyph.isAsciiAlphaNum(z));
    expect(Ziglyph.isAsciiHexDigit(z));
    expect(Ziglyph.isAsciiGraphic(z));
    expect(Ziglyph.isAsciiPrint(z));
    expect(Ziglyph.isAsciiUpper(z));
    expect(!Ziglyph.isAsciiControl(z));
    expect(!Ziglyph.isAsciiDigit(z));
    expect(!Ziglyph.isAsciiNumber(z));
    expect(!Ziglyph.isAsciiLower(z));
    expectEqual(Ziglyph.toAsciiLower(z), 'f');
    expectEqual(Ziglyph.toAsciiUpper('a'), 'A');
    expect(Ziglyph.isAsciiLower(Ziglyph.toAsciiLower(z)));
}

test "Ziglyph struct" {
    var ziglyph = Ziglyph.new();

    const z = 'z';
    expect(ziglyph.isAlphaNum(z));
    expect(!ziglyph.isControl(z));
    expect(!ziglyph.isDecimal(z));
    expect(!ziglyph.isDigit(z));
    expect(!ziglyph.isHexDigit(z));
    expect(ziglyph.isGraphic(z));
    expect(ziglyph.isLetter(z));
    expect(ziglyph.isLower(z));
    expect(!ziglyph.isMark(z));
    expect(!ziglyph.isNumber(z));
    expect(ziglyph.isPrint(z));
    expect(!ziglyph.isPunct(z));
    expect(!ziglyph.isWhiteSpace(z));
    expect(!ziglyph.isSymbol(z));
    expect(!ziglyph.isTitle(z));
    expect(!ziglyph.isUpper(z));
    const uz = ziglyph.toUpper(z);
    expect(ziglyph.isUpper(uz));
    expectEqual(uz, 'Z');
    const lz = ziglyph.toLower(uz);
    expect(ziglyph.isLower(lz));
    expectEqual(lz, 'z');
    const tz = ziglyph.toTitle(lz);
    expect(ziglyph.isUpper(tz));
    expectEqual(tz, 'Z');
}

test "Ziglyph isGraphic" {
    var ziglyph = Ziglyph.new();

    expect(ziglyph.isGraphic('A'));
    expect(ziglyph.isGraphic('\u{20E4}'));
    expect(ziglyph.isGraphic('1'));
    expect(ziglyph.isGraphic('?'));
    expect(ziglyph.isGraphic(' '));
    expect(ziglyph.isGraphic('='));
    expect(!ziglyph.isGraphic('\u{0003}'));
}

test "Ziglyph isHexDigit" {
    var ziglyph = Ziglyph.new();

    var cp: u21 = '0';
    while (cp <= '9') : (cp += 1) {
        expect(ziglyph.isHexDigit(cp));
    }

    cp = 'A';
    while (cp <= 'F') : (cp += 1) {
        expect(ziglyph.isHexDigit(cp));
    }

    cp = 'a';
    while (cp <= 'f') : (cp += 1) {
        expect(ziglyph.isHexDigit(cp));
    }

    expect(!ziglyph.isHexDigit('\u{0003}'));
    expect(!ziglyph.isHexDigit('Z'));
}

test "Ziglyph isPrint" {
    var ziglyph = Ziglyph.new();

    expect(ziglyph.isPrint('A'));
    expect(ziglyph.isPrint('\u{20E4}'));
    expect(ziglyph.isPrint('1'));
    expect(ziglyph.isPrint('?'));
    expect(ziglyph.isPrint('='));
    expect(ziglyph.isPrint(' '));
    expect(ziglyph.isPrint('\t'));
    expect(!ziglyph.isPrint('\u{0003}'));
}

test "Ziglyph isAlphaNum" {
    var ziglyph = Ziglyph.new();

    var cp: u21 = '0';
    while (cp <= '9') : (cp += 1) {
        expect(ziglyph.isAlphaNum(cp));
    }

    cp = 'a';
    while (cp <= 'z') : (cp += 1) {
        expect(ziglyph.isAlphaNum(cp));
    }

    cp = 'A';
    while (cp <= 'Z') : (cp += 1) {
        expect(ziglyph.isAlphaNum(cp));
    }

    expect(!ziglyph.isAlphaNum('='));
}

test "Ziglyph isControl" {
    var ziglyph = Ziglyph.new();

    expect(ziglyph.isControl('\n'));
    expect(ziglyph.isControl('\r'));
    expect(ziglyph.isControl('\t'));
    expect(ziglyph.isControl('\u{0003}'));
    expect(ziglyph.isControl('\u{0012}'));
    expect(!ziglyph.isControl('A'));
}
