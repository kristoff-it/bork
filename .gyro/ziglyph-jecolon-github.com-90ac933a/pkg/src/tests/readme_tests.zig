const std = @import("std");
const testing = std.testing;

// Import structs.
const ziglyph = @import("../ziglyph.zig");
const Collator = ziglyph.Collator;
const Grapheme = ziglyph.Grapheme;
const GraphemeIterator = Grapheme.GraphemeIterator;
const letter = ziglyph.letter;
const Normalizer = ziglyph.Normalizer;
const punct = ziglyph.punct;
const Sentence = ziglyph.Sentence;
const SentenceIterator = Sentence.SentenceIterator;
const ComptimeSentenceIterator = Sentence.ComptimeSentenceIterator;
const upper_map = ziglyph.upper_map;
const display_width = ziglyph.display_width;
const Word = ziglyph.Word;
const WordIterator = Word.WordIterator;

test "ziglyph struct" {
    const z = 'z';
    try testing.expect(ziglyph.isLetter(z));
    try testing.expect(ziglyph.isAlphaNum(z));
    try testing.expect(ziglyph.isPrint(z));
    try testing.expect(!ziglyph.isUpper(z));
    const uz = ziglyph.toUpper(z);
    try testing.expect(ziglyph.isUpper(uz));
    try testing.expectEqual(uz, 'Z');
    const tz = ziglyph.toTitle(z);
    try testing.expect(ziglyph.isUpper(tz));
    try testing.expectEqual(tz, 'Z');

    // String toLower, toTitle and toUpper.
    var allocator = std.testing.allocator;
    var got = try ziglyph.toLowerStr(allocator, "AbC123");
    errdefer allocator.free(got);
    try testing.expect(std.mem.eql(u8, "abc123", got));
    allocator.free(got);
    got = try ziglyph.toUpperStr(allocator, "aBc123");
    errdefer allocator.free(got);
    try testing.expect(std.mem.eql(u8, "ABC123", got));
    allocator.free(got);
    got = try ziglyph.toTitleStr(allocator, "thE aBc123 moVie. yes!");
    defer allocator.free(got);
    try testing.expect(std.mem.eql(u8, "The Abc123 Movie. Yes!", got));
}

test "Aggregate struct" {
    const z = 'z';
    try testing.expect(letter.isLetter(z));
    try testing.expect(!letter.isUpper(z));
    try testing.expect(!punct.isPunct(z));
    try testing.expect(punct.isPunct('!'));
    const uz = letter.toUpper(z);
    try testing.expect(letter.isUpper(uz));
    try testing.expectEqual(uz, 'Z');
}

test "Component structs" {
    const z = 'z';
    try testing.expect(letter.isLower(z));
    try testing.expect(!letter.isUpper(z));
    const uz = upper_map.toUpper(z);
    try testing.expect(letter.isUpper(uz));
    try testing.expectEqual(uz, 'Z');
}

test "normalizeTo" {
    var allocator = std.testing.allocator;
    var normalizer = try Normalizer.init(allocator);
    defer normalizer.deinit();

    // Canonical Composition (NFC)
    const input_nfc = "Complex char: \u{03D2}\u{0301}";
    const want_nfc = "Complex char: \u{03D3}";
    const got_nfc = try normalizer.normalizeTo(.composed, input_nfc);
    try testing.expectEqualSlices(u8, want_nfc, got_nfc);

    // Compatibility Composition (NFKC)
    const input_nfkc = "Complex char: \u{03A5}\u{0301}";
    const want_nfkc = "Complex char: \u{038E}";
    const got_nfkc = try normalizer.normalizeTo(.komposed, input_nfkc);
    try testing.expectEqualSlices(u8, want_nfkc, got_nfkc);

    // Canonical Decomposition (NFD)
    const input_nfd = "Complex char: \u{03D3}";
    const want_nfd = "Complex char: \u{03D2}\u{0301}";
    const got_nfd = try normalizer.normalizeTo(.canon, input_nfd);
    try testing.expectEqualSlices(u8, want_nfd, got_nfd);

    // Compatibility Decomposition (NFKD)
    const input_nfkd = "Complex char: \u{03D3}";
    const want_nfkd = "Complex char: \u{03A5}\u{0301}";
    const got_nfkd = try normalizer.normalizeTo(.compat, input_nfkd);
    try testing.expectEqualSlices(u8, want_nfkd, got_nfkd);

    // String comparisons.
    try testing.expect(try normalizer.eqlBy("foé", "foe\u{0301}", .normalize));
    try testing.expect(try normalizer.eqlBy("foϓ", "fo\u{03D2}\u{0301}", .normalize));
    try testing.expect(try normalizer.eqlBy("Foϓ", "fo\u{03D2}\u{0301}", .norm_ignore));
    try testing.expect(try normalizer.eqlBy("FOÉ", "foe\u{0301}", .norm_ignore)); // foÉ == foé
    try testing.expect(try normalizer.eqlBy("Foé", "foé", .ident)); // Unicode Identifiers caseless match.
}

