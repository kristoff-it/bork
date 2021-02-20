const std = @import("std");
const tzif = @import("tzif");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    var successful_parse: usize = 0;
    var successful_convert: usize = 0;
    var failed_parse: usize = 0;
    var failed_convert: usize = 0;

    var walker = try std.fs.walkPath(allocator, "/usr/share/zoneinfo");
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .File) {
            if (tzif.parseFile(allocator, entry.path)) |timezone| {
                defer timezone.deinit();
                successful_parse += 1;
                const utc = std.time.timestamp();
                if (timezone.localTimeFromUTC(utc)) |conversion| {
                    successful_convert += 1;
                } else {
                    failed_convert += 1;
                    std.log.warn("Failed to convert with {s}", .{entry.path});
                }
            } else |err| {
                failed_parse += 1;
                std.log.warn("Failed to parse {s}: {}", .{ entry.path, err });
            }
        }
    }

    std.log.info("Parsed: {}/{}", .{successful_parse, successful_parse + failed_parse});
    std.log.info("Converted: {}/{}", .{successful_convert, successful_convert + failed_convert});
}
