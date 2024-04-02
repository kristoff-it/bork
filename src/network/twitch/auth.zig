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

    var auth = std.json.parseFromSliceLeaky(Auth, gpa, result.stdout, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch {
        // NOTE: A parsing error means token exprired for us because
        //       twitch likes to do `{"status":401,"message":"invalid access token"}`
        //       instead of using HTTP status codes correctly :^(
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

fn waitForToken() ![]const u8 {
    const address = try std.net.Address.parseIp("127.0.0.1", 22890);
    var tcp_server = try address.listen(.{
        .reuse_address = true,
        .reuse_port = true,
    });
    defer tcp_server.deinit();

    accept: while (true) {
        var conn = try tcp_server.accept();
        defer conn.stream.close();

        var read_buffer: [8000]u8 = undefined;
        var server = std.http.Server.init(conn, &read_buffer);
        while (server.state == .ready) {
            var request = server.receiveHead() catch |err| {
                std.debug.print("error: {s}\n", .{@errorName(err)});
                continue :accept;
            };
            const maybe_auth = try handleRequest(&request);
            return maybe_auth orelse continue :accept;
        }
    }
}

const collect_fragment_html = @embedFile("collect_fragment.html");
var access_token: [30]u8 = undefined;
fn handleRequest(request: *std.http.Server.Request) !?[]const u8 {
    const query = request.head.target;

    if (std.mem.eql(u8, query, "/")) {
        try request.respond(collect_fragment_html, .{
            .extra_headers = &.{.{ .name = "content-type", .value = "text/html" }},
        });
        return null;
    } else {
        const response_html = "<html><body><h1>Success! You can now return to bork</h1></body></html>";
        try request.respond(response_html, .{
            .extra_headers = &.{.{ .name = "content-type", .value = "text/html" }},
        });

        if (!std.mem.startsWith(u8, query, "/?")) {
            return error.BadURI;
        }

        var it = std.mem.tokenizeScalar(u8, query[2..], '&');

        while (it.next()) |kv| {
            var kv_it = std.mem.splitScalar(u8, kv, '=');
            const key = kv_it.next() orelse return error.BadURI;
            const value = kv_it.next() orelse return error.BadURI;
            if (std.mem.eql(u8, key, "access_token")) {
                @memcpy(&access_token, value);
                return &access_token;
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

    const token = waitForToken() catch |err| {
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
    const original_termios = try std.posix.tcgetattr(in.handle);
    {
        defer std.posix.tcsetattr(in.handle, .FLUSH, original_termios) catch {};
        var termios = original_termios;
        // set immediate input mode
        termios.lflag.ICANON = false;
        try std.posix.tcsetattr(in.handle, .FLUSH, termios);

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
