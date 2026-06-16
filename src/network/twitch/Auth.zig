const Auth = @This();
const std = @import("std");
const build_opts = @import("build_options");
const folders = @import("known-folders");
const Config = @import("../../Config.zig");
const oauth = @import("../oauth.zig");

const log = std.log.scoped(.twitch_auth);
const url = "https://id.twitch.tv/oauth2/validate";

user_id: []const u8,
login: []const u8,
token: []const u8 = "",

pub fn get(io: std.Io, gpa: std.mem.Allocator, config_base: std.Io.Dir, stdin: *std.Io.Reader) !Auth {
    const token = blk: {
        const file = config_base.openFile(io, "bork/twitch-token.secret", .{}) catch |err| {
            switch (err) {
                else => return err,
                error.FileNotFound => {
                    const t = try oauth.createToken(io, gpa, config_base, .twitch, false, stdin);
                    break :blk t.twitch;
                },
            }
        };
        defer file.close(io);
        var buffer: [1024]u8 = undefined;
        var reader = file.reader(io, &buffer);
        const token_raw = try reader.interface.readAlloc(gpa, 4096);
        const token = std.mem.trimEnd(u8, token_raw, " \n");
        break :blk token;
    };

    return authenticateToken(io, gpa, token) catch |err| switch (err) {
        // Twitch token needs to be renewed
        error.TokenExpired => {
            const new_token = try oauth.createToken(io, gpa, config_base, .twitch, true, stdin);

            const auth = authenticateToken(io, gpa, new_token.twitch) catch |new_err| {
                std.debug.print("\nCould not validate the token with Twitch: {s}\n", .{
                    @errorName(new_err),
                });

                std.process.exit(1);
            };

            return auth;
        },
        else => {
            std.debug.print("Error while renewing Twitch OAuth token: {s}\n", .{
                @errorName(err),
            });
            std.process.exit(1);
        },
    };
}

pub fn authenticateToken(io: std.Io, gpa: std.mem.Allocator, token: []const u8) !Auth {
    if (build_opts.local) return .{
        .user_id = "$user_id",
        .login = "$login",
        .token = "$token",
    };

    std.debug.print("Twitch auth...\n", .{});

    const header_oauth = try std.fmt.allocPrint(
        gpa,
        "Authorization: {s}",
        .{token},
    );
    defer gpa.free(header_oauth);

    const result = try std.process.spawn(io, .{
        .argv = &.{
            "curl",
            "-s",
            "-H",
            header_oauth,
            url,
        },
        .stdout = .pipe,
        .stderr = .pipe,
    });

    var arr: std.ArrayList(u8) = .empty;
    defer arr.deinit(gpa);
    {
        var buffer: [256]u8 = undefined;
        var reader = result.stdout.?.reader(io, &buffer);
        try reader.interface.appendRemaining(gpa, &arr, .unlimited);
    }
    if (arr.items.len == 0) {
        return error.TokenExpired;
    }

    var auth = std.json.parseFromSliceLeaky(Auth, gpa, arr.items, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch {
        // std.debug.print("auth fail: {s}\n", .{result.stdout});
        // NOTE: A parsing error means token exprired for us because
        //       twitch likes to reply with 200 `{"status":401,"message":"invalid access token"}`
        //       as one does.
        return error.TokenExpired;
    };

    auth.token = token;
    return auth;
}

// TODO: re-enable once either Twitch starts supporting TLS 1.3 or Zig
//       adds support for TLS 1.2
fn authenticateTokenNative(gpa: std.mem.Allocator, token: []const u8) !?Auth {
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
        log.debug("token is not good: {s}", .{@tagName(result.status)});
        return null;
    }

    const auth = try std.json.parseFromSlice(Auth, gpa, result.body, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    auth.token = token;
    return auth;
}
