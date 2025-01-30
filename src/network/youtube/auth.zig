const Auth = @This();

const std = @import("std");
const oauth = @import("../oauth.zig");
const livechat = @import("livechat.zig");
const Config = @import("../../Config.zig");

const log = std.log.scoped(.yt_auth);

enabled: bool = false,
chat_id: ?[]const u8 = null,
token: oauth.Token.YouTube = undefined,

const google_oauth = "https://accounts.google.com/o/oauth2/v2/auth?client_id=519150430990-68hvu66hl7vdtpb4u1mngb0qq2hqoiv8.apps.googleusercontent.com&redirect_uri=http://localhost:22890&response_type=token&scope=https://www.googleapis.com/auth/youtube.readonly";

pub fn get(gpa: std.mem.Allocator, config_base: std.fs.Dir) !Auth {
    const token: oauth.Token.YouTube = blk: {
        const file = config_base.openFile("bork/youtube-token.secret", .{}) catch |err| {
            switch (err) {
                else => return err,
                error.FileNotFound => {
                    const t = try oauth.createToken(gpa, config_base, .youtube, false);
                    break :blk t.youtube;
                },
            }
        };
        defer file.close();
        const token_raw = try file.reader().readAllAlloc(gpa, 4096);
        const refresh_token = std.mem.trimRight(u8, token_raw, " \n");
        break :blk try refreshToken(gpa, refresh_token);
    };

    return authenticateToken(gpa, token) catch |err| switch (err) {
        // Twitch token needs to be renewed
        error.InvalidToken => {
            const new_token = try oauth.createToken(gpa, config_base, .youtube, true);

            const auth = authenticateToken(gpa, new_token.youtube) catch |new_err| {
                std.debug.print("\nCould not validate the token with YouTube: {s}\n", .{
                    @errorName(new_err),
                });

                std.process.exit(1);
            };

            return auth;
        },
        else => {
            std.debug.print("Error while renewing YouTube OAuth token: {s}\n", .{
                @errorName(err),
            });
            std.process.exit(1);
        },
    };
}

pub fn authenticateToken(gpa: std.mem.Allocator, token: oauth.Token.YouTube) !Auth {
    std.debug.print("YouTube auth... \n", .{});
    const chat_id = try livechat.findLive(gpa, token);
    return .{
        .enabled = true,
        .token = token,
        .chat_id = chat_id,
    };
}

const google_refresh = "https://oauth2.googleapis.com/token?client_id=519150430990-68hvu66hl7vdtpb4u1mngb0qq2hqoiv8.apps.googleusercontent.com&client_secret=GOC" ++ "SPX-5e1VALKHYwGJZDlnLyUKKgN_I1KW&grant_type=refresh_token&refresh_token={s}";

pub fn refreshToken(
    gpa: std.mem.Allocator,
    refresh_token: []const u8,
) !oauth.Token.YouTube {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    var yt: std.http.Client = .{ .allocator = arena };
    defer yt.deinit();

    const refresh_url = try std.fmt.allocPrint(arena, google_refresh, .{
        refresh_token,
    });

    var buf = std.ArrayList(u8).init(arena);

    log.debug("YT REQUEST: refresh 2 access token", .{});

    const res = yt.fetch(.{
        .location = .{ .url = refresh_url },
        .method = .POST,
        .response_storage = .{ .dynamic = &buf },
        .extra_headers = &.{.{ .name = "Content-Length", .value = "0" }},
    }) catch {
        return error.YouTubeRefreshTokenFailed;
    };

    log.debug("yt token refresh = {}", .{res});
    log.debug("data = {s}", .{buf.items});

    const payload = std.json.parseFromSliceLeaky(struct {
        access_token: []const u8,
        expires_in: i64,
        scope: []const u8,
        token_type: []const u8,
    }, arena, buf.items, .{}) catch {
        log.err("Error while parsing YouTube token refresh payoload: {s}", .{buf.items});
        return error.BadYouTubeRefreshData;
    };

    return .{
        .refresh = refresh_token,
        .access = try std.fmt.allocPrint(
            gpa,
            "Bearer {s}",
            .{payload.access_token},
        ),
        .expires_at_seconds = std.time.timestamp() + payload.expires_in,
    };
}
