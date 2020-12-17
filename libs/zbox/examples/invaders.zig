const std = @import("std");
const display = @import("zbox");
const options = @import("build_options");
const page_allocator = std.heap.page_allocator;
const ArrayList = std.ArrayList;

pub usingnamespace @import("log_handler.zig");

const bad_char = '%';
const ship_char = '^';
const bullet_char = '.';

const bb_width = 7;
const bb_height = 3;
const baddie_block_init = [bb_height][bb_width]u8{
    .{ 1, 0, 1, 0, 1, 0, 1 },
    .{ 0, 1, 0, 1, 0, 1, 0 },
    .{ 1, 0, 1, 0, 1, 0, 1 },
};
var baddie_block = baddie_block_init;
var bb_y: usize = 0;
var bb_countdown: usize = 3;

const Bullet = struct {
    active: bool = false,
    x: usize = 0,
    y: usize = 0,
};

var bullets = [_]Bullet{.{}} ** 4;
var score: usize = 0;
const width: usize = 7;
const mid_width: usize = 4;
const height: usize = 24;
const mid_height = 11;
var ship_x: usize = 4; // center of the screen.

var state: enum {
    start,
    playing,
    win,
    lose,
} = .playing;

pub fn main() !void {
    var alloc = std.heap.page_allocator;

    // initialize the display with stdin/out
    try display.init(alloc);
    defer display.deinit();

    // ignore ctrl+C
    try display.ignoreSignalInput();
    try display.cursorHide();
    defer display.cursorShow() catch {};

    var game_display = try display.Buffer.init(alloc, height, width);
    defer game_display.deinit();

    var output = try display.Buffer.init(alloc, height, width);
    defer output.deinit();

    while (try display.nextEvent()) |e| {
        const size = try display.size();
        output.clear();
        try output.resize(size.height, size.width);

        if (size.height < height or size.width < width) {
            const row = std.math.max(0, size.height / 2);
            var cursor = output.cursorAt(row, 0);
            try cursor.writer().writeAll("display too small; resize.");
            try display.push(output);
            continue;
        }

        switch (e) {
            .left => if (ship_x > 0) {
                ship_x -= 1;
            },
            .right => if (ship_x < width - 1) {
                ship_x += 1;
            },

            .other => |data| {
                const eql = std.mem.eql;
                if (eql(u8, " ", data)) {
                    std.log.scoped(.invaders).debug("pyoo", .{});
                    for (bullets) |*bullet| if (!bullet.active) {
                        bullet.active = true;
                        bullet.y = height - 1;
                        bullet.x = ship_x;
                        break;
                    };
                }
            },

            .escape => return,
            else => {},
        }

        game_display.clear();

        game_display.cellRef(height - 1, ship_x).char = ship_char;

        for (bullets) |*bullet| {
            if (bullet.active) {
                if (bullet.y > 0) bullet.y -= 1;
                if (bullet.y == 0) {
                    bullet.active = false;
                    if (score > 0) score -= 1;
                }
            }
        }
        if (bb_countdown == 0) {
            bb_countdown = 6;
            bb_y += 1;
        } else bb_countdown -= 1;

        var baddie_count: usize = 0;
        for (baddie_block) |*baddie_row, row_offset| for (baddie_row.*) |*baddie, col_num| {
            const row_num = row_offset + bb_y;
            if (row_num >= height) continue;

            if (baddie.* > 0) {
                for (bullets) |*bullet| {
                    if (bullet.x == col_num and
                        bullet.y <= row_num and
                        bullet.active)
                    {
                        score += 3;
                        baddie.* -= 1;
                        bullet.active = false;
                        bullet.y = 0;
                        bullet.x = 0;
                    }
                    if (row_num == height - 1) { // baddie reached bottom
                        if (score >= 5) {
                            score -= 5;
                        } else {
                            score = 0;
                        }
                    }
                }

                game_display.cellRef(row_num, col_num).* = .{
                    .char = bad_char,
                    .attribs = .{ .fg_magenta = true },
                };
                baddie_count += 1;
            }
        };

        if ((baddie_count == 0) or (bb_y >= height)) {
            bb_y = 0;
            baddie_block = baddie_block_init;
            bullets = [_]Bullet{.{}} ** 4; // clear all the bullets
        }

        for (bullets) |bullet| {
            if (bullet.active)
                game_display.cellRef(bullet.y, bullet.x).* = .{
                    .char = bullet_char,
                    .attribs = .{ .fg_yellow = true },
                };
        }
        var score_curs = game_display.cursorAt(0, 3);
        score_curs.attribs = .{ .underline = true };

        try score_curs.writer().print("{:0>4}", .{score});

        const game_row = if (size.height >= height + 2)
            size.height / 2 - mid_height
        else
            0;

        const game_col = if (size.width >= height + 2)
            size.width / 2 - mid_width
        else
            0;

        output.blit(game_display, @intCast(isize, game_row), @intCast(isize, game_col));
        try display.push(output);
    }
}
