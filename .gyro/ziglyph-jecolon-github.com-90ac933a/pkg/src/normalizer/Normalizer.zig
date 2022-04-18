//! `Normalizer` implements Unicode normaliztion for Unicode strings and code points.

const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const sort = std.sort.sort;
const unicode = std.unicode;

const isAsciiStr = @import("../ascii.zig").isAsciiStr;
const canonicals = @import("../ziglyph.zig").canonicals;
const case_fold_map = @import("../ziglyph.zig").case_fold_map;
const ccc_map = @import("../ziglyph.zig").combining_map;
const hangul_map = @import("../ziglyph.zig").hangul_map;
const norm_props = @import("../ziglyph.zig").derived_normalization_props;

pub const DecompFile = @import("DecompFile.zig");
const Decomp = DecompFile.Decomp;

const Trieton = @import("Trieton.zig");
const Lookup = Trieton.Lookup;

allocator: mem.Allocator,
arena: std.heap.ArenaAllocator,
decomp_trie: Trieton,

const Self = @This();

pub fn init(allocator: mem.Allocator) !Self {
    var self = Self{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .decomp_trie = Trieton.init(allocator),
    };

    const decompositions = @embedFile("../data/ucd/Decompositions.bin");
    var reader = std.io.fixedBufferStream(decompositions).reader();
    var file = try DecompFile.decompress(allocator, reader);
    defer file.deinit();
    while (file.next()) |entry| {
        try self.decomp_trie.add(entry.key[0..entry.key_len], entry.value);
    }

    return self;
}

pub fn deinit(self: *Self) void {
    self.decomp_trie.deinit();
    self.arena.deinit();
}

var cp_buf: [4]u8 = undefined;

/// `mapping` retrieves the decomposition mapping for a code point as per the UCD.
pub fn mapping(self: Self, cp: u21, nfd: bool) Decomp {
    const len = unicode.utf8Encode(cp, &cp_buf) catch |err| {
        std.debug.print("Normalizer.mapping: error encoding UTF-8 for 0x{x}; {}\n", .{ cp, err });
        std.os.exit(1);
    };

    const lookup = self.decomp_trie.find(cp_buf[0..len]);

    if (lookup) |l| {
        // Got an entry.
        if (l.index == len - 1) {
            // Full match.
            if (nfd and l.value.form == .compat) {
                return Decomp{ .form = .same, .len = 1, .seq = [_]u21{ cp, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } };
            } else {
                return l.value;
            }
        }
    }

    return Decomp{ .form = .same, .len = 1, .seq = [_]u21{ cp, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } };
}

/// `decompose` takes a code point and returns its decomposition to NFD if `nfd` is true, NFKD otherwise.
pub fn decompose(self: Self, cp: u21, nfd: bool) Decomp {
    var dc = Decomp{};

    if (nfd and norm_props.isNfd(cp)) {
        dc.len = 1;
        dc.seq[0] = cp;
        return dc;
    }

    if (isHangulPrecomposed(cp)) {
        // Hangul precomposed syllable full decomposition.
        const seq = decomposeHangul(cp);
        dc.len = if (seq[2] == 0) 2 else 3;
        mem.copy(u21, &dc.seq, seq[0..dc.len]);
        return dc;
    }

    if (!nfd) dc.form = .compat;
    var result_index: usize = 0;

    var work: [18]u21 = undefined;
    var work_index: usize = 1;
    work[0] = cp;

    while (work_index > 0) {
        work_index -= 1;
        const next = work[work_index];
        const m = self.mapping(next, nfd);

        if (m.form == .same) {
            dc.seq[result_index] = m.seq[0];
            result_index += 1;
            continue;
        }

        var i: usize = m.len - 1;

        while (true) {
            work[work_index] = m.seq[i];
            work_index += 1;
            if (i == 0) break;
            i -= 1;
        }
    }

    dc.len = result_index;

    return dc;
}

