const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

const ascii = @import("../ascii.zig");
const CaseFoldMap = @import("../components.zig").CaseFoldMap;
const DecomposeMap = @import("../components.zig").DecomposeMap;
const Letter = @import("../ziglyph.zig").Letter;

pub const CodePointIterator = @import("CodePointIterator.zig");
pub const GraphemeIterator = @import("GraphemeIterator.zig");
pub const Grapheme = GraphemeIterator.Grapheme;
pub const Width = @import("../components/aggregate/Width.zig");

const Self = @This();

allocator: *mem.Allocator,
ascii_only: bool,
bytes: []const u8,
code_points: ?[]u21,
cp_count: usize,
decomp_map: DecomposeMap,
grapheme_clusters: ?[]Grapheme,
letter: Letter,
owned: bool,
widths: Width,

/// init returns a new Zigstr from the byte slice `str`, which is owned elsewhere. It will *not* be 
/// freed on `deinit`.
pub fn init(allocator: *mem.Allocator, str: []const u8) !Self {
    return initWith(allocator, str, false);
}

/// initOwned returns a new Zigstr from the owned byte slice `str`. It will be freed on `deinit`.
pub fn initOwned(allocator: *mem.Allocator, str: []const u8) !Self {
    return initWith(allocator, str, true);
}

/// initWith creates a new Zigstr instance. `owned` determines if the bytes need to be freed on `deinit`.
fn initWith(allocator: *mem.Allocator, str: []const u8, owned: bool) !Self {
    var zstr = Self{
        .allocator = allocator,
        .ascii_only = false,
        .bytes = str,
        .code_points = null,
        .cp_count = 0,
        .decomp_map = DecomposeMap.new(),
        .grapheme_clusters = null,
        .letter = Letter.new(),
        .owned = owned,
        .widths = Width.new(),
    };

    try zstr.processCodePoints();

    return zstr;
}

pub fn deinit(self: *Self) void {
    if (self.owned) self.allocator.free(self.bytes);
    if (self.code_points) |code_points| self.allocator.free(code_points);
    if (self.grapheme_clusters) |gcs| self.allocator.free(gcs);
}

fn resetState(self: *Self) void {
    // Free and reset old content.
    if (self.code_points) |code_points| {
        self.allocator.free(code_points);
        self.code_points = null;
    }

    self.cp_count = 0;

    if (self.grapheme_clusters) |gcs| {
        self.allocator.free(gcs);
        self.grapheme_clusters = null;
    }
}

/// reset reinitializes this Zigstr from the byte slice `str`, which is owned elsewhere. It will *not* be 
/// freed on `deinit`.
pub fn reset(self: *Self, str: []const u8) !void {
    return self.resetWith(str, false);
}

/// resetOwned returns a new Zigstr from the owned byte slice `str`. It will be freed on `deinit`.
pub fn resetOwned(self: *Self, str: []const u8) !void {
    return self.resetWith(str, true);
}

/// resetWith resets this Zigstr with `str` as its new content, which will be freed on `deinit` if `owned`.
fn resetWith(self: *Self, str: []const u8, owned: bool) !void {
    self.resetState();

    if (!self.owned and !owned) {
        // No need to free or copy bytes.
        self.bytes = str;
        try self.processCodePoints();
    }

    if (self.owned and !owned) {
        // Free old, no need to free new.
        self.allocator.free(self.bytes);
        self.owned = false;
        self.bytes = str;
        try self.processCodePoints();
    }

    if (self.owned and owned) {
        // Need to free both.
        self.allocator.free(self.bytes);
        self.bytes = str;
        try self.processCodePoints();
    }

    if (!self.owned and owned) {
        // Only new must be freed.
        self.owned = true;
        self.bytes = str;
        try self.processCodePoints();
    }
}

/// byteCount returns the number of bytes, which can be different from the number of code points and the 
/// number of graphemes.
pub fn byteCount(self: Self) usize {
    return self.bytes.len;
}

/// codePointIter returns a code point iterator based on the bytes of this Zigstr.
pub fn codePointIter(self: Self) !CodePointIterator {
    return CodePointIterator.init(self.bytes);
}

