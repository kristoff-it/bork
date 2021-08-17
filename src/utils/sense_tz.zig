const std = @import("std");
const datetime = @import("datetime").datetime;
const tzif = @import("tzif");

pub fn senseUserTZ(allocator: *std.mem.Allocator) !datetime.Timezone {
    const localtime = try tzif.parseFile(allocator, "/etc/localtime");
    defer localtime.deinit();

    const now_utc = std.time.timestamp();
    const now_converted = localtime.localTimeFromUTC(now_utc) orelse {
        std.log.err("Offset is not specified for current timezone", .{});
        return error.TZ;
    };

    std.log.debug("current tz offset: {d}", .{@divTrunc(now_converted.offset, 60)});
    return datetime.Timezone.create("Custom", @intCast(i16, @divTrunc(now_converted.offset, 60)));
}
