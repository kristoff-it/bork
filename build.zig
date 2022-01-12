const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;
const pkgs = @import("deps.zig").pkgs;

const bork_version = std.builtin.Version{ .major = 0, .minor = 1, .patch = 1 };

pub fn build(b: *Builder) !void {
    // Standard target options alloirc the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const local = b.option(bool, "local", "not using real data and testing locally") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "local", local);
    const version = v: {
        const version_string = b.fmt(
            "{d}.{d}.{d}",
            .{
                bork_version.major,
                bork_version.minor,
                bork_version.patch,
            },
        );

        var code: u8 = undefined;
        const git_describe_untrimmed = b.execAllowFail(&[_][]const u8{
            "git", "-C", b.build_root, "describe", "--match", "*.*.*", "--tags",
        }, &code, .Ignore) catch {
            break :v version_string;
        };
        const git_describe = std.mem.trim(u8, git_describe_untrimmed, " \n\r");

        switch (std.mem.count(u8, git_describe, "-")) {
            0 => {
                // Tagged release version (e.g. 0.8.0).
                if (!std.mem.eql(u8, git_describe, version_string)) {
                    std.debug.print(
                        "version '{s}' does not match Git tag '{s}'\n",
                        .{ version_string, git_describe },
                    );
                    std.process.exit(1);
                }
                break :v version_string;
            },
            2 => {
                // Untagged development build (e.g. 0.8.0-684-gbbe2cca1a).
                var it = std.mem.split(u8, git_describe, "-");
                const tagged_ancestor = it.next() orelse unreachable;
                const commit_height = it.next() orelse unreachable;
                const commit_id = it.next() orelse unreachable;

                const ancestor_ver = try std.builtin.Version.parse(tagged_ancestor);
                if (bork_version.order(ancestor_ver) != .gt) {
                    std.debug.print(
                        "version '{}' must be greater than tagged ancestor '{}'\n",
                        .{ bork_version, ancestor_ver },
                    );
                    std.process.exit(1);
                }

                // Check that the commit hash is prefixed with a 'g' (a Git convention).
                if (commit_id.len < 1 or commit_id[0] != 'g') {
                    std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
                    break :v version_string;
                }

                // The version is reformatted in accordance with the https://semver.org specification.
                break :v b.fmt("{s}-dev.{s}+{s}", .{ version_string, commit_height, commit_id[1..] });
            },
            else => {
                std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
                break :v version_string;
            },
        }
    };
    options.addOption([:0]const u8, "version", try b.allocator.dupeZ(u8, version));

    const release_step = b.step("release", "Builds a bunch of versions of bork");
    const releases = [_]std.zig.CrossTarget{
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
    };

    inline for (releases) |ct| {
        const exe = b.addExecutable("bork", "src/main.zig");
        pkgs.addAllTo(exe);
        exe.setOutputDir("./releases/" ++ @tagName(ct.os_tag.?) ++ "-" ++ @tagName(ct.cpu_arch.?));
        exe.setTarget(ct);
        exe.setBuildMode(.ReleaseSafe);
        exe.addOptions("build_options", options);
        exe.install();
        release_step.dependOn(&exe.install_step.?.step);
    }

    {
        const exe = b.addExecutable("bork", "src/main.zig");
        pkgs.addAllTo(exe);

        exe.addOptions("build_options", options);
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.install();

        b.default_step.dependencies.shrinkRetainingCapacity(0);
        b.default_step.dependOn(&exe.install_step.?.step);

        const run_cmd = exe.run();
        run_cmd.step.dependOn(&exe.install_step.?.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
}
