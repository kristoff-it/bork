// Autogenerated from http://www.unicode.org/Public/UCD/latest/ucd/UCD.zip by running ucd_gen.sh.
// Placeholders:
//    0. Struct name
//    1. Lowest code point
//    2. Highest code point
//! Unicode MathSymbol code points.

lo: u21 = 43,
hi: u21 = 126705,

const MathSymbol = @This();

pub fn isMathSymbol(self: MathSymbol, cp: u21) bool {
    if (cp < self.lo or cp > self.hi) return false;
    if (cp == 43) return true;
    if (cp >= 60 and cp <= 62) return true;
    if (cp == 124) return true;
    if (cp == 126) return true;
    if (cp == 172) return true;
    if (cp == 177) return true;
    if (cp == 215) return true;
    if (cp == 247) return true;
    if (cp == 1014) return true;
    if (cp >= 1542 and cp <= 1544) return true;
    if (cp == 8260) return true;
    if (cp == 8274) return true;
    if (cp >= 8314 and cp <= 8316) return true;
    if (cp >= 8330 and cp <= 8332) return true;
    if (cp == 8472) return true;
    if (cp >= 8512 and cp <= 8516) return true;
    if (cp == 8523) return true;
    if (cp >= 8592 and cp <= 8596) return true;
    if (cp >= 8602 and cp <= 8603) return true;
    if (cp == 8608) return true;
    if (cp == 8611) return true;
    if (cp == 8614) return true;
    if (cp == 8622) return true;
    if (cp >= 8654 and cp <= 8655) return true;
    if (cp == 8658) return true;
    if (cp == 8660) return true;
    if (cp >= 8692 and cp <= 8959) return true;
    if (cp >= 8992 and cp <= 8993) return true;
    if (cp == 9084) return true;
    if (cp >= 9115 and cp <= 9139) return true;
    if (cp >= 9180 and cp <= 9185) return true;
    if (cp == 9655) return true;
    if (cp == 9665) return true;
    if (cp >= 9720 and cp <= 9727) return true;
    if (cp == 9839) return true;
    if (cp >= 10176 and cp <= 10180) return true;
    if (cp >= 10183 and cp <= 10213) return true;
    if (cp >= 10224 and cp <= 10239) return true;
    if (cp >= 10496 and cp <= 10626) return true;
    if (cp >= 10649 and cp <= 10711) return true;
    if (cp >= 10716 and cp <= 10747) return true;
    if (cp >= 10750 and cp <= 11007) return true;
    if (cp >= 11056 and cp <= 11076) return true;
    if (cp >= 11079 and cp <= 11084) return true;
    if (cp == 64297) return true;
    if (cp == 65122) return true;
    if (cp >= 65124 and cp <= 65126) return true;
    if (cp == 65291) return true;
    if (cp >= 65308 and cp <= 65310) return true;
    if (cp == 65372) return true;
    if (cp == 65374) return true;
    if (cp == 65506) return true;
    if (cp >= 65513 and cp <= 65516) return true;
    if (cp == 120513) return true;
    if (cp == 120539) return true;
    if (cp == 120571) return true;
    if (cp == 120597) return true;
    if (cp == 120629) return true;
    if (cp == 120655) return true;
    if (cp == 120687) return true;
    if (cp == 120713) return true;
    if (cp == 120745) return true;
    if (cp == 120771) return true;
    if (cp >= 126704 and cp <= 126705) return true;
    return false;
}