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

    const not_real = b.option(bool, "not_real", "not using real data and testing locally") orelse false;
    exe.addBuildOption(bool, "not_real", not_real);

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
