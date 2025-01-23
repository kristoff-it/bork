const Auth = @This();

const std = @import("std");
const oauth = @import("../oauth.zig");
const livechat = @import("livechat.zig");
const Config = @import("../../Config.zig");

enabled: bool = false,
token: []const u8 = "",
chat_id: ?[]const u8 = null,

const google_oauth = "https://accounts.google.com/o/oauth2/v2/auth?client_id=519150430990-68hvu66hl7vdtpb4u1mngb0qq2hqoiv8.apps.googleusercontent.com&redirect_uri=http://localhost:22890&response_type=token&scope=https://www.googleapis.com/auth/youtube.readonly";

pub fn get(gpa: std.mem.Allocator, config_base: std.fs.Dir) !Auth {
    const token = blk: {
        const file = config_base.openFile("bork/youtube-token.secret", .{}) catch |err| {
            switch (err) {
                else => return err,
                error.FileNotFound => {
                    break :blk try oauth.createToken(gpa, config_base, .youtube, false);
                },
            }
        };
        defer file.close();
        const token_raw = try file.reader().readAllAlloc(gpa, 4096);
        const token = std.mem.trimRight(u8, token_raw, " \n");
        break :blk token;
    };

    return authenticateToken(gpa, token) catch |err| switch (err) {
        // Twitch token needs to be renewed
        error.InvalidToken => {
            const new_token = try oauth.createToken(gpa, config_base, .youtube, true);

            const auth = authenticateToken(gpa, new_token) catch |new_err| {
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

pub fn authenticateToken(gpa: std.mem.Allocator, token: []const u8) !Auth {
    std.debug.print("YouTube auth... \n", .{});
    const chat_id = try livechat.findLive(gpa, token);
    return .{
        .enabled = true,
        .token = token,
        .chat_id = chat_id,
    };
}
