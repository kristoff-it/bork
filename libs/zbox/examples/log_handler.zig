const std = @import("std");
const options = @import("build_options");
const term = @import("zbox");

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const logfile = std.fs.cwd().createFile(options.log_path, .{ .truncate = false }) catch return;
    defer logfile.close();
    const writer = logfile.writer();
    const end = logfile.getEndPos() catch return;
    logfile.seekTo(end) catch return;

    writer.print("{}: {}:" ++ format ++ "\n", .{ @tagName(message_level), @tagName(scope) } ++ args) catch return;
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    term.deinit();
    //std.debug.print("wtf?", .{});
    log(.emerg, .examples, "{}", .{msg});
    std.builtin.default_panic(msg, trace);
}
