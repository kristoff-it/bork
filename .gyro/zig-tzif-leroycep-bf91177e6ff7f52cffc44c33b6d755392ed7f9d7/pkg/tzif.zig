const std = @import("std");
const testing = std.testing;

const log = std.log.scoped(.tzif);

pub const TimeZone = struct {
    allocator: *std.mem.Allocator,
    version: Version,
    transitionTimes: []i64,
    transitionTypes: []u8,
    localTimeTypes: []LocalTimeType,
    designations: []u8,
    leapSeconds: []LeapSecond,
    transitionIsStd: []bool,
    transitionIsUT: []bool,
    string: []u8,
    posixTZ: ?PosixTZ,

    pub fn deinit(this: @This()) void {
        this.allocator.free(this.transitionTimes);
        this.allocator.free(this.transitionTypes);
        this.allocator.free(this.localTimeTypes);
        this.allocator.free(this.designations);
        this.allocator.free(this.leapSeconds);
        this.allocator.free(this.transitionIsStd);
        this.allocator.free(this.transitionIsUT);
        this.allocator.free(this.string);
    }

    fn findTransitionTime(this: @This(), utc: i64) ?usize {
        var left: usize = 0;
        var right: usize = this.transitionTimes.len;

        while (left < right) {
            // Avoid overflowing in the midpoint calculation
            const mid = left + (right - left) / 2;
            // Compare the key with the midpoint element
            if (this.transitionTimes[mid] == utc) {
                if (mid + 1 < this.transitionTimes.len) {
                    return mid;
                } else {
                    return null;
                }
            } else if (this.transitionTimes[mid] > utc) {
                right = mid;
            } else if (this.transitionTimes[mid] < utc) {
                left = mid + 1;
            }
        }

        if (right == this.transitionTimes.len) {
            return null;
        } else if (right > 0) {
            return right - 1;
        } else {
            return 0;
        }
    }

    pub const ConversionResult = struct {
        timestamp: i64,
        offset: i32,
        dst: bool,
        designation: []const u8,
    };

    pub fn localTimeFromUTC(this: @This(), utc: i64) ?ConversionResult {
        if (this.findTransitionTime(utc)) |idx| {
            const transition_type = this.transitionTypes[idx];
            const local_time_type = this.localTimeTypes[transition_type];

            var designation = this.designations[local_time_type.idx .. this.designations.len - 1];
            for (designation) |c, i| {
                if (c == 0) {
                    designation = designation[0..i];
                    break;
                }
            }

            return ConversionResult{
                .timestamp = utc + local_time_type.utoff,
                .offset = local_time_type.utoff,
                .dst = local_time_type.dst,
                .designation = designation,
            };
        } else if (this.posixTZ) |posixTZ| {
            // Base offset on the TZ string
            const offset_res = posixTZ.offset(utc);
            return ConversionResult{
                .timestamp = utc - offset_res.offset,
                .offset = offset_res.offset,
                .dst = offset_res.dst,
                .designation = offset_res.designation,
            };
        } else {
            return null;
        }
    }
};

pub const Version = enum(u8) {
    V1 = 0,
    V2 = '2',
    V3 = '3',

    pub fn timeSize(this: @This()) u32 {
        return switch (this) {
            .V1 => 4,
            .V2, .V3 => 8,
        };
    }

    pub fn leapSize(this: @This()) u32 {
        return this.timeSize() + 4;
    }

    pub fn string(this: @This()) []const u8 {
        return switch (this) {
            .V1 => "1",
            .V2 => "2",
            .V3 => "3",
        };
    }
};

pub const LocalTimeType = struct {
    utoff: i32,
    /// Indicates whether this local time is Daylight Saving Time
    dst: bool,
    idx: u8,
};

pub const LeapSecond = struct {
    occur: i64,
    corr: i32,
};

