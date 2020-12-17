const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options alloirc the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const example_log = b.fmt("{}/{}/{}", .{ b.build_root, b.cache_root, "example.log" });
    const exe = b.addExecutable("zig-twitch-chat", "src/main.zig");
    exe.addPackagePath("zbox", "libs/zbox/src/box.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // const irc_exe = b.addExecutable("irc_test", "src/irc_test.zig");
    // irc_exe.setTarget(target);
    // irc_exe.setBuildMode(mode);
    // irc_exe.install();

    // const irc_cmd = irc_exe.run();
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     irc_cmd.addArgs(args);
    // }

    // const irc_step = b.step("irc", "Run the irc test app");
    // irc_step.dependOn(&irc_cmd.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
