//! This module extracts the subset of UnicodeData.txt data that represent decompositions, and
//! handles compression/decompression of that subset using Unicode Data Differential Compression
//! (UDDC).
//!
//! Unicode Data Differential Compression (UDDC) is a compression format designed by @slimsag / @hexops
//! specifically for the Unicode data tables required for normalization (decompositions from
//! UnicodeData.txt) and for sorting via the Unicode Collation Algorithm (allkeys.txt). It is
//! designed to compress the files better than e.g. gzip or brotli by exploiting some properties
//! unique to these data tables, but gzip or brotli on top can be complementary. See this issue
//! for some motivations: https://github.com/jecolon/ziglyph/issues/3 and the following blog post for
//! some more insight into the general approach I took:
//!
//! https://devlog.hexops.com/2021/unicode-data-file-compression
//!
//! The compression technique is a form of differential encoding based on a state machine. The
//! compressed file is a stream of opcodes that describe how to reproduce the original input file
//! losslessly. The key insight about these data tables is that each entry (line in the files) have
//! a small, finite number of columns / properties, and each row is often predictibly a small
//! alteration to the next row.
//!
//! The algorithm is simple: it starts by maintaining a number of registers which can faithfully
//! represent any entry in the file. Then, a number of opcodes are provided to alter those registers
//! in specific ways that are common between entries in the file. For example, one opcode may set
//! specific registers to specific values - while another series of opcodes may set up a counter
//! which emits a range of values, incrementing a register by a certain amount each iteration. The
//! goal is obviously to reduce the number of opcodes, and the bit size of them, to produce the
//! smallest stream of opcodes that can losslessly reproduce the entire file.
//!
//! Although the algorithm is nearly identical whether you are compressing the decompositions table
//! or the allkeys.txt UCA table, the number of registers differ and the opcodes are chosen
//! specifically for the types of data found in those files based on some offline statistical
//! frequency analysis.
//!
//! After the decompositions are extracted from UnicodeData.txt, 72K of text remains. In raw, uncompressed
//! binary format, that is reduced to 48K. With UDDC compression we reduce that down to just 19K - beating
//! brotli and gzip compression:
//! 
//! | File                    | Before (bytes) | After (bytes) | Change                 |
//! |-------------------------|----------------|---------------|------------------------|
//! | `Decompositions.bin`    | 48,242         | 19,072        | -60.5% (-29,170 bytes) |
//! | `Decompositions.bin.br` | 24,411         | 14,783        | -39.4% (-9,628 bytes)  |
//! | `Decompositions.bin.gz` | 30,931         | 15,670        | -49.34% (15,261 bytes) |
//! 
//! Similarly, for allkeys.txt, we find a raw, uncompressed binary format results in a 365K file. With UDDC
//! compression we reduce that down to just 99K, again beating brotli and gzip compression:
//!
//! | File                    | Before (bytes) | After (bytes) | Change                  |
//! |-------------------------|----------------|---------------|-------------------------|
//! | `allkeys.bin`           | 373,719        | 100,907       | -73.0% (-272,812 bytes) |
//! | `allkeys.bin.br`        | 108,982        | 44,860        | -58.8% (-64,122 bytes)  |
//! | `allkeys.bin.gz`        | 163,237        | 46,996        | -71.2% (-116,241 bytes) |
//!
//! * Before represents binary format without UDDC compression.
//! * After represents binary format with UDDC compression.
//! * `.br` represents `brotli -9 <file>` compression
//! * `.gz` represents `gzip -9 <file>` compression

const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const unicode = std.unicode;
const testing = std.testing;

iter: usize,
entries: std.ArrayList(Entry),

const DecompFile = @This();

