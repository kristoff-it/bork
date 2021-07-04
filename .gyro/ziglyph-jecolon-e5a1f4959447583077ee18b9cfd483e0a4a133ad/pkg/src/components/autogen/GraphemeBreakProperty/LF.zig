// Autogenerated from http://www.unicode.org/Public/UCD/latest/ucd/UCD.zip by running ucd_gen.sh.
// Placeholders:
//    0. Struct name
//    1. Lowest code point
//    2. Highest code point
//! Unicode LF code points.

lo: u21 = 10,
hi: u21 = 10,

const LF = @This();

pub fn isLF(self: LF, cp: u21) bool {
    if (cp < self.lo or cp > self.hi) return false;
    if (cp == 10) return true;
    return false;
}