// Autogenerated from http://www.unicode.org/Public/UCD/latest/ucd/UCD.zip by running ucd_gen.sh.
// Placeholders:
//    0. Struct name
//    1. Lowest code point
//    2. Highest code point
//! Unicode WhiteSpace code points.

lo: u21 = 9,
hi: u21 = 12288,

const WhiteSpace = @This();

pub fn isWhiteSpace(self: WhiteSpace, cp: u21) bool {
    if (cp < self.lo or cp > self.hi) return false;
    if (cp >= 9 and cp <= 13) return true;
    if (cp == 32) return true;
    if (cp == 133) return true;
    if (cp == 160) return true;
    if (cp == 5760) return true;
    if (cp >= 8192 and cp <= 8202) return true;
    if (cp == 8232) return true;
    if (cp == 8233) return true;
    if (cp == 8239) return true;
    if (cp == 8287) return true;
    if (cp == 12288) return true;
    return false;
}