/// codePoints returns the code points that make up this Zigstr.
pub fn codePoints(self: *Self) ![]u21 {
    // Check for cached code points.
    if (self.code_points) |code_points| return code_points;

    // Cache miss, generate.
    var cp_iter = try self.codePointIter();
    var code_points = std.ArrayList(u21).init(self.allocator);
    defer code_points.deinit();

    while (cp_iter.next()) |cp| {
        try code_points.append(cp);
    }

    // Cache.
    self.code_points = code_points.toOwnedSlice();

    return self.code_points.?;
}

/// codePointCount returns the number of code points, which can be different from the number of bytes
/// and the number of graphemes.
pub fn codePointCount(self: *Self) usize {
    return self.cp_count;
}

/// graphemeIter returns a grapheme cluster iterator based on the bytes of this Zigstr. Each grapheme
/// can be composed of multiple code points, so the next method returns a slice of bytes.
pub fn graphemeIter(self: *Self) !GraphemeIterator {
    return GraphemeIterator.new(self.bytes);
}

/// graphemes returns the grapheme clusters that make up this Zigstr.
pub fn graphemes(self: *Self) ![]Grapheme {
    // Check for cached code points.
    if (self.grapheme_clusters) |gcs| return gcs;

    // Cache miss, generate.
    var giter = try self.graphemeIter();
    var gcs = std.ArrayList(Grapheme).init(self.allocator);
    defer gcs.deinit();

    while (giter.next()) |gc| {
        try gcs.append(gc);
    }

    // Cache.
    self.grapheme_clusters = gcs.toOwnedSlice();

    return self.grapheme_clusters.?;
}

/// graphemeCount returns the number of grapheme clusters, which can be different from the number of bytes
/// and the number of code points.
pub fn graphemeCount(self: *Self) !usize {
    if (self.grapheme_clusters) |gcs| {
        return gcs.len;
    } else {
        return (try self.graphemes()).len;
    }
}

/// copy a Zigstr to a new Zigstr. Don't forget to to `deinit` the returned Zigstr!
pub fn copy(self: Self) !Self {
    var bytes = try self.allocator.alloc(u8, self.bytes.len);
    mem.copy(u8, bytes, self.bytes);
    return initWith(self.allocator, bytes, true);
}

/// sameAs convenience method to test exact byte equality of two Zigstrs.
pub fn sameAs(self: Self, other: Self) bool {
    return self.eql(other.bytes);
}

pub const CmpMode = enum {
    ignore_case,
    normalize,
    norm_ignore,
};

/// eql compares for exact byte per byte equality with `other`.
pub fn eql(self: Self, other: []const u8) bool {
    return mem.eql(u8, self.bytes, other);
}

/// eqlBy compares for equality with `other` according to the specified comparison mode.
pub fn eqlBy(self: *Self, other: []const u8, mode: CmpMode) !bool {
    // Check for ASCII only comparison.
    var ascii_only = self.ascii_only;

    if (ascii_only) {
        ascii_only = try isAsciiStr(other);
    }

    // If ASCII only, different lengths mean inequality.
    const len_a = self.bytes.len;
    const len_b = other.len;
    var len_eql = len_a == len_b;

    if (ascii_only and !len_eql) return false;

    if (mode == .ignore_case and len_eql) {
        if (ascii_only) {
            // ASCII case insensitive.
            for (self.bytes) |c, i| {
                const oc = other[i];
                const lc = if (c >= 'A' and c <= 'Z') c ^ 32 else c;
                const olc = if (oc >= 'A' and oc <= 'Z') oc ^ 32 else oc;
                if (lc != olc) return false;
            }
            return true;
        }

        // Non-ASCII case insensitive.
        return self.eqlIgnoreCase(other);
    }

    if (mode == .normalize) return self.eqlNorm(other);
    if (mode == .norm_ignore) return self.eqlNormIgnore(other);

    return false;
}

fn eqlIgnoreCase(self: *Self, other: []const u8) !bool {
    const cf_a = try self.letter.fold_map.caseFoldStr(self.allocator, self.bytes);
    defer self.allocator.free(cf_a);
    const cf_b = try self.letter.fold_map.caseFoldStr(self.allocator, other);
    defer self.allocator.free(cf_b);

    return mem.eql(u8, cf_a, cf_b);
}

