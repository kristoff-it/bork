# Zig TZif

This repository implements TZif parsing, according to [RFC 8536][].

[rfc 8536]: https://datatracker.ietf.org/doc/html/rfc8536

## Usage

Take a look at the [examples][] to get an idea of this library works. I
recommend starting with the [localtime][] example.

[examples]: ./examples/
[localtime]: ./examples/localtime.zig

### Add it as a package

To start, add zig-tzif to your `build.zig.zon`:

```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .tzif = .{
            .url = "https://github.com/leroycep/zig-tzif/archive/fdac55aa9b4a59b5b0dcba20866b6943fc00765d.tar.gz",
            .hash = "1220459c1522d67e7541b3500518c9db7d380aaa962d433e6704d87a21b643502e69",
        },
    },
}
```

Then, add `zig-tzif` to executable (or library) in the `build.zig`:

```zig
const Build = @import("std").Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the tzif dependency
    const tzif = b.dependency("tzif", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "tzif",
        .root_source_file = b.path("tzif.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add it as a module
    exe.addModule("tzif", tzif.module("tzif"));

    b.installArtifact(exe);
}

```

### Useful functions

#### `tzif.parseFile(allocator, filename) !TimeZone`

#### `tzif.parse(allocator, reader, seekableStream) !TimeZone`

#### `TimeZone.localTimeFromUTC(this, utc_timestamp) ?ConversionResult`

## Caveats

-   This library has not been rigorously tested, it might not always produce the
    correct offset, especially for time zones that have changed between
    different Daylight Savings schemes.
-   Does not support version 1 files. Files must be version 2 or 3.