/// This is based on Posix definition of the TZ environment variable
pub const PosixTZ = struct {
    std: []const u8,
    std_offset: i32,
    dst: ?[]const u8 = null,
    /// This field is ignored when dst is null
    dst_offset: i32 = 0,
    dst_range: ?struct {
        start: Rule,
        end: Rule,
    } = null,

    pub const Rule = union(enum) {
        JulianDay: struct {
            /// 1 <= day <= 365. Leap days are not counted and are impossible to refer to
            /// 0 <= day <= 365. Leap days are counted, and can be referred to.
            oneBased: bool,
            day: u16,
            time: i32,
        },
        MonthWeekDay: struct {
            /// 1 <= m <= 12
            m: u8,
            /// 1 <= n <= 5
            n: u8,
            /// 0 <= n <= 6
            d: u8,
            time: i32,
        },

        pub fn toSecs(this: @This(), year: i32) i64 {
            var is_leap: bool = undefined;
            var t = year_to_secs(year, &is_leap);

            switch (this) {
                .JulianDay => |j| {
                    var x: i64 = j.day;
                    if (j.oneBased and (x < 60 or !is_leap)) x -= 1;
                    t += std.time.s_per_day * x;
                    t += j.time;
                },
                .MonthWeekDay => |mwd| {
                    t += month_to_secs(mwd.m - 1, is_leap);
                    const wday = @divFloor(@mod((t + 4 * std.time.s_per_day), (7 * std.time.s_per_day)), std.time.s_per_day);
                    var days = mwd.d - wday;
                    if (days < 0) days += 7;
                    var n = mwd.n;
                    if (mwd.n == 5 and days + 28 >= days_in_month(mwd.m, is_leap)) n = 4;
                    t += std.time.s_per_day * (days + 7 * (n - 1));
                    t += mwd.time;
                },
            }
            return t;
        }
    };

    pub const OffsetResult = struct {
        offset: i32,
        designation: []const u8,
        dst: bool,
    };

    pub fn offset(this: @This(), utc: i64) OffsetResult {
        if (this.dst == null) {
            std.debug.assert(this.dst_range == null);
            return .{ .offset = this.std_offset, .designation = this.std, .dst = false };
        }
        if (this.dst_range) |range| {
            const utc_year = secs_to_year(utc);
            const start_dst = range.start.toSecs(utc_year);
            const end_dst = range.end.toSecs(utc_year);
            if (start_dst < end_dst) {
                if (utc >= start_dst and utc < end_dst) {
                    return .{ .offset = this.dst_offset, .designation = this.dst.?, .dst = true };
                } else {
                    return .{ .offset = this.std_offset, .designation = this.std, .dst = false };
                }
            } else {
                if (utc >= end_dst and utc < start_dst) {
                    return .{ .offset = this.dst_offset, .designation = this.dst.?, .dst = true };
                } else {
                    return .{ .offset = this.std_offset, .designation = this.std, .dst = false };
                }
            }
        } else {
            return .{ .offset = this.std_offset, .designation = this.std, .dst = false };
        }
    }
};

fn days_in_month(m: u8, is_leap: bool) i32 {
    if (m == 2) {
        return 28 + @as(i32, @boolToInt(is_leap));
    } else {
        return 30 + ((@as(i32, 0xad5) >> @intCast(u5, m - 1)) & 1);
    }
}

fn month_to_secs(m: u8, is_leap: bool) i32 {
    const d = std.time.s_per_day;
    const secs_though_month = [12]i32{
        0 * d,   31 * d,  59 * d,  90 * d,
        120 * d, 151 * d, 181 * d, 212 * d,
        243 * d, 273 * d, 304 * d, 334 * d,
    };
    var t = secs_though_month[m];
    if (is_leap and m >= 2) t += d;
    return t;
}

fn secs_to_year(secs: i64) i32 {
    // Copied from MUSL
    // TODO: make more efficient?
    var _is_leap: bool = undefined;
    var y = @intCast(i32, @divFloor(secs, 31556952) + 70);
    while (year_to_secs(y, &_is_leap) > secs) y -= 1;
    while (year_to_secs(y + 1, &_is_leap) < secs) y += 1;
    return y;
}

fn year_to_secs(year: i32, is_leap: *bool) i64 {
    if (year - 2 <= 136) {
        const y = year;
        var leaps = (y - 68) >> 2;
        if (((y - 68) & 3) != 0) {
            leaps -= 1;
            is_leap.* = true;
        } else is_leap.* = false;
        return 31536000 * (y - 70) + std.time.s_per_day * leaps;
    }

    is_leap.* = false;
    var centuries: i64 = undefined;
    var leaps: i64 = undefined;
    var cycles = @divFloor((year - 100), 400);
    var rem = @mod((year - 100), 400);
    if (rem < 0) {
        cycles -= 1;
        rem += 400;
    }
    if (rem != 0) {
        is_leap.* = true;
        centuries = 0;
        leaps = 0;
    } else {
        if (rem >= 200) {
            if (rem >= 300) {
                centuries = 3;
                rem -= 300;
            } else {
                centuries = 2;
                rem -= 200;
            }
        } else {
            if (rem >= 100) {
                centuries = 1;
                rem -= 100;
            } else {
                centuries = 0;
            }
        }
        if (rem != 0) {
            is_leap.* = false;
            leaps = 0;
        } else {
            leaps = @divFloor(rem, 4);
            rem = @mod(rem, 4);
            is_leap.* = rem != 0;
        }
    }

    leaps += 97 * cycles + 24 * centuries - @boolToInt(is_leap.*);

    return (year - 100) * 31536000 + leaps * std.time.s_per_day + 946684800 + std.time.s_per_day;
}