fn getCodePoints(self: *Self, str: []const u8) ![]u21 {
    var code_points = std.ArrayList(u21).init(self.arena.allocator());
    var iter = (try unicode.Utf8View.init(str)).iterator();

    while (iter.nextCodepoint()) |cp| {
        try code_points.append(cp);
    }

    return code_points.items;
}

/// `Form` represents the Unicode Normalization Form.
const Form = enum {
    canon, // NFD: Canonical Decomposed.
    compat, // NFKD: Compatibility Decomposed.
    same, // Just the same code point.
    composed, // NFC: Canonical Composed.
    komposed, // NFKC: Compatibility Decomposed.
};

/// `normalizeTo` will normalize the code points in str, producing a slice of u8 with the new bytes
/// corresponding to the specified Normalization Form.
pub fn normalizeTo(self: *Self, form: Form, str: []const u8) anyerror![]u8 {
    const code_points = try self.getCodePoints(str);
    return self.normalizeCodePointsTo(form, code_points);
}

fn normalizeCodePointsTo(self: *Self, form: Form, code_points: []u21) anyerror![]u8 {
    const d_code_points = try self.normalizeCodePointsToCodePoints(form, code_points);
    //var result = try std.ArrayList(u8).initCapacity(&self.arena.allocator, code_points.len * 4);
    var result = std.ArrayList(u8).init(self.arena.allocator());
    var buf: [4]u8 = undefined;

    // Encode as UTF-8 bytes.
    for (d_code_points) |dcp| {
        const len = try unicode.utf8Encode(dcp, &buf);
        //result.appendSliceAssumeCapacity(buf[0..len]);
        try result.appendSlice(buf[0..len]);
    }

    return result.items;
}

/// `normalizeToCodePoints` will normalize the code points in str, producing a new slice of code points
/// corresponding to the specified Normalization Form.
pub fn normalizeToCodePoints(self: *Self, form: Form, str: []const u8) anyerror![]u21 {
    var code_points = try self.getCodePoints(str);
    return self.normalizeCodePointsToCodePoints(form, code_points);
}

/// `normalizeCodePointsToCodePoints` receives code points and returns normalized code points.
pub fn normalizeCodePointsToCodePoints(self: *Self, form: Form, code_points: []u21) anyerror![]u21 {
    if (form == .composed or form == .komposed) return self.composeCodePoints(form, code_points);

    // NFD Quick Check.
    if (form == .canon) {
        const already_nfd = for (code_points) |cp| {
            if (!norm_props.isNfd(cp)) break false;
        } else true;

        if (already_nfd) {
            // Apply canonical sort algorithm.
            canonicalSort(code_points);
            return code_points;
        }
    }

    var d_code_points = std.ArrayList(u21).init(self.arena.allocator());

    // Gather decomposed code points.
    for (code_points) |cp| {
        const dc = self.decompose(cp, form == .canon);
        try d_code_points.appendSlice(dc.seq[0..dc.len]);
    }

    // Apply canonical sort algorithm.
    canonicalSort(d_code_points.items);

    return d_code_points.items;
}

