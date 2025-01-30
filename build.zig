const std = @import("std");

const bork_version = std.SemanticVersion{ .major = 0, .minor = 4, .patch = 1 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const local = b.option(bool, "local", "not using real data and testing locally") orelse false;

    const options = b.addOptions();

    const version = "0.5.0";
    options.addOption([:0]const u8, "version", try b.allocator.dupeZ(u8, version));
    options.addOption(bool, "local", local);

    const exe = b.addExecutable(.{
        .name = "bork",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // .strip = true,
    });

    const vaxis = b.dependency("vaxis", .{});

    const known_folders = b.dependency("known-folders", .{});
    const zeit = b.dependency("zeit", .{});
    const ziggy = b.dependency("ziggy", .{});
    const clap = b.dependency("clap", .{});
    const ws = b.dependency("ws", .{});

    exe.root_module.addImport("vaxis", vaxis.module("vaxis"));
    exe.root_module.addImport("known-folders", known_folders.module("known-folders"));
    exe.root_module.addImport("zeit", zeit.module("zeit"));
    exe.root_module.addImport("ziggy", ziggy.module("ziggy"));
    exe.root_module.addImport("clap", clap.module("clap"));
    exe.root_module.addImport("ws", ws.module("websocket"));

    exe.root_module.addOptions("build_options", options);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run bork");
    const run = b.addRunArtifact(exe);

    if (b.args) |args| run.addArgs(args);

    run_step.dependOn(&run.step);

    // Release

    const release_step = b.step("release", "Create releases for bork");
    const targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        // .{ .cpu_arch = .x86_64, .os_tag = .windows },
    };

    for (targets) |t| {
        const release_exe = b.addExecutable(.{
            .name = "bork",
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(t),
            .optimize = .ReleaseSafe,
        });
        // release_exe.root_module.addImport("known-folders", known_folders.module("known-folders"));
        // release_exe.root_module.addImport("datetime", datetime.module("zig-datetime"));
        // release_exe.root_module.addImport("zg", zg.module("zg"));
        // release_exe.root_module.addImport("tzif", tzif.module("tzif"));
        // release_exe.root_module.addImport("clap", clap.module("clap"));
        // release_exe.root_module.addImport("ws", ws.module("websocket"));

        release_exe.root_module.addOptions("build_options", options);

        const target_output = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        release_step.dependOn(&target_output.step);
    }
}
