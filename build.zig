const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;
const pkgs = @import("deps.zig").pkgs;

pub fn build(b: *Builder) void {
    // Standard target options alloirc the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("bork", "src/main.zig");
    pkgs.addAllTo(exe);

    const local = b.option(bool, "local", "not using real data and testing locally") orelse false;
    const exe_options = b.addOptions();
    exe_options.addOption(bool, "local", local);

    exe.addOptions("build_options", exe_options);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
