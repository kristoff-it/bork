const std = @import("std");
pub const pkgs = struct {
    pub const zbox = std.build.Pkg{
        .name = "zbox",
        .path = "forks/zbox/src/box.zig",
    };

    pub const datetime = std.build.Pkg{
        .name = "datetime",
        .path = ".gyro/zig-datetime-frmdstryr-b52235d4026ead2ce8e2b768daf880f8174f0be5/pkg/datetime.zig",
    };

    pub const clap = std.build.Pkg{
        .name = "clap",
        .path = ".gyro/zig-clap-Hejsil-42433ca7b59c3256f786af5d1d282798b5b37f31/pkg/clap.zig",
    };

    pub const iguanaTLS = std.build.Pkg{
        .name = "iguanaTLS",
        .path = ".gyro/iguanaTLS-alexnask-71bcc990f5b9012a7c16d39036ca89c0645dc250/pkg/src/main.zig",
    };

    pub const hzzp = std.build.Pkg{
        .name = "hzzp",
        .path = ".gyro/hzzp-truemedian-b4e874ed921f76941dce2870677b713c8e0ebc6c/pkg/src/main.zig",
    };

    pub const tzif = std.build.Pkg{
        .name = "tzif",
        .path = ".gyro/zig-tzif-leroycep-bf91177e6ff7f52cffc44c33b6d755392ed7f9d7/pkg/tzif.zig",
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