/// `composeCodePoints` returns the composed form of `code_points`.
pub fn composeCodePoints(self: *Self, form: Form, code_points: []u21) anyerror![]u21 {
    var decomposed = if (form == .composed)
        try self.normalizeCodePointsToCodePoints(.canon, code_points)
    else
        try self.normalizeCodePointsToCodePoints(.compat, code_points);

    while (true) {
        var deleted: usize = 0;
        var i: usize = 1; // start at second code point.

        block_check: while (i < decomposed.len) : (i += 1) {
            const C = decomposed[i];
            var starter_index: ?usize = null;
            var j: usize = i;

            while (true) {
                j -= 1;

                if (ccc_map.combiningClass(decomposed[j]) == 0) {
                    if (i - j > 1) {
                        for (decomposed[(j + 1)..i]) |B| {
                            if (isHangul(C)) {
                                if (isCombining(B) or isNonHangulStarter(B)) continue :block_check;
                            }
                            if (ccc_map.combiningClass(B) >= ccc_map.combiningClass(C)) continue :block_check;
                        }
                    }
                    starter_index = j;
                    break;
                }

                if (j == 0) break;
            }

            if (starter_index) |sidx| {
                const L = decomposed[sidx];

                var processed_hangul: bool = false;

                if (isHangul(L) and isHangul(C)) {
                    const l_stype = hangul_map.syllableType(L).?;
                    const c_stype = hangul_map.syllableType(C).?;

                    if (l_stype == .LV and c_stype == .T) {
                        // LV, T
                        decomposed[sidx] = composeHangulCanon(L, C);
                        decomposed[i] = 0xFFFD;
                        processed_hangul = true;
                    }

                    if (l_stype == .L and c_stype == .V) {
                        // Handle L, V. L, V, T is handled via main loop.
                        decomposed[sidx] = composeHangulFull(L, C, 0);
                        decomposed[i] = 0xFFFD;
                        processed_hangul = true;
                    }

                    if (processed_hangul) deleted += 1;
                }

                if (!processed_hangul) {
                    // Not Hangul.
                    if (canonicals.composite(L, C)) |P| {
                        if (!norm_props.isFcx(P)) {
                            decomposed[sidx] = P;
                            decomposed[i] = 0xFFFD; // Mark as deleted.
                            deleted += 1;
                        }
                    }
                }
            }
        }

        if (deleted == 0) return decomposed;

        var composed = try std.ArrayList(u21).initCapacity(self.arena.allocator(), decomposed.len - deleted);

        for (decomposed) |cp| {
            if (cp != 0xFFFD) composed.appendAssumeCapacity(cp);
        }

        decomposed = composed.items;
    }
}

fn cccLess(_: void, lhs: u21, rhs: u21) bool {
    return ccc_map.combiningClass(lhs) < ccc_map.combiningClass(rhs);
}

fn canonicalSort(cp_list: []u21) void {
    var i: usize = 0;
    while (true) {
        if (i >= cp_list.len) break;
        var start: usize = i;
        while (i < cp_list.len and ccc_map.combiningClass(cp_list[i]) != 0) : (i += 1) {}
        sort(u21, cp_list[start..i], {}, cccLess);
        i += 1;
    }
}

// Hangul Syllable constants.
const SBase: u21 = 0xAC00;
const LBase: u21 = 0x1100;
const VBase: u21 = 0x1161;
const TBase: u21 = 0x11A7;
const LCount: u21 = 19;
const VCount: u21 = 21;
const TCount: u21 = 28;
const NCount: u21 = 588; // VCount * TCount
const SCount: u21 = 11172; // LCount * NCount

fn composeHangulCanon(lv: u21, t: u21) u21 {
    std.debug.assert(0x11A8 <= t and t <= 0x11C2);
    return lv + (t - TBase);
}

fn composeHangulFull(l: u21, v: u21, t: u21) u21 {
    std.debug.assert(0x1100 <= l and l <= 0x1112);
    std.debug.assert(0x1161 <= v and v <= 0x1175);
    const LIndex = l - LBase;
    const VIndex = v - VBase;
    const LVIndex = LIndex * NCount + VIndex * TCount;

    if (t == 0) return SBase + LVIndex;

    std.debug.assert(0x11A8 <= t and t <= 0x11C2);
    const TIndex = t - TBase;

    return SBase + LVIndex + TIndex;
}

fn decomposeHangul(cp: u21) [3]u21 {
    const SIndex: u21 = cp - SBase;
    const LIndex: u21 = SIndex / NCount;
    const VIndex: u21 = (SIndex % NCount) / TCount;
    const TIndex: u21 = SIndex % TCount;
    const LPart: u21 = LBase + LIndex;
    const VPart: u21 = VBase + VIndex;
    var TPart: u21 = 0;
    if (TIndex != 0) TPart = TBase + TIndex;

    return [3]u21{ LPart, VPart, TPart };
}

fn isHangulPrecomposed(cp: u21) bool {
    if (hangul_map.syllableType(cp)) |kind| {
        return switch (kind) {
            .LV, .LVT => true,
            else => false,
        };
    } else {
        return false;
    }
}

