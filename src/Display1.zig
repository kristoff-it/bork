const std = @import("std");
const options = @import("build_options");

const vaxis = @import("vaxis");

const main = @import("main.zig");
const url = @import("utils/url.zig");
const Config = @import("Config.zig");
const Chat = @import("Chat.zig");
const Channel = @import("utils/channel.zig").Channel;
const GlobalEventUnion = main.Event;

const log = std.log.scoped(.display_vaxis);

var gpa: std.mem.Allocator = undefined;
var config: Config = undefined;
var loop: *vaxis.Loop(GlobalEventUnion) = undefined;
var chat: *Chat = undefined;

pub fn setup(
    gpa_: std.mem.Allocator,
    loop_: *vaxis.Loop(GlobalEventUnion),
    config_: Config,
    chat_: *Chat,
) !void {
    gpa = gpa_;
    loop = loop_;
    config = config_;
    chat = chat_;
}

pub fn teardown() void {}

pub fn render() !void {
    const vx = loop.vaxis;
    const tty = loop.tty;

    const win = vx.window();
    win.clear();

    const bar_style: vaxis.Style = .{ .bg = .{ .index = 4 } };
    const top = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = null,
        .height = 1,
    });

    top.fill(.{ .style = bar_style });

    const window_title: []const u8 = comptime blk: {
        var v = std.mem.tokenizeScalar(u8, options.version, '.');
        const major = v.next().?;
        const minor = v.next().?;
        const patch = v.next().?;
        const dev = v.next() != null;
        const more = if (dev or patch[0] != '0') "+" else "";

        break :blk std.fmt.comptimePrint("bork ⚡ v{s}.{s}{s}", .{ major, minor, more });
    };
    const window_title_width: u16 = window_title.len - 2;

    if (win.width > window_title_width) {
        _ = top.printSegment(.{ .text = window_title, .style = bar_style }, .{
            .col_offset = (win.width - window_title_width) / 2,
        });
    }

    const body = win.child(.{
        .x_off = 0,
        .y_off = @min(1, win.height -| 1),
        .width = null,
        .height = win.height -| 2,
    });

    try renderBody(body);

    const bottom = win.child(.{
        .x_off = 0,
        .y_off = win.height -| 1,
        .width = null,
        .height = 1,
    });

    bottom.fill(.{ .style = bar_style });
    try vx.render(tty.anyWriter());
}

fn renderBody(body: vaxis.Window) !void {
    var row = body.height;
    var current_message = chat.bottom_message;
    while (current_message) |msg| : (current_message = msg.prev) {
        if (row == 0) break;

        switch (msg.kind) {
            else => {},
            .chat => |comment| {
                const res = body.printSegment(.{ .text = comment.text }, .{
                    .wrap = .word,
                    .commit = false,
                });
                row -|= res.row + 1;

                _ = body.printSegment(.{ .text = comment.text }, .{
                    .row_offset = row,
                    .wrap = .word,
                });

                log.debug("msg body res = {}", .{res});

                if (msg.prev == null or
                    !std.mem.eql(u8, msg.prev.?.login_name, msg.login_name))
                {
                    if (row == 0) break;
                    row -= 1;

                    _ = body.printSegment(.{
                        .text = comment.display_name,
                        .style = .{ .bold = true },
                    }, .{
                        .col_offset = 0,
                        .row_offset = row,
                        .wrap = .none,
                    });
                }
            },
        }
    }
}

pub fn setAfkMessage(
    target_time: i64,
    reason: []const u8,
    title: []const u8,
) !void {
    _ = target_time;
    _ = reason;
    _ = title;
}

pub fn clearActiveInteraction(c: ?[]const u8) void {
    _ = c;
}

pub fn wantTick() bool {
    return true;
    // return afk != null or showing_quit_message != null;
}

pub fn prepareMessage(m: Chat.Message) !*Chat.Message {
    const result = try gpa.create(Chat.Message);
    result.* = m;
    return result;
}
