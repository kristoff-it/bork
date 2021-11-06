const std = @import("std");

const component = enum { h, m, s };

pub fn parseTime(time: []const u8) !i64 {
    var total_seconds: i64 = 0;
    var current: component = .h;
    var searching_digits = true;
    var start: usize = 0;
    var i: usize = 0;
    while (i < time.len) : (i += 1) {
        if (time[i] >= '0' and time[i] <= '9') {
            searching_digits = true;
            continue;
        }

        searching_digits = false;

        const number = try std.fmt.parseInt(i64, time[start..i], 10);
        start = i + 1;

        // Searching for h, m, s
        switch (time[i]) {
            else => return error.ParseError,
            'h' => {
                if (current != .h) {
                    return error.ParseError;
                }

                total_seconds += number * 60 * 60;
                current = .m;
            },
            'm' => {
                if (current == .s) {
                    return error.ParseError;
                }

                total_seconds += number * 60;
                current = .s;
            },

            's' => {
                if (i + 1 != time.len) {
                    return error.ParseError;
                }
                total_seconds += number;
            },
        }
    }

    if (searching_digits) return error.ParseError;

    return total_seconds;
}

test {
    try std.testing.expectError(error.ParseError, parseTime("1"));
    try std.testing.expectEqual(parseTime("10m"), 600);
}