pub const Entry = struct {
    key: [4]u8,
    key_len: usize,
    value: Decomp,

    // Calculates the difference of each integral value in this entry.
    pub fn diff(self: Entry, other: Entry, value_form_diff: *u2) Entry {
        var d = Entry{
            .key = undefined,
            .key_len = self.key_len -% other.key_len,
            .value = Decomp{
                .form = undefined,
                .len = self.value.len -% other.value.len,
            },
        };
        value_form_diff.* = @enumToInt(self.value.form) -% @enumToInt(other.value.form);
        for (d.key) |_, i| d.key[i] = self.key[i] -% other.key[i];
        for (d.value.seq) |_, i| d.value.seq[i] = self.value.seq[i] -% other.value.seq[i];
        return d;
    }
};

/// `Form` is the normalization form.
/// * .canon : Canonical decomposition, which always results in two code points.
/// * .compat : Compatibility decomposition, which can result in at most 18 code points.
/// * .same : Default canonical decomposition to the code point itself.
pub const Form = enum(u2) {
    canon, // D
    compat, // KD
    same, // no more decomposition.
};

/// `Decomp` is the result of decomposing a code point to a normaliztion form.
pub const Decomp = struct {
    form: Form = .canon,
    len: usize = 2,
    seq: [18]u21 = [_]u21{0} ** 18,
};

pub fn deinit(self: *DecompFile) void {
    self.entries.deinit();
}

pub fn next(self: *DecompFile) ?Entry {
    if (self.iter >= self.entries.items.len) return null;
    const entry = self.entries.items[self.iter];
    self.iter += 1;
    return entry;
}

pub fn parseFile(allocator: mem.Allocator, filename: []const u8) !DecompFile {
    var in_file = try std.fs.cwd().openFile(filename, .{});
    defer in_file.close();
    return parse(allocator, in_file.reader());
}

pub fn parse(allocator: mem.Allocator, reader: anytype) !DecompFile {
    var buf_reader = std.io.bufferedReader(reader);
    var input_stream = buf_reader.reader();
    var entries = std.ArrayList(Entry).init(allocator);

    // Iterate over lines.
    var buf: [640]u8 = undefined;
    while (try input_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        // Iterate over fields.
        var fields = mem.split(u8, line, ";");
        var field_index: usize = 0;
        var code_point: []const u8 = undefined;
        var dc = Decomp{};

        while (fields.next()) |raw| : (field_index += 1) {
            if (field_index == 0) {
                // Code point.
                code_point = raw;
            } else if (field_index == 5 and raw.len != 0) {
                // Normalization.
                const parsed_cp = try fmt.parseInt(u21, code_point, 16);
                var _key_backing = std.mem.zeroes([4]u8);
                const key = blk: {
                    const len = try unicode.utf8Encode(parsed_cp, &_key_backing);
                    break :blk _key_backing[0..len];
                };

                var is_compat = false;
                var cp_list: [18][]const u8 = [_][]const u8{""} ** 18;

                var cp_iter = mem.split(u8, raw, " ");
                var i: usize = 0;
                while (cp_iter.next()) |cp| {
                    if (mem.startsWith(u8, cp, "<")) {
                        is_compat = true;
                        continue;
                    }
                    cp_list[i] = cp;
                    i += 1;
                }

                if (!is_compat and i == 1) {
                    // Singleton
                    dc.len = 1;
                    dc.seq[0] = try fmt.parseInt(u21, cp_list[0], 16);
                    try entries.append(Entry{ .key = _key_backing, .key_len = key.len, .value = dc });
                } else if (!is_compat) {
                    // Canonical
                    std.debug.assert(i == 2);
                    dc.seq[0] = try fmt.parseInt(u21, cp_list[0], 16);
                    dc.seq[1] = try fmt.parseInt(u21, cp_list[1], 16);
                    try entries.append(Entry{ .key = _key_backing, .key_len = key.len, .value = dc });
                } else {
                    // Compatibility
                    std.debug.assert(i != 0 and i <= 18);
                    var j: usize = 0;

                    for (cp_list) |ccp| {
                        if (ccp.len == 0) break; // sentinel
                        dc.seq[j] = try fmt.parseInt(u21, ccp, 16);
                        j += 1;
                    }

                    dc.form = .compat;
                    dc.len = j;
                    try entries.append(Entry{ .key = _key_backing, .key_len = key.len, .value = dc });
                }
            } else {
                continue;
            }
        }
    }
    return DecompFile{ .iter = 0, .entries = entries };
}