fn eqlNorm(self: *Self, other: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    const norm_a = try self.decomp_map.normalizeTo(&arena.allocator, .D, self.bytes);
    const norm_b = try self.decomp_map.normalizeTo(&arena.allocator, .D, other);

    return mem.eql(u8, norm_a, norm_b);
}

fn eqlNormIgnore(self: *Self, other: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    // The long winding road of normalized caseless matching...
    // NFD(CaseFold(NFD(str)))
    var norm_a = try self.decomp_map.normalizeTo(&arena.allocator, .D, self.bytes);
    var cf_a = try self.letter.fold_map.caseFoldStr(&arena.allocator, norm_a);
    norm_a = try self.decomp_map.normalizeTo(&arena.allocator, .D, cf_a);
    var norm_b = try self.decomp_map.normalizeTo(&arena.allocator, .D, other);
    var cf_b = try self.letter.fold_map.caseFoldStr(&arena.allocator, norm_b);
    norm_b = try self.decomp_map.normalizeTo(&arena.allocator, .D, cf_b);

    return mem.eql(u8, norm_a, norm_b);
}

/// isAsciiStr checks if a string (`[]const uu`) is composed solely of ASCII characters.
pub fn isAsciiStr(str: []const u8) !bool {
    // Shamelessly stolen from std.unicode.
    const N = @sizeOf(usize);
    const MASK = 0x80 * (std.math.maxInt(usize) / 0xff);

    var i: usize = 0;
    while (i < str.len) {
        // Fast path for ASCII sequences
        while (i + N <= str.len) : (i += N) {
            const v = mem.readIntNative(usize, str[i..][0..N]);
            if (v & MASK != 0) {
                return false;
            }
        }

        if (i < str.len) {
            const n = try unicode.utf8ByteSequenceLength(str[i]);
            if (i + n > str.len) return error.TruncatedInput;

            switch (n) {
                1 => {}, // ASCII
                else => return false,
            }

            i += n;
        }
    }

    return true;
}

/// trimLeft removes `str` from the left of this Zigstr, mutating it.
pub fn trimLeft(self: *Self, str: []const u8) !void {
    const trimmed = mem.trimLeft(u8, self.bytes, str);

    if (self.owned) {
        var bytes = try self.allocator.alloc(u8, trimmed.len);
        mem.copy(u8, bytes, trimmed);
        try self.resetWith(trimmed, true);
    } else {
        try self.resetWith(trimmed, false);
    }
}

/// trimRight removes `str` from the right of this Zigstr, mutating it.
pub fn trimRight(self: *Self, str: []const u8) !void {
    const trimmed = mem.trimRight(u8, self.bytes, str);

    if (self.owned) {
        var bytes = try self.allocator.alloc(u8, trimmed.len);
        mem.copy(u8, bytes, trimmed);
        try self.resetWith(trimmed, true);
    } else {
        try self.resetWith(trimmed, false);
    }
}

/// trim removes `str` from both the left and right of this Zigstr, mutating it.
pub fn trim(self: *Self, str: []const u8) !void {
    const trimmed = mem.trim(u8, self.bytes, str);

    if (self.owned) {
        var bytes = try self.allocator.alloc(u8, trimmed.len);
        mem.copy(u8, bytes, trimmed);
        try self.resetWith(trimmed, true);
    } else {
        try self.resetWith(trimmed, false);
    }
}

/// indexOf returns the index of `needle` in this Zigstr or null if not found.
pub fn indexOf(self: Self, needle: []const u8) ?usize {
    return mem.indexOf(u8, self.bytes, needle);
}

/// containes ceonvenience method to check if `str` is a substring of this Zigstr.
pub fn contains(self: Self, str: []const u8) bool {
    return self.indexOf(str) != null;
}

/// lastIndexOf returns the index of `needle` in this Zigstr starting from the end, or null if not found.
pub fn lastIndexOf(self: Self, needle: []const u8) ?usize {
    return mem.lastIndexOf(u8, self.bytes, needle);
}

