const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const os = std.os;
const path = std.fs.path;
const process = std.process;
const testing = std.testing;

const AllKeysFile = @import("collator/AllKeysFile.zig");
const DecompFile = @import("normalizer/DecompFile.zig");

pub fn main() anyerror!void {
    const allocator = testing.allocator;
    var args = process.args();
    _ = args.skip(); // skip program name.
    if (args.nextPosix()) |arg| {
        if (mem.eql(u8, path.basename(arg), "allkeys.txt")) {
            // Compress allkeys.txt -> allkeys.bin
            var file = try AllKeysFile.parseFile(allocator, arg);
            defer file.deinit();
            try file.compressToFile("allkeys.bin");
        } else if (mem.eql(u8, path.basename(arg), "UnicodeData.txt")) {
            var file = try DecompFile.parseFile(allocator, arg);
            defer file.deinit();
            try file.compressToFile("Decompositions.bin");
        } else {
            // Unsupported filename.
            debug.print("Unsupported file name: {s}\n", .{arg});
            debug.print("usage: uddc (<path_to_allkeys.txt> | <path_to_UnicodeData.txt>)\n", .{});
            os.exit(2);
        }
    } else {
        // No file specified.
        debug.print("usage: uddc (<path_to_allkeys.txt> | <path_to_UnicodeData.txt>)\n", .{});
        os.exit(1);
    }
}