const TIME_TYPE_SIZE = 6;

pub const TZifHeader = struct {
    version: Version,
    isutcnt: u32,
    isstdcnt: u32,
    leapcnt: u32,
    timecnt: u32,
    typecnt: u32,
    charcnt: u32,

    pub fn dataSize(this: @This(), dataBlockVersion: Version) u32 {
        return this.timecnt * dataBlockVersion.timeSize() +
            this.timecnt +
            this.typecnt * TIME_TYPE_SIZE +
            this.charcnt +
            this.leapcnt * dataBlockVersion.leapSize() +
            this.isstdcnt +
            this.isutcnt;
    }
};

pub fn parseHeader(reader: anytype, seekableStream: anytype) !TZifHeader {
    var magic_buf: [4]u8 = undefined;
    try reader.readNoEof(&magic_buf);
    if (!std.mem.eql(u8, "TZif", &magic_buf)) {
        log.warn("File is missing magic string 'TZif'", .{});
        return error.InvalidFormat;
    }

    // Check verison
    const version = reader.readEnum(Version, .Little) catch |err| switch (err) {
        error.InvalidValue => return error.UnsupportedVersion,
        else => |e| return e,
    };
    if (version == .V1) {
        return error.UnsupportedVersion;
    }

    // Seek past reserved bytes
    try seekableStream.seekBy(15);

    return TZifHeader{
        .version = version,
        .isutcnt = try reader.readInt(u32, .Big),
        .isstdcnt = try reader.readInt(u32, .Big),
        .leapcnt = try reader.readInt(u32, .Big),
        .timecnt = try reader.readInt(u32, .Big),
        .typecnt = try reader.readInt(u32, .Big),
        .charcnt = try reader.readInt(u32, .Big),
    };
}

fn hhmmss_offset_to_s(_string: []const u8, idx: *usize) !i32 {
    var string = _string;
    var sign: i2 = 1;
    if (string[0] == '+') {
        sign = 1;
        string = string[1..];
        idx.* += 1;
    } else if (string[0] == '-') {
        sign = -1;
        string = string[1..];
        idx.* += 1;
    }

    for (string) |c, i| {
        if (!(std.ascii.isDigit(c) or c == ':')) {
            string = string[0..i];
            break;
        }
        idx.* += 1;
    }

    var result: i32 = 0;

    var segment_iter = std.mem.split(u8, string, ":");
    const hour_string = segment_iter.next() orelse return error.EmptyString;
    const hours = try std.fmt.parseInt(u32, hour_string, 10);
    if (hours > 167) {
        log.warn("too many hours! {}", .{hours});
        return error.InvalidFormat;
    }
    result += std.time.s_per_hour * @intCast(i32, hours);

    if (segment_iter.next()) |minute_string| {
        const minutes = try std.fmt.parseInt(u32, minute_string, 10);
        if (minutes > 59) return error.InvalidFormat;
        result += std.time.s_per_min * @intCast(i32, minutes);
    }

    if (segment_iter.next()) |second_string| {
        const seconds = try std.fmt.parseInt(u8, second_string, 10);
        if (seconds > 59) return error.InvalidFormat;
        result += seconds;
    }

    return result * sign;
}