/// count returns the number of `needle`s in this Zigstr.
pub fn count(self: Self, needle: []const u8) usize {
    return mem.count(u8, self.bytes, needle);
}

/// tokenIter returns an iterator on tokens resulting from splitting this Zigstr at every `delim`.
/// Semantics are that of `std.mem.tokenize`.
pub fn tokenIter(self: Self, delim: []const u8) mem.TokenIterator {
    return mem.tokenize(self.bytes, delim);
}

/// tokenize returns a slice of tokens resulting from splitting this Zigstr at every `delim`.
pub fn tokenize(self: Self, delim: []const u8) ![][]const u8 {
    var ts = std.ArrayList([]const u8).init(self.allocator);
    defer ts.deinit();

    var iter = self.tokenIter(delim);
    while (iter.next()) |t| {
        try ts.append(t);
    }

    return ts.toOwnedSlice();
}

/// splitIter returns an iterator on substrings resulting from splitting this Zigstr at every `delim`.
/// Semantics are that of `std.mem.split`.
pub fn splitIter(self: Self, delim: []const u8) mem.SplitIterator {
    return mem.split(self.bytes, delim);
}

/// split returns a slice of substrings resulting from splitting this Zigstr at every `delim`.
pub fn split(self: Self, delim: []const u8) ![][]const u8 {
    var ss = std.ArrayList([]const u8).init(self.allocator);
    defer ss.deinit();

    var iter = self.splitIter(delim);
    while (iter.next()) |s| {
        try ss.append(s);
    }

    return ss.toOwnedSlice();
}

/// startsWith returns true if this Zigstr starts with `str`.
pub fn startsWith(self: Self, str: []const u8) bool {
    return mem.startsWith(u8, self.bytes, str);
}

/// endsWith returns true if this Zigstr ends with `str`.
pub fn endsWith(self: Self, str: []const u8) bool {
    return mem.endsWith(u8, self.bytes, str);
}

/// Refer to the docs for `std.mem.join`.
pub const join = mem.join;

/// concatAll appends each string in `others` to this Zigstr, mutating it.
pub fn concatAll(self: *Self, others: [][]const u8) !void {
    if (others.len == 0) return;

    const total_len = blk: {
        var sum: usize = 0;
        for (others) |slice| {
            sum += slice.len;
        }
        sum += self.bytes.len;
        break :blk sum;
    };

    const buf = try self.allocator.alloc(u8, total_len);
    mem.copy(u8, buf, self.bytes);

    var buf_index: usize = self.bytes.len;
    for (others) |slice| {
        mem.copy(u8, buf[buf_index..], slice);
        buf_index += slice.len;
    }

    // No need for shrink since buf is exactly the correct size.
    try self.resetWith(buf, true);
}

/// concat appends `other` to this Zigstr, mutating it.
pub fn concat(self: *Self, other: []const u8) !void {
    try self.concatAll(&[1][]const u8{other});
}

/// replace all occurrences of `needle` with `replacement`, mutating this Zigstr. Returns the total
/// replacements made.
pub fn replace(self: *Self, needle: []const u8, replacement: []const u8) !usize {
    const len = mem.replacementSize(u8, self.bytes, needle, replacement);
    var buf = try self.allocator.alloc(u8, len);
    const replacements = mem.replace(u8, self.bytes, needle, replacement, buf);
    if (replacement.len == 0) buf = self.allocator.shrink(buf, (len + 1) - needle.len * replacements);
    try self.resetWith(buf, true);

    return replacements;
}

/// append adds `cp` to the end of this Zigstr, mutating it.
pub fn append(self: *Self, cp: u21) !void {
    var buf: [4]u8 = undefined;
    const len = try unicode.utf8Encode(cp, &buf);
    try self.concat(buf[0..len]);
}

/// append adds `cp` to the end of this Zigstr, mutating it.
pub fn appendAll(self: *Self, cp_list: []const u21) !void {
    var cp_bytes = std.ArrayList(u8).init(self.allocator);
    defer cp_bytes.deinit();

    var buf: [4]u8 = undefined;
    for (cp_list) |cp| {
        const len = try unicode.utf8Encode(cp, &buf);
        try cp_bytes.appendSlice(buf[0..len]);
    }

    try self.concat(cp_bytes.items);
}

