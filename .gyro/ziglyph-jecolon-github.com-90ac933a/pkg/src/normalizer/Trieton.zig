//! `Trieton` is a trie implementation tailored for the `Normalizer` struct.

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Decomp = @import("DecompFile.zig").Decomp;

const Self = @This();

const Node = struct {
    value: ?Decomp = null,
    children: [256]?*Node = [_]?*Node{null} ** 256,

    fn deinit(self: *Node, allocator: mem.Allocator) void {
        for (self.children) |byte| {
            if (byte) |node| {
                node.deinit(allocator);
                allocator.destroy(node);
            }
        }
    }
};

allocator: mem.Allocator,
root: Node = Node{},

pub fn init(allocator: mem.Allocator) Self {
    return Self{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.root.deinit(self.allocator);
}

/// `add` a value for the specified key. Keys are slices of the key value type.
pub fn add(self: *Self, key: []const u8, value: Decomp) !void {
    var current = &self.root;

    for (key) |k| {
        if (current.children[k] == null) {
            var node = try self.allocator.create(Node);
            node.* = Node{};
            current.children[k] = node;
        }

        current = current.children[k].?;
    }

    current.value = value;
}

/// `Lookup` is returned from the find method on a successful match. The index field refers to
/// the index of the element in the key slice that produced the match.
pub const Lookup = struct {
    index: usize,
    value: Decomp,
};

/// `finds` the matching value for the given key, null otherwise.
pub fn find(self: Self, key: []const u8) ?Lookup {
    var current = &self.root;
    var result: ?Lookup = null;

    for (key) |k, i| {
        if (current.children[k] == null) break;

        if (current.children[k].?.value) |value| {
            result = .{
                .index = i,
                .value = value,
            };
        }

        current = current.children[k].?;
    }

    return result;
}

test "Normalizer Trieton" {
    var allocator = std.testing.allocator;
    var trie = init(allocator);
    defer trie.deinit();

    try trie.add(&[_]u8{ 2, 3 }, .{ .seq = [_]u21{ 33, 33, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } });
    const result = trie.find(&[_]u8{ 2, 3 });
    try testing.expect(result != null);
    try testing.expectEqual(result.?.index, 1);
    try testing.expectEqual(result.?.value.form, .canon);
    try testing.expectEqual(result.?.value.len, 2);
    try testing.expectEqual(result.?.value.seq[0], 33);
    try testing.expectEqual(result.?.value.seq[1], 33);
}
