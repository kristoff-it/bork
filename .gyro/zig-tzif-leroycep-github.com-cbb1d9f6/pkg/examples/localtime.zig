const std = @import("std");
const tzif = @import("tzif");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    const localtime = try tzif.parseFile(allocator, "/etc/localtime");
    defer localtime.deinit();

    const now_utc = std.time.timestamp();
    const now_converted = localtime.localTimeFromUTC(now_utc) orelse {
        std.log.err("Offset is not specified for current timezone", .{});
        return;
    };

    const out = std.io.getStdOut();
    try out.writer().print("{}\n", .{now_converted.timestamp});
}