fn isHangul(cp: u21) bool {
    return hangul_map.syllableType(cp) != null;
}

fn isStarter(cp: u21) bool {
    return ccc_map.combiningClass(cp) == 0;
}

fn isCombining(cp: u21) bool {
    return ccc_map.combiningClass(cp) > 0;
}

fn isNonHangulStarter(cp: u21) bool {
    return !isHangul(cp) and isStarter(cp);
}

/// `CmpMode` determines the type of comparison to be performed.
/// * ident compares Unicode Identifiers for caseless matching.
/// * ignore_case compares ignoring letter case.
/// * normalize compares the result of normalizing to canonical form (NFD).
/// * norm_ignore combines both ignore_case and normalize modes.
pub const CmpMode = enum {
    ident,
    ignore_case,
    normalize,
    norm_ignore,
};

/// `eqlBy` compares for equality between `a` and `b` according to the specified comparison mode.
pub fn eqlBy(self: *Self, a: []const u8, b: []const u8, mode: CmpMode) !bool {
    // Empty string quick check.
    if (a.len == 0 and b.len == 0) return true;
    if (a.len == 0 and b.len != 0) return false;
    if (b.len == 0 and a.len != 0) return false;

    // Check for ASCII only comparison.
    var ascii_only = try isAsciiStr(a);

    if (ascii_only) {
        ascii_only = try isAsciiStr(b);
    }

    // If ASCII only, different lengths mean inequality.
    const len_a = a.len;
    const len_b = b.len;
    var len_eql = len_a == len_b;

    if (ascii_only and !len_eql) return false;

    if ((mode == .ignore_case or mode == .ident) and len_eql) {
        if (ascii_only) {
            // ASCII case insensitive.
            for (a) |c, i| {
                const oc = b[i];
                const lc = if (c >= 'A' and c <= 'Z') c ^ 32 else c;
                const olc = if (oc >= 'A' and oc <= 'Z') oc ^ 32 else oc;
                if (lc != olc) return false;
            }
            return true;
        }

        // Non-ASCII case insensitive.
        return if (mode == .ident) self.eqlIdent(a, b) else self.eqlNormIgnore(a, b);
    }

    return switch (mode) {
        .ident => self.eqlIdent(a, b),
        .normalize => self.eqlNorm(a, b),
        .norm_ignore => self.eqlNormIgnore(a, b),
        else => false,
    };
}

fn eqlIdent(self: *Self, a: []const u8, b: []const u8) !bool {
    const a_cps = try self.getCodePoints(a);
    var a_cf = std.ArrayList(u21).init(self.arena.allocator());

    for (a_cps) |cp| {
        const cf_s = norm_props.toNfkcCaseFold(cp);
        if (cf_s.len == 0) {
            // Same code point. ""
            try a_cf.append(cp);
        } else if (cf_s.len == 1) {
            // Map to nothing. "0"
            continue;
        } else {
            // Got list; parse it. "x,y,z..."
            var fields = mem.split(u8, cf_s, ",");

            while (fields.next()) |field| {
                const parsed_cp = try std.fmt.parseInt(u21, field, 16);
                try a_cf.append(parsed_cp);
            }
        }
    }

    const b_cps = try self.getCodePoints(b);
    var b_cf = std.ArrayList(u21).init(self.arena.allocator());

    for (b_cps) |cp| {
        const cf_s = norm_props.toNfkcCaseFold(cp);
        if (cf_s.len == 0) {
            // Same code point. ""
            try b_cf.append(cp);
        } else if (cf_s.len == 1) {
            // Map to nothing. "0"
            continue;
        } else {
            // Got list; parse it. "x,y,z..."
            var fields = mem.split(u8, cf_s, ",");

            while (fields.next()) |field| {
                const parsed_cp = try std.fmt.parseInt(u21, field, 16);
                try b_cf.append(parsed_cp);
            }
        }
    }

    return mem.eql(u21, a_cf.items, b_cf.items);
}

