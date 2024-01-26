const Auth = @This();
const std = @import("std");
const build_opts = @import("build_options");
const folders = @import("known-folders");
const Config = @import("../../Config.zig");

const log = std.log.scoped(.auth);
const url = "https://id.twitch.tv/oauth2/validate";

pub const client_id = "qlw2m6rgpnlcn17cnj5p06xtlh36b4";
const scopes = "bits:read" ++ "+" ++
    "channel:read:ads" ++ "+" ++
    "channel:read:charity" ++ "+" ++
    "channel:read:goals" ++ "+" ++
    "channel:read:guest_star" ++ "+" ++
    "channel:read:hype_train" ++ "+" ++
    "channel:read:polls" ++ "+" ++
    "channel:read:predictions" ++ "+" ++
    "channel:read:redemptions" ++ "+" ++
    "channel:bot" ++ "+" ++
    "channel:moderate" ++ "+" ++
    "moderator:read:followers" ++ "+" ++
    "chat:read" ++ "+" ++
    "chat:edit";
const redirect_uri = "http://localhost:22890/";

user_id: []const u8,
login: []const u8,
token: []const u8 = "",

pub fn get(gpa: std.mem.Allocator, config_base: std.fs.Dir) !Auth {
    const file = config_base.openFile("bork/token.secret", .{}) catch |err| {
        switch (err) {
            else => return err,
            error.FileNotFound => {
                return createToken(gpa, config_base, .new);
            },
        }
    };
    defer file.close();

    const token_raw = try file.reader().readAllAlloc(gpa, 4096);
    const token = std.mem.trimRight(u8, token_raw, " \n");

    return authenticateToken(gpa, token) catch |err| switch (err) {
        // Token needs to be renewed
        error.TokenExpired => try createToken(gpa, config_base, .renew),
        else => {
            std.debug.print("Error while renewing Twitch OAuth token: {s}\n", .{
                @errorName(err),
            });
            std.process.exit(1);
        },
    };
}

pub fn authenticateToken(gpa: std.mem.Allocator, token: []const u8) !Auth {
    if (build_opts.local) return .{
        .user_id = "$user_id",
        .login = "$login",
        .token = "$token",
    };

    std.debug.print("Authenticating with Twitch... \n", .{});

    const header_oauth = try std.fmt.allocPrint(
        gpa,
        "Authorization: Bearer {s}",
        .{token},
    );
    defer gpa.free(header_oauth);

    const result = try std.ChildProcess.run(.{
        .allocator = gpa,
        .argv = &.{
            "curl",
            "-s",
            "-H",
            header_oauth,
            url,
        },
    });

    defer {
        gpa.free(result.stdout);
        gpa.free(result.stderr);
    }

    if (result.stdout.len == 0) {
        return error.TokenExpired;
    }

    var auth = try std.json.parseFromSliceLeaky(Auth, gpa, result.stdout, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
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

fn waitForToken(gpa: std.mem.Allocator) ![]const u8 {
    var server = std.http.Server.init(.{
        .reuse_address = true,
        .reuse_port = true,
    });
    defer server.deinit();

    const address = try std.net.Address.parseIp("127.0.0.1", 22890);
    try server.listen(address);

    var header_buffer: [1024]u8 = undefined;
    accept: while (true) {
        var res = try server.accept(.{
            .allocator = gpa,
            .header_strategy = .{ .static = &header_buffer },
        });
        defer res.deinit();

        while (res.reset() != .closing) {
            res.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :accept,
                error.EndOfStream => continue,
                else => return err,
            };
            const maybe_auth = try handleRequest(&res);
            return maybe_auth orelse continue :accept;
        }
    }
}

const collect_fragment_html = @embedFile("collect_fragment.html");
fn handleRequest(res: *std.http.Server.Response) !?[]const u8 {
    res.status = .ok;

    const query = res.request.target;

    if (std.mem.eql(u8, query, "/")) {
        res.transfer_encoding = .{ .content_length = collect_fragment_html.len };
        try res.headers.append("content-type", "text/html");
        try res.headers.append("connection", "close");
        try res.send();
        _ = try res.writer().writeAll(collect_fragment_html);
        try res.finish();
        return null;
    } else {
        const response_html = "<html><body><h1>Success! You can now return to bork</h1></body></html>";
        res.transfer_encoding = .{ .content_length = response_html.len };
        try res.headers.append("content-type", "text/html");
        try res.headers.append("connection", "close");
        try res.send();
        _ = try res.writer().writeAll(response_html);
        try res.finish();

        if (!std.mem.startsWith(u8, query, "/?")) {
            return error.BadURI;
        }

        var it = std.mem.tokenizeScalar(u8, query[2..], '&');

        while (it.next()) |kv| {
            var kv_it = std.mem.splitScalar(u8, kv, '=');
            const key = kv_it.next() orelse return error.BadURI;
            const value = kv_it.next() orelse return error.BadURI;
            if (std.mem.eql(u8, key, "access_token")) {
                return value;
            }
        }

        return error.BadURI;
    }
}

const TokenActon = enum { new, renew };
fn createToken(
    gpa: std.mem.Allocator,
    config_base: std.fs.Dir,
    action: TokenActon,
) !Auth {
    switch (action) {
        .new => std.debug.print(
            \\
            \\======================================================
            \\
            \\Please authenticate with Twitch by navigating to the
            \\following URL: 
            \\
            \\
        , .{}),
        .renew => std.debug.print(
            \\
            \\The Twitch OAuth token expired, we must refresh it.
            \\
            \\Please re-authenticate with Twitch: 
            \\
            \\
        , .{}),
    }

    std.debug.print("https://id.twitch.tv/oauth2/authorize?client_id={s}&response_type=token&scope={s}&redirect_uri={s}\n\n", .{
        client_id, scopes, redirect_uri,
    });

    std.debug.print("Waiting...\n", .{});

    const token = waitForToken(gpa) catch |err| {
        std.debug.print("\nAn error occurred while waiting for the OAuth flow to complete: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    const auth = authenticateToken(gpa, token) catch |err| {
        std.debug.print("\nCould not validate the token with Twitch: {s}\n", .{
            @errorName(err),
        });

        std.process.exit(1);
    };

    var token_file = try config_base.createFile("bork/token.secret", .{});
    defer token_file.close();

    try token_file.writer().print("{s}\n", .{token});

    const in = std.io.getStdIn();
    const original_termios = try std.os.tcgetattr(in.handle);
    {
        defer std.os.tcsetattr(in.handle, .FLUSH, original_termios) catch {};
        var termios = original_termios;
        // set immediate input mode
        termios.lflag &= ~@as(std.os.system.tcflag_t, std.os.system.ICANON);
        try std.os.tcsetattr(in.handle, .FLUSH, termios);

        std.debug.print(
            \\
            \\
            \\Success, great job!
            \\Your token has been saved in your Bork config directory.
            \\
            \\Press any key to continue.
            \\
        , .{});

        _ = try in.reader().readByte();
    }

    return auth;
}
