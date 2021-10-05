//! `Grapheme` represents a Unicode grapheme cluster with related functionality.

const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const testing = std.testing;
const unicode = std.unicode;

const CodePoint = @import("CodePoint.zig");
const CodePointIterator = CodePoint.CodePointIterator;
const emoji = @import("../ziglyph.zig").emoji_data;
const gbp = @import("../ziglyph.zig").grapheme_break_property;

pub const Grapheme = @This();

bytes: []const u8,
offset: usize,

/// `eql` comparse `str` with the bytes of this grapheme cluster for equality.
pub fn eql(self: Grapheme, str: []const u8) bool {
    return mem.eql(u8, self.bytes, str);
}

const Type = enum {
    control,
    cr,
    extend,
    han_l,
    han_lv,
    han_lvt,
    han_t,
    han_v,
    lf,
    prepend,
    regional,
    spacing,
    xpic,
    zwj,
    any,

    fn get(cp: CodePoint) Type {
        var ty: Type = .any;
        if (0x000D == cp.scalar) ty = .cr;
        if (0x000A == cp.scalar) ty = .lf;
        if (0x200D == cp.scalar) ty = .zwj;
        if (gbp.isControl(cp.scalar)) ty = .control;
        if (gbp.isExtend(cp.scalar)) ty = .extend;
        if (gbp.isL(cp.scalar)) ty = .han_l;
        if (gbp.isLv(cp.scalar)) ty = .han_lv;
        if (gbp.isLvt(cp.scalar)) ty = .han_lvt;
        if (gbp.isT(cp.scalar)) ty = .han_t;
        if (gbp.isV(cp.scalar)) ty = .han_v;
        if (gbp.isPrepend(cp.scalar)) ty = .prepend;
        if (gbp.isRegionalIndicator(cp.scalar)) ty = .regional;
        if (gbp.isSpacingmark(cp.scalar)) ty = .spacing;
        if (emoji.isExtendedPictographic(cp.scalar)) ty = .xpic;

        return ty;
    }
};

const Token = struct {
    ty: Type,
    code_point: CodePoint,
    offset: usize = 0,

    fn is(self: Token, ty: Type) bool {
        return self.ty == ty;
    }
};

const TokenList = std.ArrayList(Token);

