const std = @import("std");
const tzif = @import("tzif");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const path_to_dir = if (args.len > 1) args[1] else "/usr/share/zoneinfo";

    var successful_parse: usize = 0;
    var successful_tz_formatting: usize = 0;
    var successful_convert: usize = 0;
    var failed_parse: usize = 0;
    var failed_tz_formatting: usize = 0;
    var failed_convert: usize = 0;

    const cwd = std.fs.cwd();
    const zoneinfo = try cwd.openIterableDir(path_to_dir, .{});

    var walker = try zoneinfo.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const file = try zoneinfo.dir.openFile(entry.path, .{});
            defer file.close();

            if (tzif.parse(allocator, file.reader(), file.seekableStream())) |timezone| {
                defer timezone.deinit();

                if (timezone.posixTZ) |posix_tz| {
                    const formatted_by_tzifzig_library = try std.fmt.allocPrint(allocator, "{}", .{posix_tz});
                    defer allocator.free(formatted_by_tzifzig_library);
                    if (!std.mem.eql(u8, formatted_by_tzifzig_library, timezone.string)) {
                        failed_tz_formatting += 1;
                        std.debug.print("{s}: PosixTZ formatting differs between library and file: file = \"{}\"; library = \"{}\"\n", .{ entry.path, std.zig.fmtEscapes(timezone.string), posix_tz });
                    } else {
                        successful_tz_formatting += 1;
                    }
                }

                successful_parse += 1;
                const utc = std.time.timestamp();
                if (timezone.localTimeFromUTC(utc) != null) {
                    successful_convert += 1;
                } else {
                    failed_convert += 1;
                    std.log.warn("Failed to convert with {s}", .{entry.path});
                }
            } else |err| {
                failed_parse += 1;
                std.log.warn("Failed to parse {s}: {}", .{ entry.path, err });
            }
        }
    }

    std.log.info("Parsed: {}/{}", .{ successful_parse, successful_parse + failed_parse });
    std.log.info("Matching TZ parse/format roundtrip: {}/{}", .{ successful_tz_formatting, successful_tz_formatting + failed_tz_formatting });
    std.log.info("Converted: {}/{}", .{ successful_convert, successful_convert + failed_convert });
}
