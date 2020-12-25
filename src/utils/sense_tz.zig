const std = @import("std");
const datetime = @import("datetime");

// Cursed definitions for obtaining the user TZ.
extern fn time(?*usize) usize;
extern fn localtime(*const usize) *tm;
const tm = extern struct {
    tm_sec: c_int, // seconds,  range 0 to 59
    tm_min: c_int, // minutes, range 0 to 59
    tm_hour: c_int, // hours, range 0 to 23
    tm_mday: c_int, // day of the month, range 1 to 31
    tm_mon: c_int, // month, range 0 to 11
    tm_year: c_int, // The number of years since 1900
    tm_wday: c_int, // day of the week, range 0 to 6
    tm_yday: c_int, // day in the year, range 0 to 365
    tm_isdst: c_int, // daylight saving time
    tm_gmtoff: c_long,
    tm_zone: [*:0]const u8,
};

pub fn senseUserTZ() datetime.Timezone {
    const t = time(null);
    const local = localtime(&t);

    std.log.debug("current tz offset: {}", .{@divTrunc(local.tm_gmtoff, 60)});
    return datetime.Timezone.create("Custom", @intCast(i16, @divTrunc(local.tm_gmtoff, 60)));
}
