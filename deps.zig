const std = @import("std");
const Pkg = std.build.Pkg;
const FileSource = std.build.FileSource;

pub const pkgs = struct {
    pub const zbox = Pkg{
        .name = "zbox",
        .path = FileSource{
            .path = "forks/zbox/src/box.zig",
        },
        .dependencies = &[_]Pkg{
            Pkg{
                .name = "ziglyph",
                .path = FileSource{
                    .path = ".gyro/ziglyph-jecolon-github.com-90ac933a/pkg/src/ziglyph.zig",
                },
            },
        },
    };

    pub const datetime = Pkg{
        .name = "datetime",
        .path = FileSource{
            .path = ".gyro/zig-datetime-frmdstryr-github.com-9a49593d/pkg/src/datetime.zig",
        },
    };

    pub const clap = Pkg{
        .name = "clap",
        .path = FileSource{
            .path = ".gyro/zig-clap-Hejsil-github.com-ac5f4654/pkg/clap.zig",
        },
    };

    pub const iguanaTLS = Pkg{
        .name = "iguanaTLS",
        .path = FileSource{
            .path = ".gyro/iguanaTLS-nektro-github.com-9a05f036/pkg/src/main.zig",
        },
    };

    pub const hzzp = Pkg{
        .name = "hzzp",
        .path = FileSource{
            .path = ".gyro/hzzp-truemedian-github.com-bf5aaf22/pkg/src/main.zig",
        },
    };

    pub const tzif = Pkg{
        .name = "tzif",
        .path = FileSource{
            .path = ".gyro/zig-tzif-leroycep-github.com-cbb1d9f6/pkg/tzif.zig",
        },
    };

    pub const ziglyph = Pkg{
        .name = "ziglyph",
        .path = FileSource{
            .path = ".gyro/ziglyph-jecolon-github.com-90ac933a/pkg/src/ziglyph.zig",
        },
    };

    pub const @"known-folders" = Pkg{
        .name = "known-folders",
        .path = FileSource{
            .path = ".gyro/known-folders-ziglibs-github.com-9db1b992/pkg/known-folders.zig",
        },
    };

    pub fn addAllTo(artifact: *std.build.LibExeObjStep) void {
        artifact.addPackage(pkgs.zbox);
        artifact.addPackage(pkgs.datetime);
        artifact.addPackage(pkgs.clap);
        artifact.addPackage(pkgs.iguanaTLS);
        artifact.addPackage(pkgs.hzzp);
        artifact.addPackage(pkgs.tzif);
        artifact.addPackage(pkgs.ziglyph);
        artifact.addPackage(pkgs.@"known-folders");
    }
};

pub const exports = struct {
    pub const bork = Pkg{
        .name = "bork",
        .path = "src/main.zig",
        .dependencies = &[_]Pkg{
            pkgs.zbox,
            pkgs.datetime,
            pkgs.clap,
            pkgs.iguanaTLS,
            pkgs.hzzp,
            pkgs.tzif,
            pkgs.ziglyph,
            pkgs.@"known-folders",
        },
    };
};
