test "ziglyph" {
    _ = @import("ziglyph.zig");
}

test "Normalizer" {
    _ = @import("ziglyph.zig").Normalizer;
}

test "Segmentation" {
    _ = @import("ziglyph.zig").CodePoint;
    _ = @import("ziglyph.zig").Grapheme;
    _ = @import("ziglyph.zig").Word;
    _ = @import("ziglyph.zig").Sentence;
}

test "ziglyph" {
    _ = @import("ziglyph.zig").letter;
    _ = @import("ziglyph.zig").mark;
    _ = @import("ziglyph.zig").number;
    _ = @import("ziglyph.zig").punct;
    _ = @import("ziglyph.zig").symbol;
}

test "Collator" {
    _ = @import("ziglyph.zig").Collator;
}

test "display_width" {
    _ = @import("ziglyph.zig").display_width;
}

test "README" {
    _ = @import("tests/readme_tests.zig");
}
