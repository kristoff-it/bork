//! CodePointIterator retrieves the code points of a string.
const std = @import("std");
const unicode = std.unicode;

bytes: []const u8,
current: ?u21,
i: usize,
prev: ?u21,
prev_i: usize,

const Self = @This();

pub fn init(str: []const u8) !Self {
    if (!unicode.utf8ValidateSlice(str)) {
        return error.InvalidUtf8;
    }

    return Self{
        .bytes = str,
        .current = null,
        .i = 0,
        .prev = null,
        .prev_i = 0,
    };
}

// nexCodePointSlice retrieves the next code point's bytes.
pub fn nextCodePointSlice(self: *Self) ?[]const u8 {
    if (self.i >= self.bytes.len) {
        return null;
    }

    const cp_len = unicode.utf8ByteSequenceLength(self.bytes[self.i]) catch unreachable;
    self.prev_i = self.i;
    self.i += cp_len;
    return self.bytes[self.i - cp_len .. self.i];
}

/// nextCodePoint retrieves the next code point as a single u21.
pub fn next(self: *Self) ?u21 {
    const slice = self.nextCodePointSlice() orelse return null;
    self.prev = self.current;

    switch (slice.len) {
        1 => self.current = @as(u21, slice[0]),
        2 => self.current = unicode.utf8Decode2(slice) catch unreachable,
        3 => self.current = unicode.utf8Decode3(slice) catch unreachable,
        4 => self.current = unicode.utf8Decode4(slice) catch unreachable,
        else => unreachable,
    }

    return self.current;
}

/// peekN looks ahead at the next n codepoints without advancing the iterator.
/// If fewer than n codepoints are available, then return the remainder of the string.
pub fn peekN(self: *Self) []const u8 {
    const original_i = self.i;
    defer self.i = original_i;

    var end_ix = original_i;
    var found: usize = 0;
    while (found < n) : (found += 1) {
        const next_codepoint = self.nextCodePointSlice() orelse return self.bytes[original_i..];
        end_ix += next_codepoint.len;
    }

    return self.bytes[original_i..end_ix];
}

/// peek looks ahead at the next codepoint without advancing the iterator.
pub fn peek(self: *Self) ?u21 {
    const original_i = self.i;
    const original_prev_i = self.prev_i;
    const original_prev = self.prev;
    defer {
        self.i = original_i;
        self.prev_i = original_prev_i;
        self.prev = original_prev;
    }
    return self.next();
}

/// reset prepares the iterator to start over iteration.
pub fn reset(self: *Self) void {
    self.current = null;
    self.i = 0;
    self.prev = null;
    self.prev_i = 0;
}
