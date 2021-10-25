//! `CodePoint` represents a Unicode code point wit hrealted functionality.

const std = @import("std");
const unicode = std.unicode;

bytes: []const u8,
offset: usize,
scalar: u21,

const CodePoint = @This();

/// `end` returns the index of the byte after this code points last byte in the source string.
pub fn end(self: CodePoint) usize {
    return self.offset + self.bytes.len;
}

/// `CodePointIterator` iterates a string one code point at-a-time.
pub const CodePointIterator = struct {
    bytes: []const u8,
    i: usize = 0,

    pub fn next(it: *CodePointIterator) ?CodePoint {
        if (it.i >= it.bytes.len) {
            return null;
        }

        var cp = CodePoint{
            .bytes = undefined,
            .offset = it.i,
            .scalar = undefined,
        };

        const cp_len = unicode.utf8ByteSequenceLength(it.bytes[it.i]) catch unreachable;
        it.i += cp_len;
        cp.bytes = it.bytes[it.i - cp_len .. it.i];

        cp.scalar = switch (cp.bytes.len) {
            1 => @as(u21, cp.bytes[0]),
            2 => unicode.utf8Decode2(cp.bytes) catch unreachable,
            3 => unicode.utf8Decode3(cp.bytes) catch unreachable,
            4 => unicode.utf8Decode4(cp.bytes) catch unreachable,
            else => unreachable,
        };

        return cp;
    }
};
