const std = @import("std");
const build_opts = @import("build_options");

const url = "https://id.twitch.tv/oauth2/validate";

pub fn checkTokenValidity(gpa: std.mem.Allocator, token: []const u8) !bool {
    if (build_opts.local) return true;

    var it = std.mem.tokenize(u8, token, ":");
    _ = it.next();
    const header_oauth = try std.fmt.allocPrint(gpa, "Authorization: OAuth {s}", .{it.next().?});
    defer gpa.free(header_oauth);

    const result = try std.ChildProcess.run(.{
        .allocator = gpa,
        .argv = &.{
            "curl",
            "-s",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            "-H",
            header_oauth,
            url,
        },
    });

    defer {
        gpa.free(result.stdout);
        gpa.free(result.stderr);
    }

    return std.mem.eql(u8, result.stdout, "200");
}

pub fn checkTokenValidityNative(gpa: std.mem.Allocator, token: []const u8) !bool {
    if (build_opts.local) return true;

    var client: std.http.Client = .{
        .allocator = gpa,
    };

    var it = std.mem.tokenize(u8, token, ":");
    _ = it.next();
    const header_oauth = try std.fmt.allocPrint(gpa, "OAuth {s}", .{it.next().?});
    defer gpa.free(header_oauth);

    const headers = try std.http.Headers.initList(gpa, &.{
        .{
            .name = "User-Agent",
            .value = "Bork",
        },
        .{
            .name = "Accept",
            .value = "*/*",
        },
        .{
            .name = "Authorization",
            .value = header_oauth,
        },
    });

    const result = try client.fetch(gpa, .{
        .headers = headers,
        .location = .{ .url = url },
    });

    if (result.status != .ok) {
        std.log.debug("token is not good: {s}", .{@tagName(result.status)});
        return false;
    }

    return true;
}
