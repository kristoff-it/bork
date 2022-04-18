//! `Collator` implements the Unicode Collation Algorithm to sort Unicode strings.

const std = @import("std");
const atomic = std.atomic;
const fmt = std.fmt;
const io = std.io;
const math = std.math;
const mem = std.mem;
const testing = std.testing;
const unicode = std.unicode;
const zort = std.sort.sort;

pub const AllKeysFile = @import("AllKeysFile.zig");

const ccc_map = @import("../ziglyph.zig").combining_map;
const Elements = @import("AllKeysFile.zig").Elements;
const Normalizer = @import("../ziglyph.zig").Normalizer;
const props = @import("../ziglyph.zig").prop_list;
const Trie = @import("CollatorTrie.zig");

allocator: mem.Allocator,
arena: std.heap.ArenaAllocator,
implicits: []AllKeysFile.Implicit,
normalizer: Normalizer,
table: Trie,

const Self = @This();

/// `init` produces a new Collator using the Default Unicode Collation Elements Table (DUCET) in `src/data/uca/allkeys.bin`.
pub fn init(allocator: mem.Allocator) !Self {
    var self = Self{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .implicits = undefined,
        .normalizer = try Normalizer.init(allocator),
        .table = Trie.init(allocator),
    };

    const allkeys = @embedFile("../data/uca/allkeys.bin");
    var reader = std.io.fixedBufferStream(allkeys).reader();
    var file = try AllKeysFile.decompress(allocator, reader);
    defer file.deinit();

    while (file.next()) |entry| {
        try self.table.add(entry.key, entry.value);
    }

    self.implicits = file.implicits.toOwnedSlice();

    return self;
}

/// `initWithReader` allows tailoring of the sorting algorithm via a supplied alternate weights table. The `reader`
/// parameter can be a file, network stream, or anything else that exposes a `std.io.Reader`.
pub fn initWithReader(allocator: mem.Allocator, reader: anytype) !Self {
    var self = Self{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .implicits = undefined,
        .normalizer = try Normalizer.init(allocator),
        .table = Trie.init(allocator),
    };

    var file = try AllKeysFile.decompress(allocator, reader);
    defer file.deinit();

    while (file.next()) |entry| {
        try self.table.add(entry.key, entry.value);
    }

    self.implicits = file.implicits.toOwnedSlice();

    return self;
}

pub fn deinit(self: *Self) void {
    self.normalizer.deinit();
    self.table.deinit();
    self.arena.child_allocator.free(self.implicits);
    self.arena.deinit();
}

fn collationElements(self: *Self, normalized: []const u21) ![]AllKeysFile.Element {
    var all_elements = std.ArrayList(AllKeysFile.Element).init(self.arena.allocator());

    var code_points = normalized;
    var code_points_len = code_points.len;
    var cp_index: usize = 0;

    while (cp_index < code_points_len) {
        var lookup = self.table.find(code_points[cp_index..]);
        const S = code_points[0 .. cp_index + lookup.index + 1];
        var elements = lookup.value; // elements for S.

        // handle non-starters
        var last_class: ?u8 = null;
        const tail_start = cp_index + lookup.index + 1;
        var tail_index: usize = tail_start;

        // Advance to last combining C.
        while (tail_index < code_points_len) : (tail_index += 1) {
            const combining_class = ccc_map.combiningClass(code_points[tail_index]);
            if (combining_class == 0) {
                if (tail_index != tail_start) tail_index -= 1;
                break;
            }
            if (last_class) |last| {
                if (last >= combining_class) {
                    if (tail_index != tail_start) tail_index -= 1;
                    break;
                }
            }
            last_class = combining_class;
        }

        if (tail_index == code_points_len) tail_index -= 1;

        if (tail_index > tail_start) {
            const C = code_points[tail_index];
            var new_key = try self.arena.allocator().alloc(u21, S.len + 1);
            mem.copy(u21, new_key, S);
            new_key[new_key.len - 1] = C;
            var new_lookup = self.table.find(new_key);

            if (new_lookup.index == (new_key.len - 1) and new_lookup.value != null) {
                cp_index = tail_start;
                // Splice
                var tmp = try self.arena.allocator().alloc(u21, code_points_len - 1);
                mem.copy(u21, tmp, code_points[0..tail_index]);
                if (tail_index + 1 < code_points_len) {
                    mem.copy(u21, tmp[tail_index..], code_points[tail_index + 1 ..]);
                }
                code_points = tmp;
                code_points_len = code_points.len;
                // Add elements to final collection.
                for (new_lookup.value.?.items[0..new_lookup.value.?.len]) |element| {
                    try all_elements.append(element);
                }
                continue;
            }
        }

        if (elements == null) {
            elements = self.implicitWeight(code_points[0]);
        }

        // Add elements to final collection.
        for (elements.?.items[0..elements.?.len]) |element| {
            try all_elements.append(element);
        }

        cp_index += lookup.index + 1;
    }

    return all_elements.toOwnedSlice();
}

