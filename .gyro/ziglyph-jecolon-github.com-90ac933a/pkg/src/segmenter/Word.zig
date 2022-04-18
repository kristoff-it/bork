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

    fn is(self: Token, ty: Type) bool {
        return self.ty == ty;
    }
};

/// `WordIterator` iterates a Unicde string one word at-a-time. Note that whitespace and punctuation appear as separate 
/// elements in the iteration.
pub const WordIterator = struct {
    cp_iter: CodePointIterator,
    current: ?Token = null,
    start: ?Token = null,

    const Self = @This();

    pub fn init(str: []const u8) !Self {
        if (!unicode.utf8ValidateSlice(str)) return error.InvalidUtf8;
        return Self{ .cp_iter = CodePointIterator{ .bytes = str } };
    }

    // Main API.
    pub fn next(self: *Self) ?Word {
        if (self.advance()) |latest_non_ignorable| {
            var end = self.current.?;
            var done = false;

            if (!done and isBreaker(latest_non_ignorable)) {
                if (latest_non_ignorable.is(.cr)) {
                    if (self.peek()) |p| {
                        // WB
                        if (p.is(.lf)) {
                            _ = self.advance();
                            end = self.current.?;
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
                        end = self.current.?;
                        done = true;
                    }
                }
            }

            if (!done and latest_non_ignorable.is(.wsegspace)) {
                if (self.peek()) |p| {
                    // WB3d
                    if (p.is(.wsegspace) and !isIgnorable(end)) {
                        _ = self.advance();
                        end = self.current.?;
                        done = true;
                    }
                }
            }

            if (!done and (isAHLetter(latest_non_ignorable) or latest_non_ignorable.is(.numeric))) {
                if (self.peek()) |p| {
                    // WB5, WB8, WB9, WB10
                    if (isAHLetter(p) or p.is(.numeric)) {
                        self.run(isAlphaNum);
                        end = self.current.?;
                        done = true;
                    }
                }
            }

            if (!done and isAHLetter(latest_non_ignorable)) {
                if (self.peek()) |p| {
                    // WB6, WB7
                    if (p.is(.midletter) or isMidNumLetQ(p)) {
                        // Save state
                        const saved_i = self.cp_iter.i;
                        const saved_current = self.current;
                        const saved_start = self.start;

                        _ = self.advance(); // (MidLetter|MidNumLetQ)
                        if (self.peek()) |pp| {
                            if (isAHLetter(pp)) {
                                _ = self.advance(); // AHLetter
                                end = self.current.?;
                                done = true;
                            }
                        }

                        if (!done) {
                            // Restore state
                            self.cp_iter.i = saved_i;
                            self.current = saved_current;
                            self.start = saved_start;
                        }
                    }
                }
            }

            if (!done and latest_non_ignorable.is(.hletter)) {
                if (self.peek()) |p| {
                    // WB7a
                    if (p.is(.squote)) {
                        _ = self.advance();
                        end = self.current.?;
                        done = true;
                    } else if (p.is(.dquote)) {
                        // WB7b, WB7c
                        // Save state
                        const saved_i = self.cp_iter.i;
                        const saved_current = self.current;
                        const saved_start = self.start;

                        _ = self.advance(); // Double_Quote
                        if (self.peek()) |pp| {
                            if (pp.is(.hletter)) {
                                _ = self.advance(); // Hebrew_Letter
                                end = self.current.?;
                                done = true;
                            }
                        }

                        if (!done) {
                            // Restore state
                            self.cp_iter.i = saved_i;
                            self.current = saved_current;
                            self.start = saved_start;
                        }
                    }
                }
            }

            if (!done and latest_non_ignorable.is(.numeric)) {
                if (self.peek()) |p| {
                    if (p.is(.midnum) or isMidNumLetQ(p)) {
                        // WB11, WB12
                        // Save state
                        const saved_i = self.cp_iter.i;
                        const saved_current = self.current;
                        const saved_start = self.start;

                        _ = self.advance(); // (MidNum|MidNumLetQ)
                        if (self.peek()) |pp| {
                            if (pp.is(.numeric)) {
                                _ = self.advance(); // Numeric
                                end = self.current.?;
                                done = true;
                            }
                        }

                        if (!done) {
                            // Restore state
                            self.cp_iter.i = saved_i;
                            self.current = saved_current;
                            self.start = saved_start;
                        }
                    }
                }
            }

            if (!done and (isAHLetter(latest_non_ignorable) or latest_non_ignorable.is(.numeric) or latest_non_ignorable.is(.katakana) or
                latest_non_ignorable.is(.extendnumlet)))
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
                            end = self.current.?;
                            done = true;
                        } else break;
                    } else break;
                }
            }

            if (!done and latest_non_ignorable.is(.extendnumlet)) {
                while (true) {
                    if (self.peek()) |p| {
                        // WB13b
                        if (isAHLetter(p) or p.is(.numeric) or p.is(.katakana)) {
                            _ = self.advance(); // (AHLetter|Numeric|Katakana)
                            end = self.current.?;
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

            if (!done and latest_non_ignorable.is(.katakana)) {
                if (self.peek()) |p| {
                    // WB13
                    if (p.is(.katakana)) {
                        _ = self.advance();
                        end = self.current.?;
                        done = true;
                    }
                }
            }

            if (!done and latest_non_ignorable.is(.regional)) {
                if (self.peek()) |p| {
                    // WB
                    if (p.is(.regional)) {
                        _ = self.advance();
                        end = self.current.?;
                        done = true;
                    }
                }
            }

            if (!done and latest_non_ignorable.is(.xpic)) {
                if (self.peek()) |p| {
                    // WB
                    if (p.is(.xpic) and end.is(.zwj)) {
                        _ = self.advance();
                        end = self.current.?;
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

    fn peek(self: *Self) ?Token {
        const saved_i = self.cp_iter.i;
        defer self.cp_iter.i = saved_i;

        return if (self.cp_iter.next()) |cp| Token{
            .ty = Type.get(cp),
            .code_point = cp,
        } else null;
    }

    fn advance(self: *Self) ?Token {
        const latest_non_ignorable = if (self.cp_iter.next()) |cp| Token{
            .ty = Type.get(cp),
            .code_point = cp,
        } else return null;

        self.current = latest_non_ignorable;
        if (self.start == null) self.start = latest_non_ignorable; // Happens only at beginning.

        // WB3a, WB3b
        if (!isBreaker(latest_non_ignorable)) self.skipIgnorables();

        return latest_non_ignorable;
    }

    fn run(self: *Self, predicate: TokenPredicate) void {
        while (self.peek()) |token| {
            if (!predicate(token)) break;
            _ = self.advance();
        }
    }

    fn skipIgnorables(self: *Self) void {
        while (self.peek()) |peek_token| {
            if (!isIgnorable(peek_token)) break;
            _ = self.advance();
        }
    }

    // Production.
    fn emit(self: Self, start_token: Token, end_token: Token) Word {
        const start = start_token.code_point.offset;
        const end = end_token.code_point.end();

        return .{
            .bytes = self.cp_iter.bytes[start..end],
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

        var words = mem.split(u8, line, " ÷ ");
        var bytes_index: usize = 0;

        while (words.next()) |field| {
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
        var iter = try WordIterator.init(all_bytes.items);

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

test "Segmentation comptime WordIterator" {
    const want = [_][]const u8{ "Hello", " ", "World" };

    comptime {
        var ct_iter = try WordIterator.init("Hello World");
        var i = 0;
        while (ct_iter.next()) |word| : (i += 1) {
            try testing.expect(word.eql(want[i]));
        }
    }
}
