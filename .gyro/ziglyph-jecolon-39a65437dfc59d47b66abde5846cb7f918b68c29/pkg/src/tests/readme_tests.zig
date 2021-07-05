const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

// Import structs.
const Ziglyph = @import("../Ziglyph.zig");
const Collator = Ziglyph.Collator;
const GraphemeIterator = Ziglyph.GraphemeIterator;
const Letter = Ziglyph.Letter;
const Normalizer = Ziglyph.Normalizer;
const Punct = Ziglyph.Punct;
const UpperMap = Ziglyph.UpperMap;
const Width = Ziglyph.Width;

test "Ziglyph struct" {
    const z = 'z';
    try expect(Ziglyph.isLetter(z));
    try expect(Ziglyph.isAlphaNum(z));
    try expect(Ziglyph.isPrint(z));
    try expect(!Ziglyph.isUpper(z));
    const uz = Ziglyph.toUpper(z);
    try expect(Ziglyph.isUpper(uz));
    try expectEqual(uz, 'Z');
}

test "Aggregate struct" {
    const z = 'z';
    try expect(Letter.isLetter(z));
    try expect(!Letter.isUpper(z));
    try expect(!Punct.isPunct(z));
    try expect(Punct.isPunct('!'));
    const uz = Letter.toUpper(z);
    try expect(Letter.isUpper(uz));
    try expectEqual(uz, 'Z');
}

test "Component structs" {
    const z = 'z';
    try expect(Letter.isLower(z));
    try expect(!Letter.isUpper(z));
    const uz = UpperMap.toUpper(z);
    try expect(Letter.isUpper(uz));
    try expectEqual(uz, 'Z');
}

test "normalizeTo" {
    var allocator = std.testing.allocator;
    var normalizer = try Normalizer.init(allocator, "src/data/ucd/Decompositions.bin");
    defer normalizer.deinit();

    // Canonical (NFD)
    var input = "Complex char: \u{03D3}";
    var want = "Complex char: \u{03D2}\u{0301}";
    var got = try normalizer.normalizeTo(.canon, input);
    try expectEqualSlices(u8, want, got);

    // Compatibility (NFKD)
    input = "Complex char: \u{03D3}";
    want = "Complex char: \u{03A5}\u{0301}";
    got = try normalizer.normalizeTo(.compat, input);
    try expectEqualSlices(u8, want, got);
}

test "GraphemeIterator" {
    var giter = try GraphemeIterator.new("H\u{0065}\u{0301}llo");

    const want = &[_][]const u8{ "H", "\u{0065}\u{0301}", "l", "l", "o" };

    var i: usize = 0;
    while (giter.next()) |gc| : (i += 1) {
        try expect(gc.eql(want[i]));
    }
}

test "Code point / string widths" {
    try expectEqual(Width.codePointWidth('é', .half), 1);
    try expectEqual(Width.codePointWidth('😊', .half), 2);
    try expectEqual(Width.codePointWidth('统', .half), 2);
    try expectEqual(try Width.strWidth("Hello\r\n", .half), 5);
    try expectEqual(try Width.strWidth("\u{1F476}\u{1F3FF}\u{0308}\u{200D}\u{1F476}\u{1F3FF}", .half), 2);
    try expectEqual(try Width.strWidth("Héllo 🇪🇸", .half), 8);
    try expectEqual(try Width.strWidth("\u{26A1}\u{FE0E}", .half), 1); // Text sequence
    try expectEqual(try Width.strWidth("\u{26A1}\u{FE0F}", .half), 2); // Presentation sequence

    var allocator = std.testing.allocator;

    // padLeft, center, padRight
    const right_aligned = try Width.padLeft(allocator, "w😊w", 10, "-");
    defer allocator.free(right_aligned);
    try expectEqualSlices(u8, "------w😊w", right_aligned);

    const centered = try Width.center(allocator, "w😊w", 10, "-");
    defer allocator.free(centered);
    try expectEqualSlices(u8, "---w😊w---", centered);

    const left_aligned = try Width.padRight(allocator, "w😊w", 10, "-");
    defer allocator.free(left_aligned);
    try expectEqualSlices(u8, "w😊w------", left_aligned);
}

test "Collation" {
    var allocator = std.testing.allocator;
    var normalizer = try Normalizer.init(allocator, "src/data/ucd/Decompositions.bin");
    defer normalizer.deinit();
    var collator = try Collator.init(allocator, "src/data/uca/allkeys.bin", &normalizer);
    defer collator.deinit();

    try expect(collator.tertiaryAsc("abc", "def"));
    try expect(collator.tertiaryDesc("def", "abc"));
    try expect(try collator.orderFn("José", "jose", .primary, .eq));

    var strings: [3][]const u8 = .{ "xyz", "def", "abc" };
    collator.sortAsc(&strings);
    try expectEqual(strings[0], "abc");
    try expectEqual(strings[1], "def");
    try expectEqual(strings[2], "xyz");

    strings = .{ "xyz", "def", "abc" };
    collator.sortAsciiAsc(&strings);
    try expectEqual(strings[0], "abc");
    try expectEqual(strings[1], "def");
    try expectEqual(strings[2], "xyz");
}
