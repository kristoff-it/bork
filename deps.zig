const Pkg = @import("std").build.Pkg;
pub const pkgs = .{
    .zbox = .{
        .name = "zbox",
        .path = "forks/zbox/src/box.zig",
    },
    .datetime = .{
        .name = "datetime",
        .path = "zig-deps/68582870b79584c72d1164716da5bd48/datetime.zig",
    },
    .mecha = .{
        .name = "mecha",
        .path = "zig-deps/3a3ba987887772ca8d8d94a1275c84b7/mecha.zig",
    },
    .clap = .{
        .name = "clap",
        .path = "zig-deps/3607488077d231404672a6ca11155adb/clap.zig",
    },
};
