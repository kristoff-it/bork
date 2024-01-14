const std = @import("std");

const bork_version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 1 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
        const git_describe_untrimmed = b.runAllowFail(&[_][]const u8{
            "git", "-C", b.build_root.path.?, "describe", "--match", "*.*.*", "--tags",
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

                const ancestor_ver = try std.SemanticVersion.parse(tagged_ancestor);
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

    const exe = b.addExecutable(.{
        .name = "bork",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zbox = b.dependency("zbox", .{});
    const known_folders = b.dependency("known-folders", .{});

    exe.root_module.addImport("zbox", zbox.module("zbox"));
    exe.root_module.addImport("known-folders", known_folders.module("known-folders"));

    exe.root_module.addOptions("build_options", options);
    b.installArtifact(exe);
}