// A UDDC opcode for a decomposition file.
const Opcode = enum(u4) {
    // increments key[2] += 1; sets value.seq[0]; emits an entry.
    // 1848 instances
    increment_key_2_and_set_value_seq_0_2bit_and_emit, // 749 instances, 1779 byte reduction
    increment_key_2_and_set_value_seq_0_12bit_and_emit, // 741 instances, 834 byte reduction
    increment_key_2_and_set_value_seq_0_21bit_and_emit, // 358 instances

    // increments key[3] += 1; sets value.seq[0]; emits an entry.
    // 1685 instances
    increment_key_3_and_set_value_seq_0_2bit_and_emit, // 978 instances, 2323 byte reduction
    increment_key_3_and_set_value_seq_0_8bit_and_emit, // 269 instances, 437 byte reduction
    increment_key_3_and_set_value_seq_0_21bit_and_emit, // 438 instances

    // Sets the key and value.seq registers, then emit an entry. This is used when no other smaller
    // opcode is sufficient.
    // 1531 instances
    set_key_and_value_seq_2bit_and_emit, // 732 instances, 3358 byte reduction
    set_key_and_value_seq_8bit_and_emit, // 297 instances, 1026 byte reduction
    set_key_and_value_seq_21bit_and_emit, // 502 instances

    // increments key[1] += 1; sets value.seq[0]; emits an entry.
    // 177 instances, responsible for an 764 byte reduction
    increment_key_1_and_set_value_seq_0_and_emit,

    // increments key[1] += 1; sets value.seq[0]; sets value.seq[1]; emits an entry.
    // 108 instances, responsible for an 203 byte reduction
    increment_key_1_and_set_value_seq_0_1_and_emit,

    // increments key[2] += 1; sets value.seq[0]; sets value.seq[1]; emits an entry.
    // 387 instances, responsible for an 1135 byte reduction
    increment_key_2_and_set_value_seq_0_1_and_emit,

    // Sets the key and key_len registers at the same time.
    // 3 instances
    set_key_len_and_key,

    // Sets the value.form register
    // 72 instances
    set_value_form,

    // Sets the value.len register
    // 309 instances
    set_value_len,

    // Denotes the end of the opcode stream. This is so that we don't need to encode the total
    // number of opcodes in the stream up front (note also the file is bit packed: there may be
    // a few remaining zero bits at the end as padding so we need an EOF opcode rather than say
    // catching the actual file read EOF.)
    eof,
};

pub fn compressToFile(self: *DecompFile, filename: []const u8) !void {
    var out_file = try std.fs.cwd().createFile(filename, .{});
    defer out_file.close();
    return self.compressTo(out_file.writer());
}

