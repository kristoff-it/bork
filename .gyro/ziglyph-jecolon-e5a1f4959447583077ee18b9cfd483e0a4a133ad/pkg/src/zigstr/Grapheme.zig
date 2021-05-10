const std = @import("std");
const mem = std.mem;
const Zigstr = @import("Zigstr.zig");

bytes: []const u8,
offset: usize,

const Self = @This();

pub fn eql(self: Self, str: []const u8) bool {
    return mem.eql(u8, self.bytes, str);
}

pub fn sameAs(self: Self, other: Self) bool {
    return (self.offset == other.offset) and mem.eql(u8, self.bytes, other.bytes);
}

pub fn toZigstr(self: Self, allocator: *mem.Allocator) !Zigstr {
    return Zigstr.init(allocator, self.bytes, false);
}