fn parsePosixTZ_rule(_string: []const u8) !PosixTZ.Rule {
    var string = _string;
    if (string.len < 2) return error.InvalidFormat;

    const time: i32 = if (std.mem.indexOf(u8, string, "/")) |start_of_time| parse_time: {
        var _i: usize = 0;
        // This is ugly, should stick with one unit or the other for hhmmss offsets
        const time = try hhmmss_offset_to_s(string[start_of_time + 1 ..], &_i);
        string = string[0..start_of_time];
        break :parse_time time;
    } else 2 * std.time.s_per_hour;

    if (string[0] == 'J') {
        const julian_day1 = try std.fmt.parseInt(u16, string[1..], 10);
        if (julian_day1 < 1 or julian_day1 > 365) return error.InvalidFormat;
        return PosixTZ.Rule{ .JulianDay = .{ .oneBased = true, .day = julian_day1, .time = time } };
    } else if (std.ascii.isDigit(string[0])) {
        const julian_day0 = try std.fmt.parseInt(u16, string[0..], 10);
        if (julian_day0 > 365) return error.InvalidFormat;
        return PosixTZ.Rule{ .JulianDay = .{ .oneBased = false, .day = julian_day0, .time = time } };
    } else if (string[0] == 'M') {
        var split_iter = std.mem.split(u8, string[1..], ".");
        const m_str = split_iter.next() orelse return error.InvalidFormat;
        const n_str = split_iter.next() orelse return error.InvalidFormat;
        const d_str = split_iter.next() orelse return error.InvalidFormat;

        const m = try std.fmt.parseInt(u8, m_str, 10);
        const n = try std.fmt.parseInt(u8, n_str, 10);
        const d = try std.fmt.parseInt(u8, d_str, 10);

        if (m < 1 or m > 12) return error.InvalidFormat;
        if (n < 1 or n > 5) return error.InvalidFormat;
        if (d > 6) return error.InvalidFormat;

        return PosixTZ.Rule{ .MonthWeekDay = .{ .m = m, .n = n, .d = d, .time = time } };
    } else {
        return error.InvalidFormat;
    }
}

fn parsePosixTZ_designation(string: []const u8, idx: *usize) ![]const u8 {
    var quoted = string[idx.*] == '<';
    if (quoted) idx.* += 1;
    var start = idx.*;
    while (idx.* < string.len) : (idx.* += 1) {
        if ((quoted and string[idx.*] == '>') or
            (!quoted and !std.ascii.isAlpha(string[idx.*])))
        {
            const designation = string[start..idx.*];
            if (quoted) idx.* += 1;
            return designation;
        }
    }
    return error.InvalidFormat;
}

pub fn parsePosixTZ(string: []const u8) !PosixTZ {
    var result = PosixTZ{ .std = undefined, .std_offset = undefined };
    var idx: usize = 0;

    result.std = try parsePosixTZ_designation(string, &idx);

    result.std_offset = try hhmmss_offset_to_s(string[idx..], &idx);
    if (idx >= string.len) {
        return result;
    }

    if (string[idx] != ',') {
        result.dst = try parsePosixTZ_designation(string, &idx);

        if (idx < string.len and string[idx] != ',') {
            result.dst_offset = try hhmmss_offset_to_s(string[idx..], &idx);
        } else {
            result.dst_offset = result.std_offset + std.time.s_per_hour;
        }

        if (idx >= string.len) {
            return result;
        }
    }

    std.debug.assert(string[idx] == ',');
    idx += 1;

    if (std.mem.indexOf(u8, string[idx..], ",")) |_end_of_start_rule| {
        const end_of_start_rule = idx + _end_of_start_rule;
        result.dst_range = .{
            .start = try parsePosixTZ_rule(string[idx..end_of_start_rule]),
            .end = try parsePosixTZ_rule(string[end_of_start_rule + 1 ..]),
        };
    } else {
        return error.InvalidFormat;
    }

    return result;
}

