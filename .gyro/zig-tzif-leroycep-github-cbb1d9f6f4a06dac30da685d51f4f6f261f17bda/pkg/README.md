# Zig TZif

This repository implements TZif parsing, according to [RFC 8536][].

[rfc 8536]: https://tools.ietf.org/html/rfc8536

## Usage

Take a look at the [examples][] to get an idea of this library works. I
recommend starting with the [localtime][] example.

[examples]: ./examples/
[localtime]: ./examples/localtime.zig

### Add it as a package

To start, copy `tzif.zig` to your repository and add it as a package in your
build.zig:

```zig
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable("example", "src/main.zig");
    exe.addPackagePath("tzif", "tzif.zig");
    exe.setBuildMode(mode);
    exe.setTarget(target);
}
```

If you are using [zigmod][], you can add it to your deps like so:

```yaml
deps:
- type: git
  path: https://github.com/leroycep/zig-tzif.git
```

[zigmod]: https://github.com/nektro/zigmod

### Useful functions

#### `tzif.parseFile(allocator, filename) !TimeZone`

#### `tzif.parse(allocator, reader, seekableStream) !TimeZone`

#### `TimeZone.localTimeFromUTC(this, utc_timestamp) ?ConversionResult`

## Caveats

-   This library has not been rigorously tested, it might not always produce the
    correct offset, especially for time zones that have changed between
    different Daylight Savings schemes.
-   Does not support version 1 files. Files must be version 2 or 3.
