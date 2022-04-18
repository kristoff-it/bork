# ziglyph
Unicode text processing for the Zig Programming Language.

## In-Depth Articles on Unicode Processing with Zig and Ziglyph
The [Unicode Processing with Zig](https://zig.news/dude_the_builder/series/6) series of articles over on
ZigNEWS covers important aspects of Unicode in general and in particular how to use this library to process 
Unicode text.

## Looking for an UTF-8 String Type?
`Zigstr` is a UTF-8 string type that incorporates many of Ziglyph's Unicode processing tools. You can
learn more in the [Zigstr repo](https://github.com/jecolon/zigstr).

## Status
This is pre-1.0 software. Although breaking changes are less frequent with each minor version release,
they still will occur until we reach 1.0.

## Integrating Ziglyph in your Project
### Using Zigmod

```sh
$ zigmod aq add 1/jecolon/zigstr
$ zigmod fetch
```

Now in your `build.zig` you add this import:

```zig
const deps = @import("deps.zig");
```

In the `exe` section for the executable where you wish to have Zigstr available, add:

```zig
deps.addAllTo(exe);
```

### Manually via Git
In a `libs` subdirectory under the root of your project, clone this repository via

```sh
$  git clone https://github.com/jecolon/ziglyph.git
```

Now in your build.zig, you can add:

```zig
exe.addPackagePath("ziglyph", "libs/ziglyph/src/ziglyph.zig");
```

to the `exe` section for the executable where you wish to have Ziglyph available. Now in the code, you
can import components like this:

```zig
const ziglyph = @import("ziglyph");
const letter = @import("ziglyph").letter; // or const letter = ziglyph.letter;
const number = @import("ziglyph").number; // or const number = ziglyph.number;
```

### Using the `ziglyph` Namespace
The `ziglyph` namespace provides convenient acces to the most frequently-used functions related to Unicode
code points and strings.

```zig
const ziglyph = @import("ziglyph");

test "ziglyph namespace" {
    const z = 'z';
    try expect(ziglyph.isLetter(z));
    try expect(ziglyph.isAlphaNum(z));
    try expect(ziglyph.isPrint(z));
    try expect(!ziglyph.isUpper(z));
    const uz = ziglyph.toUpper(z);
    try expect(ziglyph.isUpper(uz));
    try expectEqual(uz, 'Z');

    // String toLower, toTitle, and toUpper.
    var allocator = std.testing.allocator;
    var got = try ziglyph.toLowerStr(allocator, "AbC123");
    errdefer allocator.free(got);
    try expect(std.mem.eql(u8, "abc123", got));
    allocator.free(got);

    got = try ziglyph.toUpperStr(allocator, "aBc123");
    errdefer allocator.free(got);
    try expect(std.mem.eql(u8, "ABC123", got));
    allocator.free(got);

    got = try ziglyph.toTitleStr(allocator, "thE aBc123 moVie. yes!");
    defer allocator.free(got);
    try expect(std.mem.eql(u8, "The Abc123 Movie. Yes!", got));
}
```

### Category Namespaces
Namespaces for frequently-used Unicode General Categories are available.
See [ziglyph.zig](src/ziglyph.zig) for a full list of all components.

```zig
const letter = @import("ziglyph").letter;
const punct = @import("ziglyph").punct;

test "Category namespaces" {
    const z = 'z';
    try expect(letter.isletter(z));
    try expect(!letter.isUpper(z));
    try expect(!punct.ispunct(z));
    try expect(punct.ispunct('!'));
    const uz = letter.toUpper(z);
    try expect(letter.isUpper(uz));
    try expectEqual(uz, 'Z');
}
```

## Normalization
In addition to the basic functions to detect and convert code point case, the `Normalizer` struct 
provides code point and string normalization methods. All normalization forms are supported (NFC,
NFKC, NFD, NFKD.).

```zig
const Normalizer = @import("ziglyph").Normalizer;

test "normalizeTo" {
    var allocator = std.testing.allocator;
    var normalizer = try Normalizer.init(allocator);
    defer normalizer.deinit();

    // Canonical Composition (NFC)
    const input_nfc = "Complex char: \u{03D2}\u{0301}";
    const want_nfc = "Complex char: \u{03D3}";
    const got_nfc = try normalizer.normalizeTo(.composed, input_nfc);
    try expectEqualSlices(u8, want_nfc, got_nfc);

    // Compatibility Composition (NFKC)
    const input_nfkc = "Complex char: \u{03A5}\u{0301}";
    const want_nfkc = "Complex char: \u{038E}";
    const got_nfkc = try normalizer.normalizeTo(.komposed, input_nfkc);
    try expectEqualSlices(u8, want_nfkc, got_nfkc);

    // Canonical Decomposition (NFD)
    const input_nfd = "Complex char: \u{03D3}";
    const want_nfd = "Complex char: \u{03D2}\u{0301}";
    const got_nfd = try normalizer.normalizeTo(.canon, input_nfd);
    try expectEqualSlices(u8, want_nfd, got_nfd);

    // Compatibility Decomposition (NFKD)
    const input_nfkd = "Complex char: \u{03D3}";
    const want_nfkd = "Complex char: \u{03A5}\u{0301}";
    const got_nfkd = try normalizer.normalizeTo(.compat, input_nfkd);
    try expectEqualSlices(u8, want_nfkd, got_nfkd);

    // String comparisons.
    try expect(try normalizer.eqlBy("foé", "foe\u{0301}", .normalize));
    try expect(try normalizer.eqlBy("foϓ", "fo\u{03D2}\u{0301}", .normalize));
    try expect(try normalizer.eqlBy("Foϓ", "fo\u{03D2}\u{0301}", .norm_ignore));
    try expect(try normalizer.eqlBy("FOÉ", "foe\u{0301}", .norm_ignore)); // foÉ == foé
    try expect(try normalizer.eqlBy("Foé", "foé", .ident)); // Unicode Identifiers caseless match.
}
```

## Collation (String Ordering)
One of the most common operations required by string processing is sorting and ordering comparisons.
The Unicode Collation Algorithm was developed to attend this area of string processing. The `Collator`
struct implements the algorithm, allowing for proper sorting and order comparison of Unicode strings.
Aside from the usual `init` function, there's `initWithReader` which you can use to initialize the 
struct with an alternate weights table file (`allkeys.bin`), be it a file, a network stream, or anything
else that exposes a `std.io.Reader`. This allows for tailoring of the sorting algorithm.


```zig
const Collator = @import("ziglyph").Collator;

test "Collation" {
    var allocator = std.testing.allocator;
    var collator = try Collator.init(allocator);
    defer collator.deinit();

    // Collation weight levels overview:
    // * .primary: different letters.
    // * .secondary: could be same letters but with marks (like accents) differ.
    // * .tertiary: same letters and marks but case is different.
    // So cab < dab at .primary, and cab < cáb at .secondary, and cáb < Cáb at .tertiary level.
    testing.expect(collator.tertiaryAsc("abc", "def"));
    testing.expect(collator.tertiaryDesc("def", "abc"));

    // At only primary level, José and jose are equal because base letters are the same, only marks 
    // and case differ, which are .secondary and .tertiary respectively.
    testing.expect(try collator.orderFn("José", "jose", .primary, .eq));

    // Full Unicode sort.
    var strings: [3][]const u8 = .{ "xyz", "def", "abc" };
    collator.sortAsc(&strings);
    testing.expectEqual(strings[0], "abc");
    testing.expectEqual(strings[1], "def");
    testing.expectEqual(strings[2], "xyz");

    // ASCII only binary sort. If you know the strings are ASCII only, this is much faster.
    strings = .{ "xyz", "def", "abc" };
    collator.sortAsciiAsc(&strings);
    testing.expectEqual(strings[0], "abc");
    testing.expectEqual(strings[1], "def");
    testing.expectEqual(strings[2], "xyz");
}
```

### Tailoring With `allkeys.txt`
To tailor the sorting algorithm, you can create a modified `allkeys.txt` and generate a new compressed binary `allkeys.bin`
file from it. Follow these steps:

```sh
# Change to the Ziglyph source directory.
cd <path to ziglyph>/src/
# Build the UDDC tool for your platform.
zig build-exe -O ReleaseSafe uddc.zig
# Create a new directory to store the UDDC tool and modified data files.
mkdir <path to new data dir>
# Move the tool and copy the data file to the new directory.
mv uddc <path to new data dir>/
cp data/uca/allkeys.txt <path to new data dir>/
# Change into the new data dir.
cd <path to new data dir>/
# Modifiy the allkeys.txt file with your favorite editor.
vim allkeys.txt
# Generate the new compressed binary allkeys.bin
./uddc allkeys.txt
```

After running these commands, you can then use this new allkeys.bin file with the `initWithReader` method:

```zig
const Collator = @import("ziglyph").Collator;

var file = try std.fs.cwd().openFile("<path to new data dir>/allkeys.bin", .{});
defer file.close();
var reader = std.io.bufferedReader(file.reader()).reader();
var collator = try Collator.initWithReader(allocator, reader);
defer collator.deinit();

// ...use the collator as usual.
```

## Text Segmentation (Grapheme Clusters, Words, Sentences)
Ziglyph has iterators to traverse text as Grapheme Clusters (what most people recognize as *characters*), 
Words, and Sentences. All of these text segmentation functions adhere to the Unicode Text Segmentation rules,
which may surprise you in terms of what's included and excluded at each break point. Test before assuming any
results! There are also non-allocating compile-time versions for use with string literals or embedded files.
Note that for compile-time versions, you may need to increase the compile-time branch evaluation quota via
`@setEvalBranchQuota`.

```zig
const Grapheme = @import("ziglyph").Grapheme;
const GraphemeIterator = Grapheme.GraphemeIterator;
const SentenceIterator = Sentence.SentenceIterator;
const ComptimeSentenceIterator = Sentence.ComptimeSentenceIterator;
const Word = @import("ziglyph").Word;
const WordIterator = Word.WordIterator;

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
```

## Code Point and String Display Width
When working with environments in which text is rendered in a fixed-width font, such as terminal 
emulators, it's necessary to know how many cells (or columns) a particular code point or string will
occupy. The `display_width` namespace provides functions to do just that.

```zig
const dw = @import("ziglyph").display_width;

test "Code point / string widths" {
    // The width methods take a second parameter of value .half or .full to determine the width of 
    // ambiguous code points as per the Unicode standard. .half is the most common case.

    // Note that codePointWidth returns an i3 because code points like backspace have width -1.
    try expectEqual(dw.codePointWidth('é', .half), 1);
    try expectEqual(dw.codePointWidth('😊', .half), 2);
    try expectEqual(dw.codePointWidth('统', .half), 2);

    var allocator = std.testing.allocator;

    // strWidth returns usize because it can never be negative, regardless of the code points it contains.
    try expectEqual(try dw.strWidth("Hello\r\n", .half), 5);
    try expectEqual(try dw.strWidth("\u{1F476}\u{1F3FF}\u{0308}\u{200D}\u{1F476}\u{1F3FF}", .half), 2);
    try expectEqual(try dw.strWidth("Héllo 🇵🇷", .half), 8);
    try expectEqual(try dw.strWidth("\u{26A1}\u{FE0E}", .half), 1); // Text sequence
    try expectEqual(try dw.strWidth("\u{26A1}\u{FE0F}", .half), 2); // Presentation sequence

    // padLeft, center, padRight
    const right_aligned = try dw.padLeft(allocator, "w😊w", 10, "-");
    defer allocator.free(right_aligned);
    try expectEqualSlices(u8, "------w😊w", right_aligned);

    const centered = try dw.center(allocator, "w😊w", 10, "-");
    defer allocator.free(centered);
    try expectEqualSlices(u8, "---w😊w---", centered);

    const left_aligned = try dw.padRight(allocator, "w😊w", 10, "-");
    defer allocator.free(left_aligned);
    try expectEqualSlices(u8, "w😊w------", left_aligned);
}
```

## Word Wrap
If you need to wrap a string to a specific number of columns according to Unicode Word boundaries and display width,
you can use the `display_width` struct's `wrap` function for this. You can also specify a threshold value indicating how close
a word boundary can be to the column limit and trigger a line break.

```zig
const dw = @import("ziglyph").display_width;

test "display_width wrap" {
    var allocator = testing.allocator;
    var input = "The quick brown fox\r\njumped over the lazy dog!";
    var got = try dw.wrap(allocator, input, 10, 3);
    defer allocator.free(got);
    var want = "The quick\n brown \nfox jumped\n over the\n lazy dog\n!";
    try testing.expectEqualStrings(want, got);
}
```