pub fn compressTo(self: *DecompFile, writer: anytype) !void {
    var buf_writer = std.io.bufferedWriter(writer);
    var out = std.io.bitWriter(.Little, buf_writer.writer());

    // For the UDDC registers, we want one register to represent each possible value in a single
    // entry; we will emit opcodes to modify these registers into the desired form to produce a
    // real entry.
    var registers = std.mem.zeroes(Entry);

    while (self.next()) |entry| {
        // Determine what has changed between this entry and the current registers' state.
        var diff_value_form: u2 = undefined;
        const diff = entry.diff(registers, &diff_value_form);

        // If you want to analyze the difference between entries, uncomment the following:
        //std.debug.print("diff={}\n", .{diff});
        //registers = entry;
        //continue;

        // Infrequently changed: key_len, value.form, and value.len registers. Emit opcodes to
        // update them if needed.
        if (diff.key_len != 0) {
            try out.writeBits(@enumToInt(Opcode.set_key_len_and_key), @bitSizeOf(Opcode));
            try out.writeBits(entry.key_len, 3);
            _ = try out.write(entry.key[0..entry.key_len]);
        }
        if (diff_value_form != 0) {
            try out.writeBits(@enumToInt(Opcode.set_value_form), @bitSizeOf(Opcode));
            try out.writeBits(diff_value_form, @bitSizeOf(Form));
        }
        if (diff.value.len != 0) {
            try out.writeBits(@enumToInt(Opcode.set_value_len), @bitSizeOf(Opcode));
            try out.writeBits(entry.value.len, 5);
        }

        // Frequently changed: this is where the magic happens.
        var seq_0_change = diff.value.seq[0] != 0 and mem.eql(u21, diff.value.seq[1..], ([_]u21{0} ** 17)[0..]);
        var seq_0_1_change = diff.value.seq[0] != 0 and diff.value.seq[1] != 0 and mem.eql(u21, diff.value.seq[2..], ([_]u21{0} ** 16)[0..]);
        if (seq_0_change and mem.eql(u8, &diff.key, &[4]u8{ 0, 1, 0, 0 })) {
            try out.writeBits(@enumToInt(Opcode.increment_key_1_and_set_value_seq_0_and_emit), @bitSizeOf(Opcode));
            try out.writeBits(entry.value.seq[0], 21);
        } else if (seq_0_change and mem.eql(u8, &diff.key, &[4]u8{ 0, 0, 1, 0 })) {
            // Within this category, of all diff.value.seq[0] values:
            // * 41% fit in 2 bits.
            // * 90% fit in 6 bits.
            var fits_2 = true;
            var fits_12 = true;
            for (diff.value.seq[0..entry.value.len]) |s| {
                if (s >= (1 << 2)) {
                    fits_2 = false;
                }
                if (s >= (1 << 12)) {
                    fits_12 = false;
                }
            }
            if (fits_2) {
                try out.writeBits(@enumToInt(Opcode.increment_key_2_and_set_value_seq_0_2bit_and_emit), @bitSizeOf(Opcode));
                try out.writeBits(diff.value.seq[0], 2);
            } else if (fits_12) {
                try out.writeBits(@enumToInt(Opcode.increment_key_2_and_set_value_seq_0_12bit_and_emit), @bitSizeOf(Opcode));
                try out.writeBits(diff.value.seq[0], 12);
            } else {
                try out.writeBits(@enumToInt(Opcode.increment_key_2_and_set_value_seq_0_21bit_and_emit), @bitSizeOf(Opcode));
                try out.writeBits(diff.value.seq[0], 21);
            }
        } else if (seq_0_change and mem.eql(u8, &diff.key, &[4]u8{ 0, 0, 0, 1 })) {
            // Within this category, of all diff.value.seq[0] values:
            // * 58% fit in 2 bits.
            // * 80% fit in 4 bits.
            var fits_2 = true;
            var fits_8 = true;
            for (diff.value.seq[0..entry.value.len]) |s| {
                if (s >= (1 << 2)) {
                    fits_2 = false;
                }
                if (s >= (1 << 8)) {
                    fits_8 = false;
                }
            }
            if (fits_2) {
                try out.writeBits(@enumToInt(Opcode.increment_key_3_and_set_value_seq_0_2bit_and_emit), @bitSizeOf(Opcode));
                try out.writeBits(diff.value.seq[0], 2);
            } else if (fits_8) {
                try out.writeBits(@enumToInt(Opcode.increment_key_3_and_set_value_seq_0_8bit_and_emit), @bitSizeOf(Opcode));
                try out.writeBits(diff.value.seq[0], 8);
            } else {
                try out.writeBits(@enumToInt(Opcode.increment_key_3_and_set_value_seq_0_21bit_and_emit), @bitSizeOf(Opcode));
                try out.writeBits(diff.value.seq[0], 21);
            }
        } else if (seq_0_1_change and mem.eql(u8, &diff.key, &[4]u8{ 0, 1, 0, 0 })) {
            try out.writeBits(@enumToInt(Opcode.increment_key_1_and_set_value_seq_0_1_and_emit), @bitSizeOf(Opcode));
            try out.writeBits(entry.value.seq[0], 21);
            try out.writeBits(entry.value.seq[1], 21);
        } else if (seq_0_1_change and mem.eql(u8, &diff.key, &[4]u8{ 0, 0, 1, 0 })) {
            try out.writeBits(@enumToInt(Opcode.increment_key_2_and_set_value_seq_0_1_and_emit), @bitSizeOf(Opcode));
            try out.writeBits(entry.value.seq[0], 21);
            try out.writeBits(entry.value.seq[1], 21);
        } else {
            // Within this category, of all diff.value.seq[0..] values:
            // * 60% fit in 2 bits.
            // * 84% fit in 8 bits.
            var fits_2 = true;
            var fits_8 = true;
            for (diff.value.seq[0..entry.value.len]) |s| {
                if (s >= (1 << 2)) {
                    fits_2 = false;
                }
                if (s >= (1 << 8)) {
                    fits_8 = false;
                }
            }

            if (fits_2) {
                try out.writeBits(@enumToInt(Opcode.set_key_and_value_seq_2bit_and_emit), @bitSizeOf(Opcode));
                _ = try out.write(entry.key[0..entry.key_len]);
                for (diff.value.seq[0..entry.value.len]) |s| try out.writeBits(s, 2);
            } else if (fits_8) {
                try out.writeBits(@enumToInt(Opcode.set_key_and_value_seq_8bit_and_emit), @bitSizeOf(Opcode));
                _ = try out.write(entry.key[0..entry.key_len]);
                for (diff.value.seq[0..entry.value.len]) |s| try out.writeBits(s, 8);
            } else {
                try out.writeBits(@enumToInt(Opcode.set_key_and_value_seq_21bit_and_emit), @bitSizeOf(Opcode));
                _ = try out.write(entry.key[0..entry.key_len]);
                for (diff.value.seq[0..entry.value.len]) |s| try out.writeBits(s, 21);
            }
        }

        registers = entry;
    }
    try out.writeBits(@enumToInt(Opcode.eof), @bitSizeOf(Opcode));
    try out.flushBits();
    try buf_writer.flush();
}