/// empty returns true if this Zigstr has no bytes.
pub fn empty(self: Self) bool {
    return self.bytes.len == 0;
}

/// chomp will remove trailing \n or \r\n from this Zigstr, mutating it.
pub fn chomp(self: *Self) !void {
    if (self.empty()) return;

    const len = self.bytes.len;
    const last = self.bytes[len - 1];
    if (last == '\r' or last == '\n') {
        // CR
        var chomp_size: usize = 1;
        if (len > 1 and last == '\n' and self.bytes[len - 2] == '\r') chomp_size = 2; // CR+LF
        if (self.owned) {
            var bytes = try self.allocator.alloc(u8, len - chomp_size);
            mem.copy(u8, bytes, self.bytes[0 .. len - chomp_size]);
            try self.resetWith(bytes, true);
        } else {
            try self.resetWith(self.bytes[0 .. len - chomp_size], false);
        }
    }
}

/// byteAt returns the byte at index `i`.
pub fn byteAt(self: Self, i: usize) !u8 {
    if (i >= self.bytes.len) return error.IndexOutOfBounds;
    return self.bytes[i];
}

/// codePointAt returns the `i`th code point.
pub fn codePointAt(self: *Self, i: usize) !u21 {
    if (i >= self.cp_count) return error.IndexOutOfBounds;
    return (try self.codePoints())[i];
}

/// graphemeAt returns the `i`th grapheme cluster.
pub fn graphemeAt(self: *Self, i: usize) !Grapheme {
    const gcs = try self.graphemes();
    if (i >= gcs.len) return error.IndexOutOfBounds;
    return gcs[i];
}

/// byteSlice returnes the bytes from this Zigstr in the specified range from `start` to `end` - 1.
pub fn byteSlice(self: Self, start: usize, end: usize) ![]const u8 {
    if (start >= self.bytes.len or end > self.bytes.len) return error.IndexOutOfBounds;
    return self.bytes[start..end];
}

/// codePointSlice returnes the code points from this Zigstr in the specified range from `start` to `end` - 1.
pub fn codePointSlice(self: *Self, start: usize, end: usize) ![]const u21 {
    if (start >= self.cp_count or end > self.cp_count) return error.IndexOutOfBounds;
    return (try self.codePoints())[start..end];
}

/// graphemeSlice returnes the grapheme clusters from this Zigstr in the specified range from `start` to `end` - 1.
pub fn graphemeSlice(self: *Self, start: usize, end: usize) ![]Grapheme {
    const gcs = try self.graphemes();
    if (start >= gcs.len or end > gcs.len) return error.IndexOutOfBounds;
    return gcs[start..end];
}

/// substr returns a byte slice representing the grapheme range starting at `start` grapheme index
/// up to `end` grapheme index - 1.
pub fn substr(self: *Self, start: usize, end: usize) ![]const u8 {
    if (self.ascii_only) {
        if (start >= self.bytes.len or end > self.bytes.len) return error.IndexOutOfBounds;
        return self.bytes[start..end];
    }

    const gcs = try self.graphemes();
    if (start >= gcs.len or end > gcs.len) return error.IndexOutOfBounds;
    return self.bytes[gcs[start].offset..gcs[end].offset];
}

/// processCodePoints performs some house-keeping and accounting on the code points that make up this
/// Zigstr.  Asserts that our bytes are valid UTF-8.
pub fn processCodePoints(self: *Self) !void {
    // Shamelessly stolen from std.unicode.
    var ascii_only = true;
    var len: usize = 0;

    const N = @sizeOf(usize);
    const MASK = 0x80 * (std.math.maxInt(usize) / 0xff);

    var i: usize = 0;
    while (i < self.bytes.len) {
        // Fast path for ASCII sequences
        while (i + N <= self.bytes.len) : (i += N) {
            const v = mem.readIntNative(usize, self.bytes[i..][0..N]);
            if (v & MASK != 0) {
                ascii_only = false;
                break;
            }
            len += N;
        }

        if (i < self.bytes.len) {
            const n = try unicode.utf8ByteSequenceLength(self.bytes[i]);
            if (i + n > self.bytes.len) return error.TruncatedInput;

            switch (n) {
                1 => {}, // ASCII, no validation needed
                else => {
                    _ = try unicode.utf8Decode(self.bytes[i .. i + n]);
                    ascii_only = false;
                },
            }

            i += n;
            len += 1;
        }
    }

    self.ascii_only = ascii_only;
    self.cp_count = len;
}

