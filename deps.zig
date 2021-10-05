const std = @import("std");
pub const pkgs = struct {
    pub const zbox = std.build.Pkg{
        .name = "zbox",
        .path = .{ .path = "forks/zbox/src/box.zig" },
        .dependencies = &[_]std.build.Pkg{
            std.build.Pkg{
                .name = "ziglyph",
                .path = .{ .path = ".gyro/ziglyph-jecolon-c37d93b6c8e6a65aaf7f76157a8a95f9c9c43f61/pkg/src/Ziglyph.zig" },
            },
        },
    };

    pub const datetime = std.build.Pkg{
        .name = "datetime",
        .path = .{ .path = ".gyro/zig-datetime-frmdstryr-b52235d4026ead2ce8e2b768daf880f8174f0be5/pkg/datetime.zig" },
    };

    pub const clap = std.build.Pkg{
        .name = "clap",
        .path = .{ .path = ".gyro/zig-clap-Hejsil-e7822aaf172704c557ad063468b2229131ce2aef/pkg/clap.zig" },
    };

    pub const iguanaTLS = std.build.Pkg{
        .name = "iguanaTLS",
        .path = .{ .path = ".gyro/iguanaTLS-nektro-953ad821fae6c920fb82399493663668cd91bde7/pkg/src/main.zig" },
    };

    pub const hzzp = std.build.Pkg{
        .name = "hzzp",
        .path = .{ .path = ".gyro/hzzp-truemedian-417eb13fefb05835c0534e622b5a6e2dc2fcd3d7/pkg/src/main.zig" },
    };

    pub const tzif = std.build.Pkg{
        .name = "tzif",
        .path = .{ .path = ".gyro/zig-tzif-leroycep-bf91177e6ff7f52cffc44c33b6d755392ed7f9d7/pkg/tzif.zig" },
    };

    pub const ziglyph = std.build.Pkg{
        .name = "ziglyph",
        .path = .{ .path = ".gyro/ziglyph-jecolon-c37d93b6c8e6a65aaf7f76157a8a95f9c9c43f61/pkg/src/Ziglyph.zig" },
    };

    pub fn addAllTo(artifact: *std.build.LibExeObjStep) void {
        @setEvalBranchQuota(1_000_000);
        inline for (std.meta.declarations(pkgs)) |decl| {
            if (decl.is_pub and decl.data == .Var) {
                artifact.addPackage(@field(pkgs, decl.name));
            }
        }
    }
};

pub const base_dirs = struct {
    pub const zbox = "forks/zbox";
    pub const datetime = ".gyro/zig-datetime-frmdstryr-b52235d4026ead2ce8e2b768daf880f8174f0be5/pkg";
    pub const clap = ".gyro/zig-clap-Hejsil-e7822aaf172704c557ad063468b2229131ce2aef/pkg";
    pub const iguanaTLS = ".gyro/iguanaTLS-nektro-953ad821fae6c920fb82399493663668cd91bde7/pkg";
    pub const hzzp = ".gyro/hzzp-truemedian-417eb13fefb05835c0534e622b5a6e2dc2fcd3d7/pkg";
    pub const tzif = ".gyro/zig-tzif-leroycep-bf91177e6ff7f52cffc44c33b6d755392ed7f9d7/pkg";
    pub const ziglyph = ".gyro/ziglyph-jecolon-c37d93b6c8e6a65aaf7f76157a8a95f9c9c43f61/pkg";
};