/// `GraphemeIterator` iterates a sting one grapheme cluster at-a-time.
pub const GraphemeIterator = struct {
    bytes: []const u8,
    i: ?usize = null,
    start: ?Token = null,
    tokens: TokenList,

    const Self = @This();

    pub fn init(allocator: *mem.Allocator, str: []const u8) !Self {
        if (!unicode.utf8ValidateSlice(str)) return error.InvalidUtf8;

        var self = Self{
            .bytes = str,
            .tokens = TokenList.init(allocator),
        };

        try self.lex();

        if (self.tokens.items.len == 0) return error.NoTokens;
        self.start = self.tokens.items[0];

        // Set token offsets.
        for (self.tokens.items) |*token, i| {
            token.offset = i;
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    fn lex(self: *Self) !void {
        var iter = CodePointIterator{
            .bytes = self.bytes,
            .i = 0,
        };

        while (iter.next()) |cp| {
            try self.tokens.append(.{
                .ty = Type.get(cp),
                .code_point = cp,
            });
        }
    }

    // Main API.
    pub fn next(self: *Self) ?Grapheme {
        if (self.advance()) |current_token| {
            var end = self.current();

            if (isBreaker(current_token)) {
                if (current_token.is(.cr)) {
                    if (self.peek()) |p| {
                        // GB3
                        if (p.is(.lf)) {
                            _ = self.advance();
                            end = self.current();
                        }
                    }
                }
            }

            if (current_token.is(.regional)) {
                if (self.peek()) |p| {
                    // GB12
                    if (p.is(.regional) and !isIgnorable(end)) {
                        _ = self.advance();
                        end = self.current();
                    }
                }
            }

            if (current_token.is(.han_l)) {
                if (self.peek()) |p| {
                    // GB6
                    if ((p.is(.han_l) or p.is(.han_v) or p.is(.han_lv) or p.is(.han_lvt)) and
                        !isIgnorable(end))
                    {
                        _ = self.advance();
                        end = self.current();
                    }
                }
            }

            if (current_token.is(.han_lv) or current_token.is(.han_v)) {
                if (self.peek()) |p| {
                    // GBy
                    if ((p.is(.han_v) or p.is(.han_t)) and !isIgnorable(end)) {
                        _ = self.advance();
                        end = self.current();
                    }
                }
            }

            if (current_token.is(.han_lvt) or current_token.is(.han_t)) {
                if (self.peek()) |p| {
                    // GB8
                    if (p.is(.han_t) and !isIgnorable(end)) {
                        _ = self.advance();
                        end = self.current();
                    }
                }
            }

            if (current_token.is(.xpic)) {
                if (self.peek()) |p| {
                    // GB11
                    if (p.is(.xpic) and end.is(.zwj)) {
                        _ = self.advance();
                        end = self.current();
                    }
                }
            }

            const start = self.start.?;
            self.start = self.peek();

            // GB999
            return self.emit(start, end);
        }

        return null;
    }

    // Token array movement.
    fn forward(self: *Self) bool {
        if (self.i) |*index| {
            index.* += 1;
            if (index.* >= self.tokens.items.len) return false;
        } else {
            self.i = 0;
        }

        return true;
    }

    // Token array movement.
    fn getRelative(self: Self, n: isize) ?Token {
        var index: usize = self.i orelse 0;

        if (n < 0) {
            if (index == 0 or -%n > index) return null;
            index -= @intCast(usize, -%n);
        } else {
            const un = @intCast(usize, n);
            if (index + un >= self.tokens.items.len) return null;
            index += un;
        }

        return self.tokens.items[index];
    }

    fn prevAfterSkip(self: *Self, predicate: TokenPredicate) ?Token {
        if (self.i == null or self.i.? == 0) return null;

        var i: isize = 1;
        while (self.getRelative(-i)) |token| : (i += 1) {
            if (!predicate(token)) return token;
        }

        return null;
    }

    fn current(self: Self) Token {
        // Assumes self.i is not null.
        return self.tokens.items[self.i.?];
    }

    fn last(self: Self) Token {
        return self.tokens.items[self.tokens.items.len - 1];
    }

    fn peek(self: Self) ?Token {
        return self.getRelative(1);
    }

    fn peekAfterSkip(self: *Self, predicate: TokenPredicate) ?Token {
        var i: isize = 1;
        while (self.getRelative(i)) |token| : (i += 1) {
            if (!predicate(token)) return token;
        }

        return null;
    }

    fn advance(self: *Self) ?Token {
        const token = if (self.forward()) self.current() else return null;
        // GB9b
        if (token.is(.prepend)) {
            if (self.peek()) |p| {
                if (!isBreaker(p)) return self.advance();
            }
        }
        // GB9, GBia
        if (!isBreaker(token)) _ = self.skipIgnorables(token);

        return token;
    }

    fn run(self: *Self, predicate: TokenPredicate) void {
        while (self.peek()) |token| {
            if (!predicate(token)) break;
            _ = self.advance();
        }
    }

    fn skipIgnorables(self: *Self, end: Token) Token {
        if (self.peek()) |p| {
            if (isIgnorable(p)) {
                self.run(isIgnorable);
                return self.current();
            }
        }

        return end;
    }

    // Production.
    fn emit(self: Self, start_token: Token, end_token: Token) Grapheme {
        const start = start_token.code_point.offset;
        const end = end_token.code_point.end();

        return .{
            .bytes = self.bytes[start..end],
            .offset = start,
        };
    }
};

// Predicates
const TokenPredicate = fn (Token) bool;

fn isBreaker(token: Token) bool {
    return token.ty == .control or token.ty == .cr or token.ty == .lf;
}

fn isControl(token: Token) bool {
    return token.ty == .control;
}

fn isIgnorable(token: Token) bool {
    return token.ty == .extend or token.ty == .spacing or token.ty == .zwj;
}

test "Segmentation GraphemeIterator" {
    var path_buf: [1024]u8 = undefined;
    var path = try std.fs.cwd().realpath(".", &path_buf);
    // Check if testing in this library path.
    if (!mem.endsWith(u8, path, "ziglyph")) return;

    var allocator = std.testing.allocator;
    var file = try std.fs.cwd().openFile("src/data/ucd/GraphemeBreakTest.txt", .{});
    defer file.close();
    var buf_reader = std.io.bufferedReader(file.reader());
    var input_stream = buf_reader.reader();

    var buf: [4096]u8 = undefined;
    var line_no: usize = 1;

    while (try input_stream.readUntilDelimiterOrEof(&buf, '\n')) |raw| : (line_no += 1) {
        // Skip comments or empty lines.
        if (raw.len == 0 or raw[0] == '#' or raw[0] == '@') continue;

        // Clean up.
        var line = mem.trimLeft(u8, raw, "÷ ");
        if (mem.indexOf(u8, line, " ÷\t#")) |octo| {
            line = line[0..octo];
        }
        //debug.print("\nline {}: {s}\n", .{ line_no, line });

        // Iterate over fields.
        var want = std.ArrayList(Grapheme).init(allocator);
        defer {
            for (want.items) |snt| {
                allocator.free(snt.bytes);
            }
            want.deinit();
        }

        var all_bytes = std.ArrayList(u8).init(allocator);
        defer all_bytes.deinit();

        var sentences = mem.split(u8, line, " ÷ ");
        var bytes_index: usize = 0;

        while (sentences.next()) |field| {
            var code_points = mem.split(u8, field, " ");
            var cp_buf: [4]u8 = undefined;
            var cp_index: usize = 0;
            var first: u21 = undefined;
            var cp_bytes = std.ArrayList(u8).init(allocator);
            defer cp_bytes.deinit();

            while (code_points.next()) |code_point| {
                if (mem.eql(u8, code_point, "×")) continue;
                const cp: u21 = try std.fmt.parseInt(u21, code_point, 16);
                if (cp_index == 0) first = cp;
                const len = try unicode.utf8Encode(cp, &cp_buf);
                try all_bytes.appendSlice(cp_buf[0..len]);
                try cp_bytes.appendSlice(cp_buf[0..len]);
                cp_index += len;
            }

            try want.append(Grapheme{
                .bytes = cp_bytes.toOwnedSlice(),
                .offset = bytes_index,
            });

            bytes_index += cp_index;
        }

        //debug.print("\nline {}: {s}\n", .{ line_no, all_bytes.items });
        var iter = try GraphemeIterator.init(allocator, all_bytes.items);
        defer iter.deinit();

        // Chaeck.
        for (want.items) |w| {
            const g = (iter.next()).?;
            //debug.print("\n", .{});
            //for (w.bytes) |b| {
            //    debug.print("line {}: w:({x})\n", .{ line_no, b });
            //}
            //for (g.bytes) |b| {
            //    debug.print("line {}: g:({x})\n", .{ line_no, b });
            //}
            //debug.print("line {}: w:({s}), g:({s})\n", .{ line_no, w.bytes, g.bytes });
            try testing.expectEqualStrings(w.bytes, g.bytes);
            try testing.expectEqual(w.offset, g.offset);
        }
    }
}

// Comptime
fn getTokens(comptime str: []const u8, comptime n: usize) [n]Token {
    var i: usize = 0;
    var cp_iter = CodePointIterator{ .bytes = str };
    var tokens: [n]Token = undefined;

    while (cp_iter.next()) |cp| : (i += 1) {
        tokens[i] = .{
            .ty = Type.get(cp),
            .code_point = cp,
            .offset = i,
        };
    }

    return tokens;
}

/// `ComptimeGraphemeIterator` is like `GraphemeIterator` but must be given a string literal to do its work at compile time.
pub fn ComptimeGraphemeIterator(comptime str: []const u8) type {
    const cp_count: usize = unicode.utf8CountCodepoints(str) catch @compileError("Invalid UTF-8.");
    if (cp_count == 0) @compileError("No code points?");
    const tokens = getTokens(str, cp_count);

    return struct {
        bytes: []const u8 = str,
        i: ?usize = null,
        start: ?Token = tokens[0],
        tokens: [cp_count]Token = tokens,

        const Self = @This();

        // Main API.
        pub fn next(self: *Self) ?Grapheme {
            if (self.advance()) |current_token| {
                var end = self.current();

                if (isBreaker(current_token)) {
                    if (current_token.is(.cr)) {
                        if (self.peek()) |p| {
                            // GB3
                            if (p.is(.lf)) {
                                _ = self.advance();
                                end = self.current();
                            }
                        }
                    }
                }

                if (current_token.is(.regional)) {
                    if (self.peek()) |p| {
                        // GB12
                        if (p.is(.regional) and !isIgnorable(end)) {
                            _ = self.advance();
                            end = self.current();
                        }
                    }
                }

                if (current_token.is(.han_l)) {
                    if (self.peek()) |p| {
                        // GB6
                        if ((p.is(.han_l) or p.is(.han_v) or p.is(.han_lv) or p.is(.han_lvt)) and
                            !isIgnorable(end))
                        {
                            _ = self.advance();
                            end = self.current();
                        }
                    }
                }

                if (current_token.is(.han_lv) or current_token.is(.han_v)) {
                    if (self.peek()) |p| {
                        // GBy
                        if ((p.is(.han_v) or p.is(.han_t)) and !isIgnorable(end)) {
                            _ = self.advance();
                            end = self.current();
                        }
                    }
                }

                if (current_token.is(.han_lvt) or current_token.is(.han_t)) {
                    if (self.peek()) |p| {
                        // GB8
                        if (p.is(.han_t) and !isIgnorable(end)) {
                            _ = self.advance();
                            end = self.current();
                        }
                    }
                }

                if (current_token.is(.xpic)) {
                    if (self.peek()) |p| {
                        // GB11
                        if (p.is(.xpic) and end.is(.zwj)) {
                            _ = self.advance();
                            end = self.current();
                        }
                    }
                }

                const start = self.start.?;
                self.start = self.peek();

                // GB999
                return self.emit(start, end);
            }

            return null;
        }

        // Token array movement.
        fn forward(self: *Self) bool {
            if (self.i) |*index| {
                index.* += 1;
                if (index.* >= self.tokens.len) return false;
            } else {
                self.i = 0;
            }

            return true;
        }

        pub fn count(self: *Self) usize {
            const original_i = self.i;
            const original_start = self.start;
            defer {
                self.i = original_i;
                self.start = original_start;
            }

            self.rewind();
            var i: usize = 0;
            while (self.next()) |_| : (i += 1) {}

            return i;
        }

        // Token array movement.
        pub fn rewind(self: *Self) void {
            self.i = null;
            self.start = self.tokens[0];
        }

        fn getRelative(self: Self, n: isize) ?Token {
            var index: usize = self.i orelse 0;

            if (n < 0) {
                if (index == 0 or -%n > index) return null;
                index -= @intCast(usize, -%n);
            } else {
                const un = @intCast(usize, n);
                if (index + un >= self.tokens.len) return null;
                index += un;
            }

            return self.tokens[index];
        }

        fn prevAfterSkip(self: *Self, predicate: TokenPredicate) ?Token {
            if (self.i == null or self.i.? == 0) return null;

            var i: isize = 1;
            while (self.getRelative(-i)) |token| : (i += 1) {
                if (!predicate(token)) return token;
            }

            return null;
        }

        fn current(self: Self) Token {
            // Assumes self.i is not null.
            return self.tokens[self.i.?];
        }

        fn last(self: Self) Token {
            return self.tokens[self.tokens.len - 1];
        }

        fn peek(self: Self) ?Token {
            return self.getRelative(1);
        }

        fn peekAfterSkip(self: *Self, predicate: TokenPredicate) ?Token {
            var i: isize = 1;
            while (self.getRelative(i)) |token| : (i += 1) {
                if (!predicate(token)) return token;
            }

            return null;
        }

        fn advance(self: *Self) ?Token {
            const token = if (self.forward()) self.current() else return null;
            // GB9b
            if (token.is(.prepend)) {
                if (self.peek()) |p| {
                    if (!isBreaker(p)) return self.advance();
                }
            }
            // GB9, GBia
            if (!isBreaker(token)) _ = self.skipIgnorables(token);

            return token;
        }

        fn run(self: *Self, predicate: TokenPredicate) void {
            while (self.peek()) |token| {
                if (!predicate(token)) break;
                _ = self.advance();
            }
        }

        fn skipIgnorables(self: *Self, end: Token) Token {
            if (self.peek()) |p| {
                if (isIgnorable(p)) {
                    self.run(isIgnorable);
                    return self.current();
                }
            }

            return end;
        }

        // Production.
        fn emit(self: Self, start_token: Token, end_token: Token) Grapheme {
            const start = start_token.code_point.offset;
            const end = end_token.code_point.end();

            return .{
                .bytes = self.bytes[start..end],
                .offset = start,
            };
        }
    };
}

test "Segmentation ComptimeGraphemeIterator" {
    comptime var ct_iter = ComptimeGraphemeIterator("Héllo"){};
    const n = comptime ct_iter.count();
    var graphemes: [n]Grapheme = undefined;
    comptime {
        var i: usize = 0;
        while (ct_iter.next()) |grapheme| : (i += 1) {
            graphemes[i] = grapheme;
        }
    }

    const want = [_][]const u8{ "H", "é", "l", "l", "o" };

    for (graphemes) |grapheme, i| {
        try testing.expect(grapheme.eql(want[i]));
    }
}
