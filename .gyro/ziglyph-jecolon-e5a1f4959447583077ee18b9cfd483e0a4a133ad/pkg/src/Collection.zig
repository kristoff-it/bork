const std = @import("std");
const io = std.io;
const mem = std.mem;

const Range = @import("record.zig").Range;
const Record = @import("record.zig").Record;
const Collection = @This();

const comp_path = "components/autogen";

allocator: *mem.Allocator,
kind: []const u8,
lo: u21,
hi: u21,
records: []Record,

pub fn init(allocator: *mem.Allocator, kind: []const u8, lo: u21, hi: u21, records: []Record) !Collection {
    return Collection{
        .allocator = allocator,
        .kind = blk: {
            var b = try allocator.alloc(u8, kind.len);
            mem.copy(u8, b, kind);
            break :blk b;
        },
        .lo = lo,
        .hi = hi,
        .records = records,
    };
}

pub fn deinit(self: *Collection) void {
    self.allocator.free(self.kind);
    self.allocator.free(self.records);
}

pub fn writeFile(self: *Collection, dir: []const u8) !void {
    const header_tpl = @embedFile("parts/collection_header_tpl.txt");

    // Prepare output files.
    const name = try self.clean_name();
    defer self.allocator.free(name);
    var dir_name = try mem.concat(self.allocator, u8, &[_][]const u8{
        comp_path,
        "/",
        dir,
    });
    defer self.allocator.free(dir_name);
    var cwd = std.fs.cwd();
    cwd.makeDir(dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var file_name = try mem.concat(self.allocator, u8, &[_][]const u8{ dir_name, "/", name, ".zig" });
    defer self.allocator.free(file_name);
    var file = try cwd.createFile(file_name, .{});
    defer file.close();
    var buf_writer = io.bufferedWriter(file.writer());
    const writer = buf_writer.writer();

    // Write data.
    _ = try writer.print(header_tpl, .{ name, self.lo, self.hi });

    for (self.records) |record| {
        switch (record) {
            .single => |cp| {
                _ = try writer.print("    if (cp == {d}) return true;\n", .{cp});
            },
            .range => |range| {
                _ = try writer.print("    if (cp >= {d} and cp <= {d}) return true;\n", .{ range.lo, range.hi });
            },
        }
    }

    _ = try writer.write("    return false;\n}");
    try buf_writer.flush();
}

fn clean_name(self: *Collection) ![]u8 {
    var name1 = try self.allocator.alloc(u8, mem.replacementSize(u8, self.kind, "_", ""));
    defer self.allocator.free(name1);
    _ = mem.replace(u8, self.kind, "_", "", name1);
    var name2 = try self.allocator.alloc(u8, mem.replacementSize(u8, name1, "-", ""));
    defer self.allocator.free(name2);
    _ = mem.replace(u8, name1, "-", "", name2);
    var name = try self.allocator.alloc(u8, mem.replacementSize(u8, name1, " ", ""));
    _ = mem.replace(u8, name2, " ", "", name);
    return name;
}
