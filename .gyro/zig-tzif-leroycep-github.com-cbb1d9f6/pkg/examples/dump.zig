const std = @import("std");
const tzif = @import("tzif");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    if (args.len != 2) {
        std.log.err("Path to TZif file is required", .{});
        return 1;
    }

    const localtime = try tzif.parseFile(allocator, args[1]);
    defer localtime.deinit();

    std.log.info("TZ string: {s}", .{localtime.string});
    std.log.info("TZif version: {s}", .{localtime.version.string()});
    std.log.info("{} transition times", .{localtime.transitionTimes.len});
    std.log.info("{} leap seconds", .{localtime.leapSeconds.len});

    return 0;
}
