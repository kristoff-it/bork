const std = @import("std");
const Pkg = std.build.Pkg;
const FileSource = std.build.FileSource;

pub const pkgs = struct {
    pub const datetime = Pkg{
        .name = "datetime",
        .path = FileSource{
            .path = ".gyro/zig-datetime-frmdstryr-github-4782701cf1dbcf2d96dfcb2560f290cb74c54725/pkg/src/datetime.zig",
        },
    };

    pub const clap = Pkg{
        .name = "clap",
        .path = FileSource{
            .path = ".gyro/zig-clap-Hejsil-github-844c9370bcecf063daff697f296d6ae979190649/pkg/clap.zig",
        },
    };

    pub const iguanaTLS = Pkg{
        .name = "iguanaTLS",
        .path = FileSource{
            .path = ".gyro/iguanaTLS-nektro-github-954fd016964d44dfe8648985fd7c06f0067be6b0/pkg/src/main.zig",
        },
    };

    pub const hzzp = Pkg{
        .name = "hzzp",
        .path = FileSource{
            .path = ".gyro/hzzp-truemedian-github-91ab8e741992e8db30b3ee1cd9e7cd5a072ca294/pkg/src/main.zig",
        },
    };

    pub const tzif = Pkg{
        .name = "tzif",
        .path = FileSource{
            .path = ".gyro/zig-tzif-leroycep-github-cbb1d9f6f4a06dac30da685d51f4f6f261f17bda/pkg/tzif.zig",
        },
    };

    pub const ziglyph = Pkg{
        .name = "ziglyph",
        .path = FileSource{
            .path = ".gyro/ziglyph-jecolon-github-c37d93b6c8e6a65aaf7f76157a8a95f9c9c43f61/pkg/src/ziglyph.zig",
        },
    };

    pub const zbox = Pkg{
        .name = "zbox",
        .path = FileSource{
            .path = "forks/zbox/src/box.zig",
        },
        .dependencies = &[_]Pkg{
            Pkg{
                .name = "ziglyph",
                .path = FileSource{
                    .path = ".gyro/ziglyph-jecolon-github-c37d93b6c8e6a65aaf7f76157a8a95f9c9c43f61/pkg/src/ziglyph.zig",
                },
            },
        },
    };

    pub fn addAllTo(artifact: *std.build.LibExeObjStep) void {
        artifact.addPackage(pkgs.datetime);
        artifact.addPackage(pkgs.clap);
        artifact.addPackage(pkgs.iguanaTLS);
        artifact.addPackage(pkgs.hzzp);
        artifact.addPackage(pkgs.tzif);
        artifact.addPackage(pkgs.ziglyph);
        artifact.addPackage(pkgs.zbox);
    }
};

pub const exports = struct {
    pub const bork = Pkg{
        .name = "bork",
        .path = "src/main.zig",
        .dependencies = &[_]Pkg{
            pkgs.datetime,
            pkgs.clap,
            pkgs.iguanaTLS,
            pkgs.hzzp,
            pkgs.tzif,
            pkgs.ziglyph,
            pkgs.zbox,
        },
    };
};