/// isLower detects if all the code points in this Zigstr are lowercase.
pub fn isLower(self: *Self) !bool {
    for (try self.codePoints()) |cp| {
        if (!self.letter.isLower(cp)) return false;
    }

    return true;
}

/// toLower converts this Zigstr to lowercase, mutating it.
pub fn toLower(self: *Self) !void {
    var bytes = std.ArrayList(u8).init(self.allocator);
    defer bytes.deinit();

    var buf: [4]u8 = undefined;
    for (try self.codePoints()) |cp| {
        const lcp = self.letter.toLower(cp);
        const len = try unicode.utf8Encode(lcp, &buf);
        try bytes.appendSlice(buf[0..len]);
    }

    try self.resetWith(bytes.toOwnedSlice(), true);
}

/// isUpper detects if all the code points in this Zigstr are uppercase.
pub fn isUpper(self: *Self) !bool {
    for (try self.codePoints()) |cp| {
        if (!self.letter.isUpper(cp)) return false;
    }

    return true;
}

/// toUpper converts this Zigstr to uppercase, mutating it.
pub fn toUpper(self: *Self) !void {
    var bytes = std.ArrayList(u8).init(self.allocator);
    defer bytes.deinit();

    var buf: [4]u8 = undefined;
    for (try self.codePoints()) |cp| {
        const lcp = self.letter.toUpper(cp);
        const len = try unicode.utf8Encode(lcp, &buf);
        try bytes.appendSlice(buf[0..len]);
    }

    try self.resetWith(bytes.toOwnedSlice(), true);
}

/// format implements the `std.fmt` format interface for printing types.
pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = try writer.print("{s}", .{self.bytes});
}

