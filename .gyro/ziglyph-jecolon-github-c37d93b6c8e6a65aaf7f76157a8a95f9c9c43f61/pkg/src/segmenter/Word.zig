//! `Word` represents a single word within a Unicde string.

const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const testing = std.testing;
const unicode = std.unicode;

const wbp = @import("../ziglyph.zig").word_break_property;
const CodePoint = @import("CodePoint.zig");
const CodePointIterator = CodePoint.CodePointIterator;
const emoji = @import("../ziglyph.zig").emoji_data;

pub const Word = @This();

bytes: []const u8,
offset: usize,

/// `eal` compares `str` with the bytes of this word for equality.
pub fn eql(self: Word, str: []const u8) bool {
    return mem.eql(u8, self.bytes, str);
}

const Type = enum {
    aletter,
    cr,
    dquote,
    extend,
    extendnumlet,
    format,
    hletter,
    katakana,
    lf,
    midletter,
    midnum,
    midnumlet,
    newline,
    numeric,
    regional,
    squote,
    wsegspace,
    xpic,
    zwj,
    any,

    fn get(cp: CodePoint) Type {
        var ty: Type = .any;
        if (0x000D == cp.scalar) ty = .cr;
        if (0x000A == cp.scalar) ty = .lf;
        if (0x200D == cp.scalar) ty = .zwj;
        if (0x0022 == cp.scalar) ty = .dquote;
        if (0x0027 == cp.scalar) ty = .squote;
        if (wbp.isAletter(cp.scalar)) ty = .aletter;
        if (wbp.isExtend(cp.scalar)) ty = .extend;
        if (wbp.isExtendnumlet(cp.scalar)) ty = .extendnumlet;
        if (wbp.isFormat(cp.scalar)) ty = .format;
        if (wbp.isHebrewLetter(cp.scalar)) ty = .hletter;
        if (wbp.isKatakana(cp.scalar)) ty = .katakana;
        if (wbp.isMidletter(cp.scalar)) ty = .midletter;
        if (wbp.isMidnum(cp.scalar)) ty = .midnum;
        if (wbp.isMidnumlet(cp.scalar)) ty = .midnumlet;
        if (wbp.isNewline(cp.scalar)) ty = .newline;
        if (wbp.isNumeric(cp.scalar)) ty = .numeric;
        if (wbp.isRegionalIndicator(cp.scalar)) ty = .regional;
        if (wbp.isWsegspace(cp.scalar)) ty = .wsegspace;
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

/// `WordIterator` iterates a Unicde string one word at-a-time. Note that whitespace and punctuation appear as separate 
/// elements in the iteration.
pub const WordIterator = struct {
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
    pub fn next(self: *Self) ?Word {
        if (self.advance()) |current_token| {
            var end = self.current();
            var done = false;

            if (!done and isBreaker(current_token)) {
                if (current_token.is(.cr)) {
                    if (self.peek()) |p| {
                        // WB
                        if (p.is(.lf)) {
                            _ = self.advance();
                            end = self.current();
                            done = true;
                        }
                    }
                }
            }

            if (!done and end.is(.zwj)) {
                if (self.peek()) |p| {
                    // WB3c
                    if (p.is(.xpic)) {
                        _ = self.advance();
                        end = self.current();
                        done = true;
                    }
                }
            }

            if (!done and current_token.is(.wsegspace)) {
                if (self.peek()) |p| {
                    // WB3d
                    if (p.is(.wsegspace) and !isIgnorable(end)) {
                        _ = self.advance();
                        end = self.current();
                        done = true;
                    }
                }
            }

            if (!done and (isAHLetter(current_token) or current_token.is(.numeric))) {
                if (self.peek()) |p| {
                    // WB5, WB8, WB9, WB10
                    if (isAHLetter(p) or p.is(.numeric)) {
                        self.run(isAlphaNum);
                        end = self.current();
                        done = true;
                    }
                }
            }

            if (!done and isAHLetter(current_token)) {
                if (self.peek()) |p| {
                    // WB6, WB7
                    if (p.is(.midletter) or isMidNumLetQ(p)) {
                        const original_i = self.i; // Save position.

                        _ = self.advance(); // (MidLetter|MidNumLetQ)
                        if (self.peek()) |pp| {
                            if (isAHLetter(pp)) {
                                _ = self.advance(); // AHLetter
                                end = self.current();
                                done = true;
                            }
                        }

                        if (!done) self.i = original_i; // Restore position.
                    }
                }
            }

            if (!done and current_token.is(.hletter)) {
                if (self.peek()) |p| {
                    // WB7a
                    if (p.is(.squote)) {
                        _ = self.advance();
                        end = self.current();
                        done = true;
                    } else if (p.is(.dquote)) {
                        // WB7b, WB7c
                        const original_i = self.i; // Save position.

                        _ = self.advance(); // Double_Quote
                        if (self.peek()) |pp| {
                            if (pp.is(.hletter)) {
                                _ = self.advance(); // Hebrew_Letter
                                end = self.current();
                                done = true;
                            }
                        }

                        if (!done) self.i = original_i; // Restore position.
                    }
                }
            }

            if (!done and current_token.is(.numeric)) {
                if (self.peek()) |p| {
                    if (p.is(.midnum) or isMidNumLetQ(p)) {
                        // WB11, WB12
                        const original_i = self.i; // Save position.

                        _ = self.advance(); // (MidNum|MidNumLetQ)
                        if (self.peek()) |pp| {
                            if (pp.is(.numeric)) {
                                _ = self.advance(); // Numeric
                                end = self.current();
                                done = true;
                            }
                        }

                        if (!done) self.i = original_i; // Restore position.
                    }
                }
            }

            if (!done and (isAHLetter(current_token) or current_token.is(.numeric) or current_token.is(.katakana) or
                current_token.is(.extendnumlet)))
            {
                while (true) {
                    if (self.peek()) |p| {
                        // WB13a
                        if (p.is(.extendnumlet)) {
                            _ = self.advance(); // ExtendNumLet
                            if (self.peek()) |pp| {
                                if (isAHLetter(pp) or isNumeric(pp) or pp.is(.katakana)) {
                                    // WB13b
                                    _ = self.advance(); // (AHLetter|Numeric|Katakana)
                                }
                            }
                            end = self.current();
                            done = true;
                        } else break;
                    } else break;
                }
            }

            if (!done and current_token.is(.extendnumlet)) {
                while (true) {
                    if (self.peek()) |p| {
                        // WB13b
                        if (isAHLetter(p) or p.is(.numeric) or p.is(.katakana)) {
                            _ = self.advance(); // (AHLetter|Numeric|Katakana)
                            end = self.current();
                            done = true;

                            if (self.peek()) |pp| {
                                // Chain.
                                if (pp.is(.extendnumlet)) {
                                    _ = self.advance(); // ExtendNumLet
                                    continue;
                                }
                            }
                        } else break;
                    } else break;
                }
            }

            if (!done and current_token.is(.katakana)) {
                if (self.peek()) |p| {
                    // WB13
                    if (p.is(.katakana)) {
                        _ = self.advance();
                        end = self.current();
                        done = true;
                    }
                }
            }

            if (!done and current_token.is(.regional)) {
                if (self.peek()) |p| {
                    // WB
                    if (p.is(.regional)) {
                        _ = self.advance();
                        end = self.current();
                        done = true;
                    }
                }
            }

            if (!done and current_token.is(.xpic)) {
                if (self.peek()) |p| {
                    // WB
                    if (p.is(.xpic) and end.is(.zwj)) {
                        _ = self.advance();
                        end = self.current();
                        done = true;
                    }
                }
            }

            const start = self.start.?;
            self.start = self.peek();

            // WB
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
        // WB3a, WB3b
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
    fn emit(self: Self, start_token: Token, end_token: Token) Word {
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

fn isAHLetter(token: Token) bool {
    return token.ty == .aletter or token.ty == .hletter;
}

fn isAlphaNum(token: Token) bool {
    return isAHLetter(token) or isNumeric(token);
}

fn isBreaker(token: Token) bool {
    return token.ty == .newline or token.ty == .cr or token.ty == .lf;
}

fn isIgnorable(token: Token) bool {
    return token.ty == .extend or token.ty == .format or token.ty == .zwj;
}

fn isMidNumLetQ(token: Token) bool {
    return token.ty == .midnumlet or token.ty == .squote;
}

fn isNumeric(token: Token) bool {
    return token.ty == .numeric;
}

test "Segmentation WordIterator" {
    var path_buf: [1024]u8 = undefined;
    var path = try std.fs.cwd().realpath(".", &path_buf);
    // Check if testing in this library path.
    if (!mem.endsWith(u8, path, "ziglyph")) return;

    var allocator = std.testing.allocator;
    var file = try std.fs.cwd().openFile("src/data/ucd/WordBreakTest.txt", .{});
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
        var want = std.ArrayList(Word).init(allocator);
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

            try want.append(Word{
                .bytes = cp_bytes.toOwnedSlice(),
                .offset = bytes_index,
            });

            bytes_index += cp_index;
        }

        //debug.print("\nline {}: {s}\n", .{ line_no, all_bytes.items });
        var iter = try WordIterator.init(allocator, all_bytes.items);
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

/// `ComptimeWordIterator` is like `WordIterator` but requires a string literal to do its work at compile time.
pub fn ComptimeWordIterator(comptime str: []const u8) type {
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
        pub fn next(self: *Self) ?Word {
            if (self.advance()) |current_token| {
                var end = self.current();
                var done = false;

                if (!done and isBreaker(current_token)) {
                    if (current_token.is(.cr)) {
                        if (self.peek()) |p| {
                            // WB
                            if (p.is(.lf)) {
                                _ = self.advance();
                                end = self.current();
                                done = true;
                            }
                        }
                    }
                }

                if (!done and end.is(.zwj)) {
                    if (self.peek()) |p| {
                        // WB3c
                        if (p.is(.xpic)) {
                            _ = self.advance();
                            end = self.current();
                            done = true;
                        }
                    }
                }

                if (!done and current_token.is(.wsegspace)) {
                    if (self.peek()) |p| {
                        // WB3d
                        if (p.is(.wsegspace) and !isIgnorable(end)) {
                            _ = self.advance();
                            end = self.current();
                            done = true;
                        }
                    }
                }

                if (!done and (isAHLetter(current_token) or current_token.is(.numeric))) {
                    if (self.peek()) |p| {
                        // WB5, WB8, WB9, WB10
                        if (isAHLetter(p) or p.is(.numeric)) {
                            self.run(isAlphaNum);
                            end = self.current();
                            done = true;
                        }
                    }
                }

                if (!done and isAHLetter(current_token)) {
                    if (self.peek()) |p| {
                        // WB6, WB7
                        if (p.is(.midletter) or isMidNumLetQ(p)) {
                            const original_i = self.i; // Save position.

                            _ = self.advance(); // (MidLetter|MidNumLetQ)
                            if (self.peek()) |pp| {
                                if (isAHLetter(pp)) {
                                    _ = self.advance(); // AHLetter
                                    end = self.current();
                                    done = true;
                                }
                            }

                            if (!done) self.i = original_i; // Restore position.
                        }
                    }
                }

                if (!done and current_token.is(.hletter)) {
                    if (self.peek()) |p| {
                        // WB7a
                        if (p.is(.squote)) {
                            _ = self.advance();
                            end = self.current();
                            done = true;
                        } else if (p.is(.dquote)) {
                            // WB7b, WB7c
                            const original_i = self.i; // Save position.

                            _ = self.advance(); // Double_Quote
                            if (self.peek()) |pp| {
                                if (pp.is(.hletter)) {
                                    _ = self.advance(); // Hebrew_Letter
                                    end = self.current();
                                    done = true;
                                }
                            }

                            if (!done) self.i = original_i; // Restore position.
                        }
                    }
                }

                if (!done and current_token.is(.numeric)) {
                    if (self.peek()) |p| {
                        if (p.is(.midnum) or isMidNumLetQ(p)) {
                            // WB11, WB12
                            const original_i = self.i; // Save position.

                            _ = self.advance(); // (MidNum|MidNumLetQ)
                            if (self.peek()) |pp| {
                                if (pp.is(.numeric)) {
                                    _ = self.advance(); // Numeric
                                    end = self.current();
                                    done = true;
                                }
                            }

                            if (!done) self.i = original_i; // Restore position.
                        }
                    }
                }

                if (!done and (isAHLetter(current_token) or current_token.is(.numeric) or current_token.is(.katakana) or
                    current_token.is(.extendnumlet)))
                {
                    while (true) {
                        if (self.peek()) |p| {
                            // WB13a
                            if (p.is(.extendnumlet)) {
                                _ = self.advance(); // ExtendNumLet
                                if (self.peek()) |pp| {
                                    if (isAHLetter(pp) or isNumeric(pp) or pp.is(.katakana)) {
                                        // WB13b
                                        _ = self.advance(); // (AHLetter|Numeric|Katakana)
                                    }
                                }
                                end = self.current();
                                done = true;
                            } else break;
                        } else break;
                    }
                }

                if (!done and current_token.is(.extendnumlet)) {
                    while (true) {
                        if (self.peek()) |p| {
                            // WB13b
                            if (isAHLetter(p) or p.is(.numeric) or p.is(.katakana)) {
                                _ = self.advance(); // (AHLetter|Numeric|Katakana)
                                end = self.current();
                                done = true;

                                if (self.peek()) |pp| {
                                    // Chain.
                                    if (pp.is(.extendnumlet)) {
                                        _ = self.advance(); // ExtendNumLet
                                        continue;
                                    }
                                }
                            } else break;
                        } else break;
                    }
                }

                if (!done and current_token.is(.katakana)) {
                    if (self.peek()) |p| {
                        // WB13
                        if (p.is(.katakana)) {
                            _ = self.advance();
                            end = self.current();
                            done = true;
                        }
                    }
                }

                if (!done and current_token.is(.regional)) {
                    if (self.peek()) |p| {
                        // WB
                        if (p.is(.regional)) {
                            _ = self.advance();
                            end = self.current();
                            done = true;
                        }
                    }
                }

                if (!done and current_token.is(.xpic)) {
                    if (self.peek()) |p| {
                        // WB
                        if (p.is(.xpic) and end.is(.zwj)) {
                            _ = self.advance();
                            end = self.current();
                            done = true;
                        }
                    }
                }

                const start = self.start.?;
                self.start = self.peek();

                // WB
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
            // WB3a, WB3b
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
        fn emit(self: Self, start_token: Token, end_token: Token) Word {
            const start = start_token.code_point.offset;
            const end = end_token.code_point.end();

            return .{
                .bytes = self.bytes[start..end],
                .offset = start,
            };
        }
    };
}

test "Segmentation ComptimeWordIterator" {
    comptime var ct_iter = ComptimeWordIterator("Hello World"){};
    const n = comptime ct_iter.count();
    var words: [n]Word = undefined;
    comptime {
        var i: usize = 0;
        while (ct_iter.next()) |word| : (i += 1) {
            words[i] = word;
        }
    }

    const want = [_][]const u8{ "Hello", " ", "World" };

    for (words) |word, i| {
        try testing.expect(word.eql(want[i]));
    }
}
