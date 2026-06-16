const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const folders = @import("known-folders");

// TODO: set to stderr
var log_file: ?std.Io.File = switch (builtin.target.os.tag) {
    .windows => null,
    else => null,
};

var log_io: std.Io = undefined;

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    // if (scope != .display) return;

    const l = log_file orelse return;
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;
    var buffer: [64]u8 = undefined;
    // TODO: handle value
    _ = std.debug.lockStderr(&buffer);
    defer std.debug.unlockStderr();

    var writer_buffer: [64]u8 = undefined;
    var writer = l.writer(log_io, &writer_buffer);
    writer.interface.print(prefix ++ format ++ "\n", args) catch return;
    writer.flush() catch return;
}

pub fn setup(
    io: std.Io,
    gpa: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    ) void {
    var buffer: [64]u8 = undefined;
    _ = std.debug.lockStderr(&buffer);
    defer std.debug.unlockStderr();

    log_file = std.Io.File.stderr();
    log_io = io;

    setup_internal(io, gpa, environ) catch {
        log_file = null;
    };
}

fn setup_internal(io: std.Io, gpa: std.mem.Allocator, environ: *const std.process.Environ.Map) !void {
    const cache_base = try folders.open(io, gpa, environ, .cache, .{}) orelse
        try folders.open(io, gpa, environ, .home, .{}) orelse
        // TODO: executable_dir is not exist anymore
        // try folders.open(io, gpa, environ, .executable_dir, .{}) orelse
        std.Io.Dir.cwd();

    try cache_base.createDir(io, "bork", .default_dir);

    const log_name = if (options.local) "bork-local.log" else "bork.log";
    const log_path = try std.fmt.allocPrint(gpa, "bork/{s}", .{log_name});
    defer gpa.free(log_path);

    // TODO: we need to set writer so we can set seek position
    // const file = try cache_base.createFile(io, log_path, .{ .truncate = false });
    // const end = try file.length(io);
    // try file.seekFromEnd(0);
    //
    // log_file = file;
}