/// width returns the cells (or columns) this Zigstr would occupy in a fixed-width context.
pub fn width(self: *Self) !usize {
    return self.widths.strWidth(self.bytes, .half);
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "Zigstr code points" {
    var str = try initWith(std.testing.allocator, "Héllo", false);
    defer str.deinit();

    var cp_iter = try str.codePointIter();
    var want = [_]u21{ 'H', 0x00E9, 'l', 'l', 'o' };
    var i: usize = 0;
    while (cp_iter.next()) |cp| : (i += 1) {
        expectEqual(want[i], cp);
    }

    expectEqual(@as(usize, 5), str.codePointCount());
    expectEqualSlices(u21, &want, try str.codePoints());
    expectEqual(@as(usize, 6), str.byteCount());
    expectEqual(@as(usize, 5), str.codePointCount());
}

test "Zigstr graphemes" {
    var str = try initWith(std.testing.allocator, "Héllo", false);
    defer str.deinit();

    var giter = try str.graphemeIter();
    var want = [_][]const u8{ "H", "é", "l", "l", "o" };
    var i: usize = 0;
    while (giter.next()) |gc| : (i += 1) {
        expect(gc.eql(want[i]));
    }

    expectEqual(@as(usize, 5), try str.graphemeCount());
    const gcs = try str.graphemes();
    for (gcs) |gc, j| {
        expect(gc.eql(want[j]));
    }

    expectEqual(@as(usize, 6), str.byteCount());
    expectEqual(@as(usize, 5), try str.graphemeCount());
}

test "Zigstr copy" {
    var str1 = try initWith(std.testing.allocator, "Zig", false);
    defer str1.deinit();

    var str2 = try str1.copy();
    defer str2.deinit();

    expect(str1.eql(str2.bytes));
    expect(str2.eql("Zig"));
    expect(str1.sameAs(str2));
}

test "Zigstr eql" {
    var str = try initWith(std.testing.allocator, "foo", false);
    defer str.deinit();

    expect(str.eql("foo")); // exact
    expect(!str.eql("fooo")); // lengths
    expect(!str.eql("foó")); // combining
    expect(!str.eql("Foo")); // letter case
    expect(try str.eqlBy("Foo", .ignore_case));

    try str.resetWith("foé", false);
    expect(try str.eqlBy("foe\u{0301}", .normalize));

    try str.resetWith("foϓ", false);
    expect(try str.eqlBy("fo\u{03D2}\u{0301}", .normalize));

    try str.resetWith("Foϓ", false);
    expect(try str.eqlBy("fo\u{03D2}\u{0301}", .norm_ignore));

    try str.resetWith("FOÉ", false);
    expect(try str.eqlBy("foe\u{0301}", .norm_ignore)); // foÉ == foé
}

test "Zigstr isAsciiStr" {
    expect(try isAsciiStr("Hello!"));
    expect(!try isAsciiStr("Héllo!"));
}

test "Zigstr trimLeft" {
    var str = try initWith(std.testing.allocator, "    Hello", false);
    defer str.deinit();

    try str.trimLeft(" ");
    expect(str.eql("Hello"));
}

test "Zigstr trimRight" {
    var str = try initWith(std.testing.allocator, "Hello    ", false);
    defer str.deinit();

    try str.trimRight(" ");
    expect(str.eql("Hello"));
}

test "Zigstr trim" {
    var str = try initWith(std.testing.allocator, "   Hello   ", false);
    defer str.deinit();

    try str.trim(" ");
    expect(str.eql("Hello"));
}

test "Zigstr indexOf" {
    var str = try initWith(std.testing.allocator, "Hello", false);
    defer str.deinit();

    expectEqual(str.indexOf("l"), 2);
    expectEqual(str.indexOf("z"), null);
    expect(str.contains("l"));
    expect(!str.contains("z"));
}

test "Zigstr lastIndexOf" {
    var str = try initWith(std.testing.allocator, "Hello", false);
    defer str.deinit();

    expectEqual(str.lastIndexOf("l"), 3);
    expectEqual(str.lastIndexOf("z"), null);
}

test "Zigstr count" {
    var str = try initWith(std.testing.allocator, "Hello", false);
    defer str.deinit();

    expectEqual(str.count("l"), 2);
    expectEqual(str.count("ll"), 1);
    expectEqual(str.count("z"), 0);
}

test "Zigstr tokenize" {
    var allocator = std.testing.allocator;
    var str = try initWith(allocator, " Hello World ", false);
    defer str.deinit();

    var iter = str.tokenIter(" ");
    expectEqualStrings("Hello", iter.next().?);
    expectEqualStrings("World", iter.next().?);
    expect(iter.next() == null);

    var ts = try str.tokenize(" ");
    defer allocator.free(ts);
    expectEqual(@as(usize, 2), ts.len);
    expectEqualStrings("Hello", ts[0]);
    expectEqualStrings("World", ts[1]);
}

test "Zigstr split" {
    var allocator = std.testing.allocator;
    var str = try initWith(allocator, " Hello World ", false);
    defer str.deinit();

    var iter = str.splitIter(" ");
    expectEqualStrings("", iter.next().?);
    expectEqualStrings("Hello", iter.next().?);
    expectEqualStrings("World", iter.next().?);
    expectEqualStrings("", iter.next().?);
    expect(iter.next() == null);

    var ss = try str.split(" ");
    defer allocator.free(ss);
    expectEqual(@as(usize, 4), ss.len);
    expectEqualStrings("", ss[0]);
    expectEqualStrings("Hello", ss[1]);
    expectEqualStrings("World", ss[2]);
    expectEqualStrings("", ss[3]);
}

test "Zigstr startsWith" {
    var str = try initWith(std.testing.allocator, "Hello World", false);
    defer str.deinit();

    expect(str.startsWith("Hell"));
    expect(!str.startsWith("Zig"));
}

test "Zigstr endsWith" {
    var str = try initWith(std.testing.allocator, "Hello World", false);
    defer str.deinit();

    expect(str.endsWith("World"));
    expect(!str.endsWith("Zig"));
}

test "Zigstr join" {
    var allocator = std.testing.allocator;
    const result = try join(allocator, "/", &[_][]const u8{ "this", "is", "a", "path" });
    defer allocator.free(result);
    expectEqualSlices(u8, "this/is/a/path", result);
}

test "Zigstr concat" {
    var str = try initWith(std.testing.allocator, "Hello", false);
    defer str.deinit();

    try str.concat(" World");
    expectEqualStrings("Hello World", str.bytes);
    var others = [_][]const u8{ " is", " the", " tradition!" };
    try str.concatAll(&others);
    expectEqualStrings("Hello World is the tradition!", str.bytes);
}

test "Zigstr replace" {
    var str = try initWith(std.testing.allocator, "Hello", false);
    defer str.deinit();

    var replacements = try str.replace("l", "z");
    expectEqual(@as(usize, 2), replacements);
    expect(str.eql("Hezzo"));

    replacements = try str.replace("z", "");
    expectEqual(@as(usize, 2), replacements);
    expect(str.eql("Heo"));
}

test "Zigstr append" {
    var str = try initWith(std.testing.allocator, "Hell", false);
    defer str.deinit();

    try str.append('o');
    expectEqual(@as(usize, 5), str.bytes.len);
    expect(str.eql("Hello"));
    try str.appendAll(&[_]u21{ ' ', 'W', 'o', 'r', 'l', 'd' });
    expectEqual(@as(usize, 11), str.bytes.len);
    expect(str.eql("Hello World"));
}

test "Zigstr chomp" {
    var str = try initWith(std.testing.allocator, "Hello\n", false);
    defer str.deinit();

    try str.chomp();
    expectEqual(@as(usize, 5), str.bytes.len);
    expect(str.eql("Hello"));

    try str.resetWith("Hello\r", false);
    try str.chomp();
    expectEqual(@as(usize, 5), str.bytes.len);
    expect(str.eql("Hello"));

    try str.resetWith("Hello\r\n", false);
    try str.chomp();
    expectEqual(@as(usize, 5), str.bytes.len);
    expect(str.eql("Hello"));
}

test "Zigstr xAt" {
    var str = try initWith(std.testing.allocator, "H\u{0065}\u{0301}llo", false);
    defer str.deinit();

    expectEqual(try str.byteAt(2), 0x00CC);
    expectError(error.IndexOutOfBounds, str.byteAt(7));
    expectEqual(try str.codePointAt(1), 0x0065);
    expectError(error.IndexOutOfBounds, str.codePointAt(6));
    expect((try str.graphemeAt(1)).eql("\u{0065}\u{0301}"));
    expectError(error.IndexOutOfBounds, str.graphemeAt(5));
}

test "Zigstr extractions" {
    var str = try initWith(std.testing.allocator, "H\u{0065}\u{0301}llo", false);
    defer str.deinit();

    // Slices
    expectEqualSlices(u8, try str.byteSlice(1, 4), "\u{0065}\u{0301}");
    expectEqualSlices(u21, try str.codePointSlice(1, 3), &[_]u21{ '\u{0065}', '\u{0301}' });
    const gc1 = try str.graphemeSlice(1, 2);
    expect(gc1[0].eql("\u{0065}\u{0301}"));

    // Substrings
    var str2 = try str.substr(1, 2);
    expectEqualStrings("\u{0065}\u{0301}", str2);
    expectEqualStrings(try str.byteSlice(1, 4), str2);
}

test "Zigstr casing" {
    var str = try initWith(std.testing.allocator, "Héllo! 123", false);
    defer str.deinit();

    expect(!try str.isLower());
    expect(!try str.isUpper());
    try str.toLower();
    expect(try str.isLower());
    expect(str.eql("héllo! 123"));
    try str.toUpper();
    expect(try str.isUpper());
    expect(str.eql("HÉLLO! 123"));
}

test "Zigstr format" {
    var str = try initWith(std.testing.allocator, "Héllo 😊", false);
    defer str.deinit();

    std.debug.print("{}\n", .{str});
}

test "Zigstr width" {
    var str = try initWith(std.testing.allocator, "Héllo 😊", false);
    defer str.deinit();

    expectEqual(@as(usize, 8), try str.width());
}
