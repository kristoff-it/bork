const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("zbox", .{
        .root_source_file = .{ .path = "src/box.zig" },
        .target = target,
        .optimize = optimize,
    });
}