test "GraphemeIterator" {
    const input = "H\u{0065}\u{0301}llo";
    var iter = try GraphemeIterator.init(input);

    const want = &[_][]const u8{ "H", "\u{0065}\u{0301}", "l", "l", "o" };

    var i: usize = 0;
    while (iter.next()) |grapheme| : (i += 1) {
        try testing.expect(grapheme.eql(want[i]));
    }

    // Need your grapheme clusters at compile time?
    comptime {
        var ct_iter = try GraphemeIterator.init(input);
        var j = 0;
        while (ct_iter.next()) |grapheme| : (j += 1) {
            try testing.expect(grapheme.eql(want[j]));
        }
    }
}

test "SentenceIterator" {
    var allocator = std.testing.allocator;
    const input =
        \\("Go.") ("He said.")
    ;
    var iter = try SentenceIterator.init(allocator, input);
    defer iter.deinit();

    // Note the space after the closing right parenthesis is included as part
    // of the first sentence.
    const s1 =
        \\("Go.") 
    ;
    const s2 =
        \\("He said.")
    ;
    const want = &[_][]const u8{ s1, s2 };

    var i: usize = 0;
    while (iter.next()) |sentence| : (i += 1) {
        try testing.expectEqualStrings(sentence.bytes, want[i]);
    }

    // Need your sentences at compile time?
    @setEvalBranchQuota(2_000);

    comptime var ct_iter = ComptimeSentenceIterator(input){};
    const n = comptime ct_iter.count();
    var sentences: [n]Sentence = undefined;
    comptime {
        var ct_i: usize = 0;
        while (ct_iter.next()) |sentence| : (ct_i += 1) {
            sentences[ct_i] = sentence;
        }
    }

    for (sentences) |sentence, j| {
        try testing.expect(sentence.eql(want[j]));
    }
}

test "WordIterator" {
    const input = "The (quick) fox. Fast! ";
    var iter = try WordIterator.init(input);

    const want = &[_][]const u8{ "The", " ", "(", "quick", ")", " ", "fox", ".", " ", "Fast", "!", " " };

    var i: usize = 0;
    while (iter.next()) |word| : (i += 1) {
        try testing.expectEqualStrings(word.bytes, want[i]);
    }

    // Need your words at compile time?
    @setEvalBranchQuota(2_000);

    comptime {
        var ct_iter = try WordIterator.init(input);
        var j = 0;
        while (ct_iter.next()) |word| : (j += 1) {
            try testing.expect(word.eql(want[j]));
        }
    }
}

test "Code point / string widths" {
    var allocator = std.testing.allocator;
    try testing.expectEqual(display_width.codePointWidth('é', .half), 1);
    try testing.expectEqual(display_width.codePointWidth('😊', .half), 2);
    try testing.expectEqual(display_width.codePointWidth('统', .half), 2);
    try testing.expectEqual(try display_width.strWidth("Hello\r\n", .half), 5);
    try testing.expectEqual(try display_width.strWidth("\u{1F476}\u{1F3FF}\u{0308}\u{200D}\u{1F476}\u{1F3FF}", .half), 2);
    try testing.expectEqual(try display_width.strWidth("Héllo 🇪🇸", .half), 8);
    try testing.expectEqual(try display_width.strWidth("\u{26A1}\u{FE0E}", .half), 1); // Text sequence
    try testing.expectEqual(try display_width.strWidth("\u{26A1}\u{FE0F}", .half), 2); // Presentation sequence

    // padLeft, center, padRight
    const right_aligned = try display_width.padLeft(allocator, "w😊w", 10, "-");
    defer allocator.free(right_aligned);
    try testing.expectEqualSlices(u8, "------w😊w", right_aligned);

    const centered = try display_width.center(allocator, "w😊w", 10, "-");
    defer allocator.free(centered);
    try testing.expectEqualSlices(u8, "---w😊w---", centered);

    const left_aligned = try display_width.padRight(allocator, "w😊w", 10, "-");
    defer allocator.free(left_aligned);
    try testing.expectEqualSlices(u8, "w😊w------", left_aligned);
}

test "Collation" {
    var allocator = std.testing.allocator;
    var collator = try Collator.init(allocator);
    defer collator.deinit();

    try testing.expect(collator.tertiaryAsc("abc", "def"));
    try testing.expect(collator.tertiaryDesc("def", "abc"));
    try testing.expect(try collator.orderFn("José", "jose", .primary, .eq));

    var strings: [3][]const u8 = .{ "xyz", "def", "abc" };
    collator.sortAsc(&strings);
    try testing.expectEqual(strings[0], "abc");
    try testing.expectEqual(strings[1], "def");
    try testing.expectEqual(strings[2], "xyz");

    strings = .{ "xyz", "def", "abc" };
    collator.sortAsciiAsc(&strings);
    try testing.expectEqual(strings[0], "abc");
    try testing.expectEqual(strings[1], "def");
    try testing.expectEqual(strings[2], "xyz");
}

test "display_width wrap" {
    var allocator = testing.allocator;
    var input = "The quick brown fox\r\njumped over the lazy dog!";
    var got = try display_width.wrap(allocator, input, 10, 3);
    defer allocator.free(got);
    var want = "The quick\n brown \nfox jumped\n over the\n lazy dog\n!";
    try testing.expectEqualStrings(want, got);
}
