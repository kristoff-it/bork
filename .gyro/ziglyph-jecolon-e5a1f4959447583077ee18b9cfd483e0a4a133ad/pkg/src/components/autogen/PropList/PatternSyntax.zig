// Autogenerated from http://www.unicode.org/Public/UCD/latest/ucd/UCD.zip by running ucd_gen.sh.
// Placeholders:
//    0. Struct name
//    1. Lowest code point
//    2. Highest code point
//! Unicode PatternSyntax code points.

lo: u21 = 33,
hi: u21 = 65094,

const PatternSyntax = @This();

pub fn isPatternSyntax(self: PatternSyntax, cp: u21) bool {
    if (cp < self.lo or cp > self.hi) return false;
    if (cp >= 33 and cp <= 35) return true;
    if (cp == 36) return true;
    if (cp >= 37 and cp <= 39) return true;
    if (cp == 40) return true;
    if (cp == 41) return true;
    if (cp == 42) return true;
    if (cp == 43) return true;
    if (cp == 44) return true;
    if (cp == 45) return true;
    if (cp >= 46 and cp <= 47) return true;
    if (cp >= 58 and cp <= 59) return true;
    if (cp >= 60 and cp <= 62) return true;
    if (cp >= 63 and cp <= 64) return true;
    if (cp == 91) return true;
    if (cp == 92) return true;
    if (cp == 93) return true;
    if (cp == 94) return true;
    if (cp == 96) return true;
    if (cp == 123) return true;
    if (cp == 124) return true;
    if (cp == 125) return true;
    if (cp == 126) return true;
    if (cp == 161) return true;
    if (cp >= 162 and cp <= 165) return true;
    if (cp == 166) return true;
    if (cp == 167) return true;
    if (cp == 169) return true;
    if (cp == 171) return true;
    if (cp == 172) return true;
    if (cp == 174) return true;
    if (cp == 176) return true;
    if (cp == 177) return true;
    if (cp == 182) return true;
    if (cp == 187) return true;
    if (cp == 191) return true;
    if (cp == 215) return true;
    if (cp == 247) return true;
    if (cp >= 8208 and cp <= 8213) return true;
    if (cp >= 8214 and cp <= 8215) return true;
    if (cp == 8216) return true;
    if (cp == 8217) return true;
    if (cp == 8218) return true;
    if (cp >= 8219 and cp <= 8220) return true;
    if (cp == 8221) return true;
    if (cp == 8222) return true;
    if (cp == 8223) return true;
    if (cp >= 8224 and cp <= 8231) return true;
    if (cp >= 8240 and cp <= 8248) return true;
    if (cp == 8249) return true;
    if (cp == 8250) return true;
    if (cp >= 8251 and cp <= 8254) return true;
    if (cp >= 8257 and cp <= 8259) return true;
    if (cp == 8260) return true;
    if (cp == 8261) return true;
    if (cp == 8262) return true;
    if (cp >= 8263 and cp <= 8273) return true;
    if (cp == 8274) return true;
    if (cp == 8275) return true;
    if (cp >= 8277 and cp <= 8286) return true;
    if (cp >= 8592 and cp <= 8596) return true;
    if (cp >= 8597 and cp <= 8601) return true;
    if (cp >= 8602 and cp <= 8603) return true;
    if (cp >= 8604 and cp <= 8607) return true;
    if (cp == 8608) return true;
    if (cp >= 8609 and cp <= 8610) return true;
    if (cp == 8611) return true;
    if (cp >= 8612 and cp <= 8613) return true;
    if (cp == 8614) return true;
    if (cp >= 8615 and cp <= 8621) return true;
    if (cp == 8622) return true;
    if (cp >= 8623 and cp <= 8653) return true;
    if (cp >= 8654 and cp <= 8655) return true;
    if (cp >= 8656 and cp <= 8657) return true;
    if (cp == 8658) return true;
    if (cp == 8659) return true;
    if (cp == 8660) return true;
    if (cp >= 8661 and cp <= 8691) return true;
    if (cp >= 8692 and cp <= 8959) return true;
    if (cp >= 8960 and cp <= 8967) return true;
    if (cp == 8968) return true;
    if (cp == 8969) return true;
    if (cp == 8970) return true;
    if (cp == 8971) return true;
    if (cp >= 8972 and cp <= 8991) return true;
    if (cp >= 8992 and cp <= 8993) return true;
    if (cp >= 8994 and cp <= 9000) return true;
    if (cp == 9001) return true;
    if (cp == 9002) return true;
    if (cp >= 9003 and cp <= 9083) return true;
    if (cp == 9084) return true;
    if (cp >= 9085 and cp <= 9114) return true;
    if (cp >= 9115 and cp <= 9139) return true;
    if (cp >= 9140 and cp <= 9179) return true;
    if (cp >= 9180 and cp <= 9185) return true;
    if (cp >= 9186 and cp <= 9254) return true;
    if (cp >= 9255 and cp <= 9279) return true;
    if (cp >= 9280 and cp <= 9290) return true;
    if (cp >= 9291 and cp <= 9311) return true;
    if (cp >= 9472 and cp <= 9654) return true;
    if (cp == 9655) return true;
    if (cp >= 9656 and cp <= 9664) return true;
    if (cp == 9665) return true;
    if (cp >= 9666 and cp <= 9719) return true;
    if (cp >= 9720 and cp <= 9727) return true;
    if (cp >= 9728 and cp <= 9838) return true;
    if (cp == 9839) return true;
    if (cp >= 9840 and cp <= 10087) return true;
    if (cp == 10088) return true;
    if (cp == 10089) return true;
    if (cp == 10090) return true;
    if (cp == 10091) return true;
    if (cp == 10092) return true;
    if (cp == 10093) return true;
    if (cp == 10094) return true;
    if (cp == 10095) return true;
    if (cp == 10096) return true;
    if (cp == 10097) return true;
    if (cp == 10098) return true;
    if (cp == 10099) return true;
    if (cp == 10100) return true;
    if (cp == 10101) return true;
    if (cp >= 10132 and cp <= 10175) return true;
    if (cp >= 10176 and cp <= 10180) return true;
    if (cp == 10181) return true;
    if (cp == 10182) return true;
    if (cp >= 10183 and cp <= 10213) return true;
    if (cp == 10214) return true;
    if (cp == 10215) return true;
    if (cp == 10216) return true;
    if (cp == 10217) return true;
    if (cp == 10218) return true;
    if (cp == 10219) return true;
    if (cp == 10220) return true;
    if (cp == 10221) return true;
    if (cp == 10222) return true;
    if (cp == 10223) return true;
    if (cp >= 10224 and cp <= 10239) return true;
    if (cp >= 10240 and cp <= 10495) return true;
    if (cp >= 10496 and cp <= 10626) return true;
    if (cp == 10627) return true;
    if (cp == 10628) return true;
    if (cp == 10629) return true;
    if (cp == 10630) return true;
    if (cp == 10631) return true;
    if (cp == 10632) return true;
    if (cp == 10633) return true;
    if (cp == 10634) return true;
    if (cp == 10635) return true;
    if (cp == 10636) return true;
    if (cp == 10637) return true;
    if (cp == 10638) return true;
    if (cp == 10639) return true;
    if (cp == 10640) return true;
    if (cp == 10641) return true;
    if (cp == 10642) return true;
    if (cp == 10643) return true;
    if (cp == 10644) return true;
    if (cp == 10645) return true;
    if (cp == 10646) return true;
    if (cp == 10647) return true;
    if (cp == 10648) return true;
    if (cp >= 10649 and cp <= 10711) return true;
    if (cp == 10712) return true;
    if (cp == 10713) return true;
    if (cp == 10714) return true;
    if (cp == 10715) return true;
    if (cp >= 10716 and cp <= 10747) return true;
    if (cp == 10748) return true;
    if (cp == 10749) return true;
    if (cp >= 10750 and cp <= 11007) return true;
    if (cp >= 11008 and cp <= 11055) return true;
    if (cp >= 11056 and cp <= 11076) return true;
    if (cp >= 11077 and cp <= 11078) return true;
    if (cp >= 11079 and cp <= 11084) return true;
    if (cp >= 11085 and cp <= 11123) return true;
    if (cp >= 11124 and cp <= 11125) return true;
    if (cp >= 11126 and cp <= 11157) return true;
    if (cp == 11158) return true;
    if (cp >= 11159 and cp <= 11263) return true;
    if (cp >= 11776 and cp <= 11777) return true;
    if (cp == 11778) return true;
    if (cp == 11779) return true;
    if (cp == 11780) return true;
    if (cp == 11781) return true;
    if (cp >= 11782 and cp <= 11784) return true;
    if (cp == 11785) return true;
    if (cp == 11786) return true;
    if (cp == 11787) return true;
    if (cp == 11788) return true;
    if (cp == 11789) return true;
    if (cp >= 11790 and cp <= 11798) return true;
    if (cp == 11799) return true;
    if (cp >= 11800 and cp <= 11801) return true;
    if (cp == 11802) return true;
    if (cp == 11803) return true;
    if (cp == 11804) return true;
    if (cp == 11805) return true;
    if (cp >= 11806 and cp <= 11807) return true;
    if (cp == 11808) return true;
    if (cp == 11809) return true;
    if (cp == 11810) return true;
    if (cp == 11811) return true;
    if (cp == 11812) return true;
    if (cp == 11813) return true;
    if (cp == 11814) return true;
    if (cp == 11815) return true;
    if (cp == 11816) return true;
    if (cp == 11817) return true;
    if (cp >= 11818 and cp <= 11822) return true;
    if (cp == 11823) return true;
    if (cp >= 11824 and cp <= 11833) return true;
    if (cp >= 11834 and cp <= 11835) return true;
    if (cp >= 11836 and cp <= 11839) return true;
    if (cp == 11840) return true;
    if (cp == 11841) return true;
    if (cp == 11842) return true;
    if (cp >= 11843 and cp <= 11855) return true;
    if (cp >= 11856 and cp <= 11857) return true;
    if (cp == 11858) return true;
    if (cp >= 11859 and cp <= 11903) return true;
    if (cp >= 12289 and cp <= 12291) return true;
    if (cp == 12296) return true;
    if (cp == 12297) return true;
    if (cp == 12298) return true;
    if (cp == 12299) return true;
    if (cp == 12300) return true;
    if (cp == 12301) return true;
    if (cp == 12302) return true;
    if (cp == 12303) return true;
    if (cp == 12304) return true;
    if (cp == 12305) return true;
    if (cp >= 12306 and cp <= 12307) return true;
    if (cp == 12308) return true;
    if (cp == 12309) return true;
    if (cp == 12310) return true;
    if (cp == 12311) return true;
    if (cp == 12312) return true;
    if (cp == 12313) return true;
    if (cp == 12314) return true;
    if (cp == 12315) return true;
    if (cp == 12316) return true;
    if (cp == 12317) return true;
    if (cp >= 12318 and cp <= 12319) return true;
    if (cp == 12320) return true;
    if (cp == 12336) return true;
    if (cp == 64830) return true;
    if (cp == 64831) return true;
    if (cp >= 65093 and cp <= 65094) return true;
    return false;
}