pub fn parse(allocator: *std.mem.Allocator, reader: anytype, seekableStream: anytype) !TimeZone {
    const v1_header = try parseHeader(reader, seekableStream);
    try seekableStream.seekBy(v1_header.dataSize(.V1));

    const v2_header = try parseHeader(reader, seekableStream);

    // Parse transition times
    var transition_times = try allocator.alloc(i64, v2_header.timecnt);
    errdefer allocator.free(transition_times);
    {
        var prev: i64 = -(2 << 59); // Earliest time supported, this is earlier than the big bang
        var i: usize = 0;
        while (i < transition_times.len) : (i += 1) {
            transition_times[i] = try reader.readInt(i64, .Big);
            if (transition_times[i] <= prev) {
                return error.InvalidFormat;
            }
            prev = transition_times[i];
        }
    }

    // Parse transition types
    var transition_types = try allocator.alloc(u8, v2_header.timecnt);
    errdefer allocator.free(transition_types);
    try reader.readNoEof(transition_types);
    for (transition_types) |transition_type| {
        if (transition_type >= v2_header.typecnt) {
            return error.InvalidFormat; // a transition type index is out of bounds
        }
    }

    // Parse local time type records
    var local_time_types = try allocator.alloc(LocalTimeType, v2_header.typecnt);
    errdefer allocator.free(local_time_types);
    {
        var i: usize = 0;
        while (i < local_time_types.len) : (i += 1) {
            local_time_types[i].utoff = try reader.readInt(i32, .Big);
            local_time_types[i].dst = switch (try reader.readByte()) {
                0 => false,
                1 => true,
                else => return error.InvalidFormat,
            };

            local_time_types[i].idx = try reader.readByte();
            if (local_time_types[i].idx >= v2_header.charcnt) {
                return error.InvalidFormat;
            }
        }
    }

    // Read designations
    var time_zone_designations = try allocator.alloc(u8, v2_header.charcnt);
    errdefer allocator.free(time_zone_designations);
    try reader.readNoEof(time_zone_designations);

    // Parse leap seconds records
    var leap_seconds = try allocator.alloc(LeapSecond, v2_header.leapcnt);
    errdefer allocator.free(leap_seconds);
    {
        var i: usize = 0;
        while (i < leap_seconds.len) : (i += 1) {
            leap_seconds[i].occur = try reader.readInt(i64, .Big);
            if (i == 0 and leap_seconds[i].occur < 0) {
                return error.InvalidFormat;
            } else if (i != 0 and leap_seconds[i].occur - leap_seconds[i - 1].occur < 2419199) {
                return error.InvalidFormat; // There must be at least 28 days worth of seconds between leap seconds
            }

            leap_seconds[i].corr = try reader.readInt(i32, .Big);
            if (i == 0 and (leap_seconds[0].corr != 1 and leap_seconds[0].corr != -1)) {
                log.warn("First leap second correction is not 1 or -1: {}", .{leap_seconds[0]});
                return error.InvalidFormat;
            } else if (i != 0) {
                const diff = leap_seconds[i].corr - leap_seconds[i - 1].corr;
                if (diff != 1 and diff != -1) {
                    log.warn("Too large of a difference between leap seconds: {}", .{diff});
                    return error.InvalidFormat;
                }
            }
        }
    }

    // Parse standard/wall indicators
    var transition_is_std = try allocator.alloc(bool, v2_header.isstdcnt);
    errdefer allocator.free(transition_is_std);
    {
        var i: usize = 0;
        while (i < transition_is_std.len) : (i += 1) {
            transition_is_std[i] = switch (try reader.readByte()) {
                1 => true,
                0 => false,
                else => return error.InvalidFormat,
            };
        }
    }

    // Parse UT/local indicators
    var transition_is_ut = try allocator.alloc(bool, v2_header.isutcnt);
    errdefer allocator.free(transition_is_ut);
    {
        var i: usize = 0;
        while (i < transition_is_ut.len) : (i += 1) {
            transition_is_ut[i] = switch (try reader.readByte()) {
                1 => true,
                0 => false,
                else => return error.InvalidFormat,
            };
        }
    }

    // Parse TZ string from footer
    if ((try reader.readByte()) != '\n') return error.InvalidFormat;
    const tz_string = try reader.readUntilDelimiterAlloc(allocator, '\n', 60);
    errdefer allocator.free(tz_string);

    const posixTZ: ?PosixTZ = if (tz_string.len > 0)
        try parsePosixTZ(tz_string)
    else
        null;

    return TimeZone{
        .allocator = allocator,
        .version = v2_header.version,
        .transitionTimes = transition_times,
        .transitionTypes = transition_types,
        .localTimeTypes = local_time_types,
        .designations = time_zone_designations,
        .leapSeconds = leap_seconds,
        .transitionIsStd = transition_is_std,
        .transitionIsUT = transition_is_ut,
        .string = tz_string,
        .posixTZ = posixTZ,
    };
}

pub fn parseFile(allocator: *std.mem.Allocator, path: []const u8) !TimeZone {
    const cwd = std.fs.cwd();

    const file = try cwd.openFile(path, .{});
    defer file.close();

    return parse(allocator, file.reader(), file.seekableStream());
}

test "parse invalid bytes" {
    var fbs = std.io.fixedBufferStream("dflkasjreklnlkvnalkfek");
    testing.expectError(error.InvalidFormat, parse(std.testing.allocator, fbs.reader(), fbs.seekableStream()));
}