fn sortKeyFromCollationElements(self: *Self, collation_elements: []AllKeysFile.Element) ![]const u16 {
    var sort_key = std.ArrayList(u16).init(self.arena.allocator());

    var level: usize = 0;

    while (level < 3) : (level += 1) {
        if (level != 0) try sort_key.append(0); // level separator

        for (collation_elements) |e| {
            switch (level) {
                0 => if (e.l1 != 0) try sort_key.append(e.l1),
                1 => if (e.l2 != 0) try sort_key.append(e.l2),
                2 => if (e.l3 != 0) try sort_key.append(e.l3),
                else => unreachable,
            }
        }
    }

    return sort_key.toOwnedSlice();
}

pub fn sortKey(self: *Self, str: []const u8) ![]const u16 {
    const normalized = try self.normalizer.normalizeToCodePoints(.canon, str);
    const collation_elements = try self.collationElements(normalized);

    return self.sortKeyFromCollationElements(collation_elements);
}

fn implicitWeight(self: Self, cp: u21) AllKeysFile.Elements {
    var base: u21 = 0;
    var aaaa: ?u21 = null;
    var bbbb: u21 = 0;

    if (props.isUnifiedIdeograph(cp) and ((cp >= 0x4E00 and cp <= 0x9FFF) or
        (cp >= 0xF900 and cp <= 0xFAFF)))
    {
        base = 0xFB40;
        aaaa = base + (cp >> 15);
        bbbb = (cp & 0x7FFF) | 0x8000;
    } else if (props.isUnifiedIdeograph(cp) and !((cp >= 0x4E00 and cp <= 0x9FFF) or
        (cp >= 0xF900 and cp <= 0xFAFF)))
    {
        base = 0xFB80;
        aaaa = base + (cp >> 15);
        bbbb = (cp & 0x7FFF) | 0x8000;
    } else {
        for (self.implicits) |weights| {
            if (cp >= weights.start and cp <= weights.end) {
                aaaa = weights.base;
                if (cp >= 0x18D00 and cp <= 0x18D8F) {
                    bbbb = (cp - 17000) | 0x8000;
                } else {
                    bbbb = (cp - weights.start) | 0x8000;
                }
                break;
            }
        }

        if (aaaa == null) {
            base = 0xFBC0;
            aaaa = base + (cp >> 15);
            bbbb = (cp & 0x7FFF) | 0x8000;
        }
    }

    var elements: Elements = undefined;
    elements.len = 2;
    elements.items[0] = .{ .l1 = @truncate(u16, aaaa.?), .l2 = 0x0020, .l3 = 0x0002 };
    elements.items[1] = .{ .l1 = @truncate(u16, bbbb), .l2 = 0x0000, .l3 = 0x0000 };
    return elements;
}

/// `asciiCmp` compares `a` with `b` returing a `math.Order` result.
pub fn asciiCmp(a: []const u8, b: []const u8) math.Order {
    var long_is_a = true;
    var long = a;
    var short = b;

    if (a.len < b.len) {
        long_is_a = false;
        long = b;
        short = a;
    }

    for (short) |_, i| {
        if (short[i] == long[i]) continue;
        return if (long_is_a) math.order(long[i], short[i]) else math.order(short[i], long[i]);
    }

    return math.order(a.len, b.len);
}

test "Collator ASCII compare" {
    try testing.expectEqual(asciiCmp("abc", "def"), .lt);
    try testing.expectEqual(asciiCmp("Abc", "abc"), .lt);
    try testing.expectEqual(asciiCmp("abc", "abcd"), .lt);
    try testing.expectEqual(asciiCmp("abc", "abc"), .eq);
    try testing.expectEqual(asciiCmp("dbc", "abc"), .gt);
    try testing.expectEqual(asciiCmp("adc", "abc"), .gt);
    try testing.expectEqual(asciiCmp("abd", "abc"), .gt);
}

