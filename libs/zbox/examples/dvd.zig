const std = @import("std");
const display = @import("zbox");
const options = @import("build_options");

pub usingnamespace @import("log_handler.zig");

const dvd_text: []const u8 =
    \\ ## #   ###
    \\ # # # # # #
    \\ # # # # # #
    \\ # #  #  # #
    \\ ##   #  ##
    \\
    \\ ##########
    \\#####  #####
    \\ ##########
;
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var alloc = &arena.allocator;

    // initialize the display with stdin/out
    try display.init(alloc);
    defer display.deinit();

    // die on ctrl+C
    try display.handleSignalInput();

    // load our cool 'image'
    var dvd_logo = try display.Buffer.init(alloc, 9, 13);
    defer dvd_logo.deinit();
    var logo_cursor = dvd_logo.cursorAt(0, 0);
    try logo_cursor.writer().writeAll(dvd_text);

    //setup our drawing buffer
    var size = try display.size();

    var output = try display.Buffer.init(alloc, size.height, size.width);
    defer output.deinit();

    // variables for tracking the movement of the logo
    var x: isize = 0;
    var x_vel: isize = 1;
    var y: isize = 0;
    var y_vel: isize = 1;

    while (true) {

        // update the size of output buffer
        size = try display.size();
        try output.resize(size.height, size.width);

        // draw our dvd logo
        output.clear();
        output.blit(dvd_logo, y, x);
        try display.push(output);

        // update logo position by velocity
        x += x_vel;
        y += y_vel;

        // change our velocities if we are running into a wall
        if ((x_vel < 0 and x < 0) or
            (x_vel > 0 and @intCast(isize, dvd_logo.width) + x >= size.width))
            x_vel *= -1;

        if ((y_vel < 0 and y < 0) or
            (y_vel > 0 and @intCast(isize, dvd_logo.height) + y >= size.height))
            y_vel *= -1;

        std.os.nanosleep(0, 80_000_000);
    }
}

test "static anal" {
    std.meta.refAllDecls(@This());
}