pub fn decompressFile(allocator: mem.Allocator, filename: []const u8) !DecompFile {
    var in_file = try std.fs.cwd().openFile(filename, .{});
    defer in_file.close();
    return decompress(allocator, in_file.reader());
}

pub fn decompress(allocator: mem.Allocator, reader: anytype) !DecompFile {
    var buf_reader = std.io.bufferedReader(reader);
    var in = std.io.bitReader(.Little, buf_reader.reader());
    var entries = std.ArrayList(Entry).init(allocator);

    // For the UDDC registers, we want one register to represent each possible value in a single
    // entry; each opcode we read will modify these registers so we can emit a value.
    var registers = std.mem.zeroes(Entry);

    while (true) {
        // Read a single operation.
        var op = @intToEnum(Opcode, try in.readBitsNoEof(std.meta.Tag(Opcode), @bitSizeOf(Opcode)));

        // If you want to inspect the # of different ops in a stream, uncomment this:
        //std.debug.print("{}\n", .{op});

        // Execute the operation.
        switch (op) {
            .increment_key_2_and_set_value_seq_0_2bit_and_emit => {
                registers.key[2] += 1;
                registers.value.seq[0] +%= try in.readBitsNoEof(u21, 2);
                try entries.append(registers);
            },
            .increment_key_2_and_set_value_seq_0_12bit_and_emit => {
                registers.key[2] += 1;
                registers.value.seq[0] +%= try in.readBitsNoEof(u21, 12);
                try entries.append(registers);
            },
            .increment_key_2_and_set_value_seq_0_21bit_and_emit => {
                registers.key[2] += 1;
                registers.value.seq[0] +%= try in.readBitsNoEof(u21, 21);
                try entries.append(registers);
            },

            .increment_key_3_and_set_value_seq_0_2bit_and_emit => {
                registers.key[3] += 1;
                registers.value.seq[0] +%= try in.readBitsNoEof(u21, 2);
                try entries.append(registers);
            },
            .increment_key_3_and_set_value_seq_0_8bit_and_emit => {
                registers.key[3] += 1;
                registers.value.seq[0] +%= try in.readBitsNoEof(u21, 8);
                try entries.append(registers);
            },
            .increment_key_3_and_set_value_seq_0_21bit_and_emit => {
                registers.key[3] += 1;
                registers.value.seq[0] +%= try in.readBitsNoEof(u21, 21);
                try entries.append(registers);
            },

            .set_key_and_value_seq_2bit_and_emit => {
                _ = try in.read(registers.key[0..registers.key_len]);
                var i: usize = 0;
                while (i < registers.value.len) : (i += 1) registers.value.seq[i] +%= try in.readBitsNoEof(u21, 2);
                while (i < registers.value.seq.len) : (i += 1) registers.value.seq[i] = 0;
                try entries.append(registers);
            },
            .set_key_and_value_seq_8bit_and_emit => {
                _ = try in.read(registers.key[0..registers.key_len]);
                var i: usize = 0;
                while (i < registers.value.len) : (i += 1) registers.value.seq[i] +%= try in.readBitsNoEof(u21, 8);
                while (i < registers.value.seq.len) : (i += 1) registers.value.seq[i] = 0;
                try entries.append(registers);
            },
            .set_key_and_value_seq_21bit_and_emit => {
                _ = try in.read(registers.key[0..registers.key_len]);
                var i: usize = 0;
                while (i < registers.value.len) : (i += 1) registers.value.seq[i] +%= try in.readBitsNoEof(u21, 21);
                while (i < registers.value.seq.len) : (i += 1) registers.value.seq[i] = 0;
                try entries.append(registers);
            },

            .increment_key_1_and_set_value_seq_0_and_emit => {
                registers.key[1] += 1;
                registers.value.seq[0] = try in.readBitsNoEof(u21, 21);
                try entries.append(registers);
            },
            .increment_key_1_and_set_value_seq_0_1_and_emit => {
                registers.key[1] += 1;
                registers.value.seq[0] = try in.readBitsNoEof(u21, 21);
                registers.value.seq[1] = try in.readBitsNoEof(u21, 21);
                try entries.append(registers);
            },
            .increment_key_2_and_set_value_seq_0_1_and_emit => {
                registers.key[2] += 1;
                registers.value.seq[0] = try in.readBitsNoEof(u21, 21);
                registers.value.seq[1] = try in.readBitsNoEof(u21, 21);
                try entries.append(registers);
            },
            .set_key_len_and_key => {
                registers.key_len = try in.readBitsNoEof(usize, 3);
                _ = try in.read(registers.key[0..registers.key_len]);
            },
            .set_value_form => {
                registers.value.form = @intToEnum(Form, @enumToInt(registers.value.form) +% try in.readBitsNoEof(std.meta.Tag(Form), @bitSizeOf(Form)));
            },
            .set_value_len => {
                registers.value.len = try in.readBitsNoEof(usize, 5);
            },
            .eof => break,
        }
    }
    return DecompFile{ .iter = 0, .entries = entries };
}

test "parse" {
    const allocator = testing.allocator;
    var file = try parseFile(allocator, "src/data/ucd/UnicodeData.txt");
    defer file.deinit();
    while (file.next()) |entry| {
        _ = entry;
    }
}

test "compression_is_lossless" {
    const allocator = testing.allocator;

    // Compress UnicodeData.txt -> Decompositions.bin
    var file = try parseFile(allocator, "src/data/ucd/UnicodeData.txt");
    defer file.deinit();
    try file.compressToFile("src/data/ucd/Decompositions.bin");

    // Reset the raw file iterator.
    file.iter = 0;

    // Decompress the file.
    var decompressed = try decompressFile(allocator, "src/data/ucd/Decompositions.bin");
    defer decompressed.deinit();
    while (file.next()) |expected| {
        var actual = decompressed.next().?;
        try testing.expectEqual(expected, actual);
    }
}