fn eqlNorm(self: *Self, a: []const u8, b: []const u8) !bool {
    const norm_a = try self.normalizeTo(.canon, a);
    const norm_b = try self.normalizeTo(.canon, b);

    return mem.eql(u8, norm_a, norm_b);
}

fn requiresNfdBeforeCaseFold(cp: u21) bool {
    return switch (cp) {
        0x0345 => true,
        0x1F80...0x1FAF => true,
        0x1FB2...0x1FB4 => true,
        0x1FB7 => true,
        0x1FBC => true,
        0x1FC2...0x1FC4 => true,
        0x1FC7 => true,
        0x1FCC => true,
        0x1FF2...0x1FF4 => true,
        0x1FF7 => true,
        0x1FFC => true,
        else => false,
    };
}

fn requiresPreNfd(code_points: []const u21) bool {
    return for (code_points) |cp| {
        if (requiresNfdBeforeCaseFold(cp)) break true;
    } else false;
}

fn eqlNormIgnore(self: *Self, a: []const u8, b: []const u8) !bool {
    const code_points_a = try self.getCodePoints(a);
    const code_points_b = try self.getCodePoints(b);

    // The long winding road of normalized caseless matching...
    // NFD(CaseFold(NFD(str))) or NFD(CaseFold(str))
    var norm_a = if (requiresPreNfd(code_points_a)) try self.normalizeCodePointsTo(.canon, code_points_a) else a;
    var cf_a = try case_fold_map.caseFoldStr(self.arena.allocator(), norm_a);
    norm_a = try self.normalizeTo(.canon, cf_a);
    var norm_b = if (requiresPreNfd(code_points_b)) try self.normalizeCodePointsTo(.canon, code_points_b) else b;
    var cf_b = try case_fold_map.caseFoldStr(self.arena.allocator(), norm_b);
    norm_b = try self.normalizeTo(.canon, cf_b);

    return mem.eql(u8, norm_a, norm_b);
}

test "Normalizer decompose D" {
    var allocator = std.testing.allocator;
    var normalizer = try init(allocator);
    defer normalizer.deinit();

    var result = normalizer.decompose('\u{00E9}', true);
    try std.testing.expectEqual(result.seq[0], 0x0065);
    try std.testing.expectEqual(result.seq[1], 0x0301);

    result = normalizer.decompose('\u{03D3}', true);
    try std.testing.expectEqual(result.seq[0], 0x03D2);
    try std.testing.expectEqual(result.seq[1], 0x0301);
}

test "Normalizer decompose KD" {
    var allocator = std.testing.allocator;
    var normalizer = try init(allocator);
    defer normalizer.deinit();

    var result = normalizer.decompose('\u{00E9}', false);
    try std.testing.expectEqual(result.seq[0], 0x0065);
    try std.testing.expectEqual(result.seq[1], 0x0301);

    result = normalizer.decompose('\u{03D3}', false);
    try std.testing.expectEqual(result.seq[0], 0x03A5);
    try std.testing.expectEqual(result.seq[1], 0x0301);
}

