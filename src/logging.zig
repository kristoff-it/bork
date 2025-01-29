const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const folders = @import("known-folders");

var log_file: ?std.fs.File = switch (builtin.target.os.tag) {
    .windows => null,
    else => std.io.getStdErr(),
};

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (scope != .display) return;

    const l = log_file orelse return;
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    const writer = l.writer();
    writer.print(prefix ++ format ++ "\n", args) catch return;
}

pub fn setup(gpa: std.mem.Allocator) void {
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    log_file = std.io.getStdErr();

    setup_internal(gpa) catch {
        log_file = null;
    };
}

fn setup_internal(gpa: std.mem.Allocator) !void {
    const cache_base = try folders.open(gpa, .cache, .{}) orelse
        try folders.open(gpa, .home, .{}) orelse
        try folders.open(gpa, .executable_dir, .{}) orelse
        std.fs.cwd();

    try cache_base.makePath("bork");

    const log_name = if (options.local) "bork-local.log" else "bork.log";
    const log_path = try std.fmt.allocPrint(gpa, "bork/{s}", .{log_name});
    defer gpa.free(log_path);

    const file = try cache_base.createFile(log_path, .{ .truncate = false });
    const end = try file.getEndPos();
    try file.seekTo(end);

    log_file = file;
}