test "parse UTC zoneinfo" {
    var fbs = std.io.fixedBufferStream(@embedFile("zoneinfo/UTC"));

    const res = try parse(std.testing.allocator, fbs.reader(), fbs.seekableStream());
    defer res.deinit();

    testing.expectEqual(Version.V2, res.version);
    testing.expectEqualSlices(i64, &[_]i64{}, res.transitionTimes);
    testing.expectEqualSlices(u8, &[_]u8{}, res.transitionTypes);
    testing.expectEqualSlices(LocalTimeType, &[_]LocalTimeType{.{ .utoff = 0, .dst = false, .idx = 0 }}, res.localTimeTypes);
    testing.expectEqualSlices(u8, "UTC\x00", res.designations);
}

test "parse Pacific/Honolulu zoneinfo and calculate local times" {
    const transition_times = [7]i64{ -2334101314, -1157283000, -1155436200, -880198200, -769395600, -765376200, -712150200 };
    const transition_types = [7]u8{ 1, 2, 1, 3, 4, 1, 5 };
    const local_time_types = [6]LocalTimeType{
        .{ .utoff = -37886, .dst = false, .idx = 0 },
        .{ .utoff = -37800, .dst = false, .idx = 4 },
        .{ .utoff = -34200, .dst = true, .idx = 8 },
        .{ .utoff = -34200, .dst = true, .idx = 12 },
        .{ .utoff = -34200, .dst = true, .idx = 16 },
        .{ .utoff = -36000, .dst = false, .idx = 4 },
    };
    const designations = "LMT\x00HST\x00HDT\x00HWT\x00HPT\x00";
    const is_std = &[6]bool{ false, false, false, false, true, false };
    const is_ut = &[6]bool{ false, false, false, false, true, false };
    const string = "HST10";

    var fbs = std.io.fixedBufferStream(@embedFile("zoneinfo/Pacific/Honolulu"));

    const res = try parse(std.testing.allocator, fbs.reader(), fbs.seekableStream());
    defer res.deinit();

    testing.expectEqual(Version.V2, res.version);
    testing.expectEqualSlices(i64, &transition_times, res.transitionTimes);
    testing.expectEqualSlices(u8, &transition_types, res.transitionTypes);
    testing.expectEqualSlices(LocalTimeType, &local_time_types, res.localTimeTypes);
    testing.expectEqualSlices(u8, designations, res.designations);
    testing.expectEqualSlices(bool, is_std, res.transitionIsStd);
    testing.expectEqualSlices(bool, is_ut, res.transitionIsUT);
    testing.expectEqualSlices(u8, string, res.string);

    {
        const conversion = res.localTimeFromUTC(-1156939200).?;
        testing.expectEqual(@as(i64, -1156973400), conversion.timestamp);
        testing.expectEqual(true, conversion.dst);
        testing.expectEqualSlices(u8, "HDT", conversion.designation);
    }
    {
        const conversion = res.localTimeFromUTC(1546300800).?;
        testing.expectEqual(@as(i64, 1546300800) - 10 * std.time.s_per_hour, conversion.timestamp);
        testing.expectEqual(false, conversion.dst);
        testing.expectEqualSlices(u8, "HST", conversion.designation);
    }
}

test "posix TZ string" {
    const result = try parsePosixTZ("MST7MDT,M3.2.0,M11.1.0");

    testing.expectEqualSlices(u8, "MST", result.std);
    testing.expectEqual(@as(i32, 25200), result.std_offset);
    testing.expectEqualSlices(u8, "MDT", result.dst.?);
    testing.expectEqual(@as(i32, 28800), result.dst_offset);
    testing.expectEqual(PosixTZ.Rule{ .MonthWeekDay = .{ .m = 3, .n = 2, .d = 0, .time = 2 * std.time.s_per_hour } }, result.dst_range.?.start);
    testing.expectEqual(PosixTZ.Rule{ .MonthWeekDay = .{ .m = 11, .n = 1, .d = 0, .time = 2 * std.time.s_per_hour } }, result.dst_range.?.end);

    testing.expectEqual(@as(i32, 25200), result.offset(1612734960).offset);
    testing.expectEqual(@as(i32, 25200), result.offset(1615712399 - 7 * std.time.s_per_hour).offset);
    testing.expectEqual(@as(i32, 28800), result.offset(1615712400 - 7 * std.time.s_per_hour).offset);
    testing.expectEqual(@as(i32, 28800), result.offset(1620453601).offset);
    testing.expectEqual(@as(i32, 28800), result.offset(1636275599 - 7 * std.time.s_per_hour).offset);
    testing.expectEqual(@as(i32, 25200), result.offset(1636275600 - 7 * std.time.s_per_hour).offset);
}
