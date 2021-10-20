const Builder = @import("std").build.Builder;

const EXAMPLES = [_]@import("std").build.Pkg{
    .{ .name = "localtime", .path = .{ .path = "examples/localtime.zig" } },
    .{ .name = "dump", .path = .{ .path = "examples/dump.zig" } },
    .{ .name = "read-all-zoneinfo", .path = .{ .path = "examples/read-all-zoneinfo.zig" } },
};

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("tzif", "tzif.zig");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("tzif.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const target = b.standardTargetOptions(.{});

    inline for (EXAMPLES) |example| {
        const exe = b.addExecutableSource(example.name, example.path);
        exe.addPackagePath("tzif", "tzif.zig");
        exe.setBuildMode(mode);
        exe.setTarget(target);

        const run_example = exe.run();
        if (b.args) |args| {
            run_example.addArgs(args);
        }

        const run_example_step = b.step("example-" ++ example.name, "Run the `" ++ example.name ++ "` example");
        run_example_step.dependOn(&run_example.step);
    }
}
