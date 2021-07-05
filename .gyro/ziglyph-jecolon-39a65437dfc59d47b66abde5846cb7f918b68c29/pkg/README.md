# ziglyph
Unicode text processing for the Zig Programming Language.

### Looking for an UTF-8 String Type?
`Zigstr` is a UTF-8 string type that incorporates many of Ziglyph's Unicode processing tools. You can
learn more in the [Zigstr repo](https://github.com/jecolon/zigstr).

## Status
This is pre-1.0 software. Although breaking changes are less frequent with each minor version release,
they still will occur until we reach 1.0.

## Integrating Ziglyph in your Project
In a `libs` subdirectory under the root of your project, clone this repository via

```sh
$  git clone https://github.com/jecolon/ziglyph.git
```

Now in your build.zig, you can add:

```zig
exe.addPackagePath("Ziglyph", "libs/ziglyph/src/Ziglyph.zig");
```

to the `exe` section for the executable where you wish to have Ziglyph available. Now in the code, you
can import components like this:

```zig
const Ziglyph = @import("Ziglyph");
const Letter = @import("Ziglyph").Letter; // or const Letter = Ziglyph.Letter;
const Number = @import("Ziglyph").Number; // or const Number = Ziglyph.Number;

```

Finally, you can build the project with:

```sh
$ zig build
```

Note that to build in release modes, either specify them in the `build.zig` file or on the command line
via the `-Drelease-fast=true`, `-Drelease-small=true`, `-Drelease-safe=true` options to `zig build`.

### Using the Ziglyph Struct
The `Ziglyph` struct provides convenient acces to the most frequently-used functions related to Unicode.

```zig
const Ziglyph = @import("Ziglyph");

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
```

### Using Component Structs
Smaller aggregate structs are privided for specific areas of functionality.
See [components.zig](src/components.zig) for a full list of all components.

```zig
const Letter = @import("Ziglyph").Letter;
const Punct = @import("Ziglyph").Punct;

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
```

## Normalization
In addition to the basic functions to detect and convert code point case, the `Normalizer` struct 
provides code point and string normalization methods. This library currently only 
performs full canonical and compatibility decomposition and normalization (NFD and NFKD). Future 
versions may add more normalization forms. The `init` function takes an allocator and the path to the
compressed `Decompositions.bin` file derived from the Unicode Character Database. A copy of this file
is found in the `src/data/ucd` directory. See the section on Collation for more information on the 
compression algorithm applied the the Unicode data files for both Normalization and Collation.

```zig
const Normalizer = @import("Ziglyph").Normalizer;

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

    // String comparisons.
    try expect(try normalizer.eqlBy("foé", "foe\u{0301}", .normalize));
    try expect(try normalizer.eqlBy("foϓ", "fo\u{03D2}\u{0301}", .normalize));
    try expect(try normalizer.eqlBy("Foϓ", "fo\u{03D2}\u{0301}", .norm_ignore));
    try expect(try normalizer.eqlBy("FOÉ", "foe\u{0301}", .norm_ignore)); // foÉ == foé
}
```

## Collation (String Ordering)
One of the most common operations required by string processing is sorting and ordering comparisons.
The Unicode Collation Algorithm was developed to attend this area of string processing. The `Collator`
struct implements the algorithm, allowing for proper sorting and order comparison of Unicode strings.
The `init` function requires the path to a file with derived Unicode sort keys. The full file of keys
can be found [here](http://www.unicode.org/Public/UCA/latest/allkeys.txt). The derived copy of this file
can be found in the `src/data/uca` directory. This derived copy is compressed with a novel compression
algorithm developed by @slimsag / @hexops called Unicode Data Differential Compression (UDDC). The
algorithm achieves extremely efficient compression of the large Unicode data files required for 
Normalization and Collation. You can read more about it in 
[this blog post](https://devlog.hexops.com/2021/unicode-data-file-compression).
`init` also takes a pointer to a `Normalizer` because collation depends on normaliztion.

```
const Collator = @import("Ziglyph").Collator;

test "Collation" {
    var allocator = std.testing.allocator;
    var normalizer = try Normalizer.init(allocator, "../libs/ziglyph/src/data/ucd/Decompositions.bin");
    defer normalizer.deinit();
    var collator = try Collator.init(allocator, "../libs/ziglyph/src/data/uca/allkeys.bin", &normalizer);
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

## Grapheme Clusters
Many programming languages and libraries provide a basic `Character` or `char` type to represent what
we normally consider to be the characters that we see printed out composing strings of text. Unfortunately,
these implementations map these types to what Unicode calls a *code point*, which is only correct if 
you're working with basic latin letters and numbers, mostly in the ASCII character set space. When 
dealing with the vast majority of other languages, code points do not map directly to what we would 
consider *characters* of a string, but rather a single visible character can be composed of many code points,
combined to form a single human-readable character. In Unicode, these combinations of code points are
called *Grapheme Clusters* and Ziglyph provides the `GraphemeIterator` to extract individual *characters* 
(not just single code points) from a string.

```
const GraphemeIterator = @import("Ziglyph").GraphemeIterator;

test "GraphemeIterator" {
    var giter = try GraphemeIterator.new("H\u{0065}\u{0301}llo");

    const want = &[_][]const u8{ "H", "\u{0065}\u{0301}", "l", "l", "o" };

    var i: usize = 0;
    while (giter.next()) |gc| : (i += 1) {
        try expect(gc.eql(want[i]));
    }
}
```

## Code Point and String Width
When working with environments in which text is rendered in a fixed-width font, such as terminal 
emulators, it's necessary to know how many cells (or columns) a particular code point or string will
occupy. The `Width` component struct provides methods to do just that.

```
const Width = @import("Ziglyph").Width;

test "Code point / string widths" {
    // The width methods take a second parameter of value .half or .full to determine the width of 
    // ambiguous code points as per the Unicode standard. .half is the most common case.

    // Note that codePointWidth returns an i3 because code points like backspace have width -1.
    try expectEqual(Width.codePointWidth('é', .half), 1);
    try expectEqual(Width.codePointWidth('😊', .half), 2);
    try expectEqual(Width.codePointWidth('统', .half), 2);

    // strWidth returns usize because it can never be negative, regardless of the code points it contains.
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
```