/// `asciiAsc` is a sort function producing ascending binary order of ASCII strings.
pub fn asciiAsc(_: Self, a: []const u8, b: []const u8) bool {
    return asciiCmp(a, b) == .lt;
}

/// `asciiDesc` is a sort function producing descending binary order of ASCII strings.
pub fn asciiDesc(_: Self, a: []const u8, b: []const u8) bool {
    return asciiCmp(a, b) == .gt;
}

/// `Level` refers to the Collation Element's weight level.
pub const Level = enum(u2) {
    primary = 1, // different base letters.
    secondary, // different marks (i.e. accents).
    tertiary, // different letter case.

    /// `incr` returns the next higher level.
    pub fn incr(self: Level) Level {
        return switch (self) {
            .primary => .secondary,
            .secondary => .tertiary,
            .tertiary => .tertiary,
        };
    }
};

/// `keyLevelCmp` compares key `a` with key `b` up to the given level, returning a `math.Order`.
pub fn keyLevelCmp(a: []const u16, b: []const u16, level: Level) math.Order {
    // Compare
    var long_is_a = true;
    var long = a;
    var short = b;
    var current_level: Level = .primary;

    if (a.len < b.len) {
        long_is_a = false;
        long = b;
        short = a;
    }

    return for (short) |_, i| {
        if (short[i] == long[i]) {
            if (short[i] == 0) {
                // New level.
                if (current_level == level) {
                    break .eq;
                }

                current_level = current_level.incr();
            }
            continue;
        }

        if (short[i] == 0) {
            // Short less than long.
            if (long_is_a) {
                break .gt;
            } else {
                break .lt;
            }
        }

        if (long[i] == 0) {
            // long less than short.
            if (long_is_a) {
                break .lt;
            } else {
                break .gt;
            }
        }

        break if (long_is_a) math.order(long[i], short[i]) else math.order(short[i], long[i]);
    } else .eq;
}

test "Collator keyLevelCmp" {
    var allocator = std.testing.allocator;
    var collator = try init(allocator);
    defer collator.deinit();

    var key_a = try collator.sortKey("cab");
    var key_b = try collator.sortKey("Cab");

    try testing.expectEqual(keyLevelCmp(key_a, key_b, .tertiary), .lt);
    try testing.expectEqual(keyLevelCmp(key_a, key_b, .secondary), .eq);
    try testing.expectEqual(keyLevelCmp(key_a, key_b, .primary), .eq);

    key_a = try collator.sortKey("Cab");
    key_b = try collator.sortKey("cáb");

    try testing.expectEqual(keyLevelCmp(key_a, key_b, .tertiary), .lt);
    try testing.expectEqual(keyLevelCmp(key_a, key_b, .secondary), .lt);
    try testing.expectEqual(keyLevelCmp(key_a, key_b, .primary), .eq);

    key_a = try collator.sortKey("cáb");
    key_b = try collator.sortKey("dab");

    try testing.expectEqual(keyLevelCmp(key_a, key_b, .tertiary), .lt);
    try testing.expectEqual(keyLevelCmp(key_a, key_b, .secondary), .lt);
    try testing.expectEqual(keyLevelCmp(key_a, key_b, .primary), .lt);
}

/// `tertiaryAsc` is a sort function producing a full weight matching ascending sort. Since this
/// function cannot return an error as per `sort.sort` requirements, it may cause a crash or undefined
/// behavior under error conditions.
pub fn tertiaryAsc(self: *Self, a: []const u8, b: []const u8) bool {
    return self.orderFn(a, b, .tertiary, .lt) catch unreachable;
}

/// `tertiaryDesc` is a sort function producing a full weight matching descending sort. Since this
/// function cannot return an error as per `sort.sort` requirements, it may cause a crash or undefined
/// behavior under error conditions.
pub fn tertiaryDesc(self: *Self, a: []const u8, b: []const u8) bool {
    return self.orderFn(a, b, .tertiary, .gt) catch unreachable;
}

/// `orderFn` can be used to match, compare, and sort strings at various collation element levels and orderings.
pub fn orderFn(self: *Self, a: []const u8, b: []const u8, level: Level, order: math.Order) !bool {
    var key_a = try self.sortKey(a);
    var key_b = try self.sortKey(b);

    return keyLevelCmp(key_a, key_b, level) == order;
}

