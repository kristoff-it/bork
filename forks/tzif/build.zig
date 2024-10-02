const Build = @import("std").Build;

const Example = struct {
    name: []const u8,
    path: []const u8,
};

const EXAMPLES = [_]Example{
    .{ .name = "localtime", .path = "examples/localtime.zig" },
    .{ .name = "dump", .path = "examples/dump.zig" },
    .{ .name = "read-all-zoneinfo", .path = "examples/read-all-zoneinfo.zig" },
};

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const module = b.addModule("tzif", .{
        .root_source_file = b.path("tzif.zig"),
    });

    const lib = b.addStaticLibrary(.{
        .name = "tzif",
        .root_source_file = b.path("tzif.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = b.path("tzif.zig"),
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    inline for (EXAMPLES) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = b.path(example.path),
            .optimize = optimize,
            .target = target,
        });
        exe.root_module.addImport("tzif", module);

        const run_example = b.addRunArtifact(exe);
        if (b.args) |args| {
            run_example.addArgs(args);
        }

        const run_example_step = b.step("example-" ++ example.name, "Run the `" ++ example.name ++ "` example");
        run_example_step.dependOn(&run_example.step);
    }
}
