const std = @import("std");
const mem = std.mem;

bytes: []const u8,
offset: usize,

const Self = @This();

pub fn eql(self: Self, str: []const u8) bool {
    return mem.eql(u8, self.bytes, str);
}