/// `sortAsc` orders the strings in `strings` in ascending full tertiary level order.
pub fn sortAsc(self: *Self, strings: [][]const u8) void {
    zort([]const u8, strings, self, tertiaryAsc);
}

/// `sortDesc` orders the strings in `strings` in ascending full tertiary level order.
pub fn sortDesc(self: *Self, strings: [][]const u8) void {
    zort([]const u8, strings, self, tertiaryDesc);
}

/// `sortAsciiAsc` orders the strings in `strings` in ASCII ascending order.
pub fn sortAsciiAsc(self: Self, strings: [][]const u8) void {
    zort([]const u8, strings, self, asciiAsc);
}

/// `sortAsciiDesc` orders the strings in `strings` in ASCII ascending order.
pub fn sortAsciiDesc(self: Self, strings: [][]const u8) void {
    zort([]const u8, strings, self, asciiDesc);
}

test "Collator sort" {
    var allocator = std.testing.allocator;
    var collator = try init(allocator);
    defer collator.deinit();

    try testing.expect(collator.tertiaryAsc("abc", "def"));
    try testing.expect(collator.tertiaryDesc("def", "abc"));
    try testing.expect(collator.asciiAsc("abc", "def"));
    try testing.expect(collator.asciiDesc("def", "abc"));
    try testing.expect(try collator.orderFn("José", "jose", .primary, .eq));

    var strings: [3][]const u8 = .{ "xyz", "def", "abc" };
    collator.sortAsc(&strings);
    try testing.expectEqual(strings[0], "abc");
    try testing.expectEqual(strings[1], "def");
    try testing.expectEqual(strings[2], "xyz");
    collator.sortDesc(&strings);
    try testing.expectEqual(strings[0], "xyz");
    try testing.expectEqual(strings[1], "def");
    try testing.expectEqual(strings[2], "abc");

    strings = .{ "xyz", "def", "abc" };
    collator.sortAsciiAsc(&strings);
    try testing.expectEqual(strings[0], "abc");
    try testing.expectEqual(strings[1], "def");
    try testing.expectEqual(strings[2], "xyz");
    collator.sortAsciiDesc(&strings);
    try testing.expectEqual(strings[0], "xyz");
    try testing.expectEqual(strings[1], "def");
    try testing.expectEqual(strings[2], "abc");
}

test "Collator UCA" {
    var path_buf: [1024]u8 = undefined;
    var path = try std.fs.cwd().realpath(".", &path_buf);
    // Check if testing in this library path.
    if (!mem.endsWith(u8, path, "ziglyph")) return;

    const uca_tests = "src/data/uca/CollationTest_NON_IGNORABLE_SHORT.txt";
    var file = try std.fs.cwd().openFile(uca_tests, .{});
    defer file.close();
    var buf_reader = std.io.bufferedReader(file.reader()).reader();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var allocator = arena.allocator();
    var buf: [1024]u8 = undefined;

    // Skip header.
    var line_no: usize = 1;
    while (try buf_reader.readUntilDelimiterOrEof(&buf, '\n')) |line| : (line_no += 1) {
        if (line.len == 0) {
            line_no += 1;
            break;
        }
    }

    var prev_key: []const u16 = &[_]u16{};

    var collator = try init(allocator);
    defer collator.deinit();
    var cp_buf: [4]u8 = undefined;

    lines: while (try buf_reader.readUntilDelimiterOrEof(&buf, '\n')) |line| : (line_no += 1) {
        if (line.len == 0 or line[0] == '#') continue;

        //std.debug.print("line {d}: {s}\n", .{ line_no, line });
        var bytes = std.ArrayList(u8).init(allocator);

        var cp_strs = mem.split(u8, line, " ");

        while (cp_strs.next()) |cp_str| {
            const cp = try fmt.parseInt(u21, cp_str, 16);
            const len = unicode.utf8Encode(cp, &cp_buf) catch continue :lines;
            try bytes.appendSlice(cp_buf[0..len]);
        }

        const current_key = try collator.sortKey(bytes.items);

        if (prev_key.len == 0) {
            prev_key = current_key;
            continue;
        }

        try testing.expect((keyLevelCmp(prev_key, current_key, .tertiary) == .eq) or
            (keyLevelCmp(prev_key, current_key, .tertiary) == .lt));

        prev_key = current_key;
    }
}