test "Normalizer normalizeTo" {
    var path_buf: [1024]u8 = undefined;
    var path = try std.fs.cwd().realpath(".", &path_buf);
    // Check if testing in this library path.
    if (!mem.endsWith(u8, path, "ziglyph")) return;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var allocator = arena.allocator();
    var normalizer = try init(allocator);
    defer normalizer.deinit();

    var file = try std.fs.cwd().openFile("src/data/ucd/NormalizationTest.txt", .{});
    defer file.close();
    var buf_reader = std.io.bufferedReader(file.reader());
    var input_stream = buf_reader.reader();
    var line_no: usize = 0;
    var buf: [4096]u8 = undefined;

    while (try input_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        line_no += 1;
        // Skip comments or empty lines.
        if (line.len == 0 or line[0] == '#' or line[0] == '@') continue;
        //std.debug.print("{}: {s}\n", .{ line_no, line });
        // Iterate over fields.
        var fields = mem.split(u8, line, ";");
        var field_index: usize = 0;
        var input: []u8 = undefined;

        while (fields.next()) |field| : (field_index += 1) {
            if (field_index == 0) {
                var i_buf = std.ArrayList(u8).init(allocator);
                defer i_buf.deinit();
                var i_fields = mem.split(u8, field, " ");
                while (i_fields.next()) |s| {
                    const icp = try std.fmt.parseInt(u21, s, 16);
                    const len = try unicode.utf8Encode(icp, &cp_buf);
                    try i_buf.appendSlice(cp_buf[0..len]);
                }
                input = i_buf.toOwnedSlice();
            } else if (field_index == 1) {
                // NFC, time to test.
                var w_buf = std.ArrayList(u8).init(allocator);
                defer w_buf.deinit();
                var w_fields = mem.split(u8, field, " ");
                while (w_fields.next()) |s| {
                    const wcp = try std.fmt.parseInt(u21, s, 16);
                    const len = try unicode.utf8Encode(wcp, &cp_buf);
                    try w_buf.appendSlice(cp_buf[0..len]);
                }
                const want = w_buf.items;
                const got = try normalizer.normalizeTo(.composed, input);
                try std.testing.expectEqualSlices(u8, want, got);
            } else if (field_index == 2) {
                // NFD, time to test.
                var w_buf = std.ArrayList(u8).init(allocator);
                defer w_buf.deinit();
                var w_fields = mem.split(u8, field, " ");
                while (w_fields.next()) |s| {
                    const wcp = try std.fmt.parseInt(u21, s, 16);
                    const len = try unicode.utf8Encode(wcp, &cp_buf);
                    try w_buf.appendSlice(cp_buf[0..len]);
                }
                const want = w_buf.items;
                const got = try normalizer.normalizeTo(.canon, input);
                try std.testing.expectEqualSlices(u8, want, got);
            } else if (field_index == 3) {
                // NFKC, time to test.
                var w_buf = std.ArrayList(u8).init(allocator);
                defer w_buf.deinit();
                var w_fields = mem.split(u8, field, " ");
                while (w_fields.next()) |s| {
                    const wcp = try std.fmt.parseInt(u21, s, 16);
                    const len = try unicode.utf8Encode(wcp, &cp_buf);
                    try w_buf.appendSlice(cp_buf[0..len]);
                }
                const want = w_buf.items;
                const got = try normalizer.normalizeTo(.komposed, input);
                try std.testing.expectEqualSlices(u8, want, got);
            } else if (field_index == 4) {
                // NFKD, time to test.
                var w_buf = std.ArrayList(u8).init(allocator);
                defer w_buf.deinit();
                var w_fields = mem.split(u8, field, " ");
                while (w_fields.next()) |s| {
                    const wcp = try std.fmt.parseInt(u21, s, 16);
                    const len = try unicode.utf8Encode(wcp, &cp_buf);
                    try w_buf.appendSlice(cp_buf[0..len]);
                }
                const want = w_buf.items;
                const got = try normalizer.normalizeTo(.compat, input);
                try std.testing.expectEqualSlices(u8, want, got);
            } else {
                continue;
            }
        }
    }
}

test "Normalizer eqlBy" {
    var allocator = std.testing.allocator;
    var normalizer = try init(allocator);
    defer normalizer.deinit();

    try std.testing.expect(try normalizer.eqlBy("foé", "foe\u{0301}", .normalize));
    try std.testing.expect(try normalizer.eqlBy("foϓ", "fo\u{03D2}\u{0301}", .normalize));
    try std.testing.expect(try normalizer.eqlBy("Foϓ", "fo\u{03D2}\u{0301}", .norm_ignore));
    try std.testing.expect(try normalizer.eqlBy("FOÉ", "foe\u{0301}", .norm_ignore)); // foÉ == foé
    try std.testing.expect(try normalizer.eqlBy("FOE", "foe", .ident));
    try std.testing.expect(try normalizer.eqlBy("ÁbC123\u{0390}", "ábc123\u{0390}", .ident));
}
