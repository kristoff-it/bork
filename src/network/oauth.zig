const std = @import("std");
const log = std.log.scoped(.oauth);

const twitch_oauth_url = "https://id.twitch.tv/oauth2/authorize?client_id={s}&response_type=token&scope={s}&redirect_uri={s}";

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

const google_oauth = "https://accounts.google.com/o/oauth2/v2/auth?client_id=519150430990-68hvu66hl7vdtpb4u1mngb0qq2hqoiv8.apps.googleusercontent.com&redirect_uri=http://localhost:22890&response_type=token&scope=https://www.googleapis.com/auth/youtube.readonly";
const broadcasts_url = "https://www.googleapis.com/youtube/v3/liveBroadcasts?mine=true&part=id,snippet,status&maxResults=50";

const redirect_uri = "http://localhost:22890/";

pub fn createToken(
    gpa: std.mem.Allocator,
    config_base: std.fs.Dir,
    platform: enum { youtube, twitch },
    renew: bool,
) ![]const u8 {
    switch (platform) {
        .youtube => {
            std.debug.print(
                \\
                \\====================== YOUTUBE ======================
                \\
            , .{});
        },
        .twitch => {
            std.debug.print(
                \\
                \\====================== TWITCH =======================
                \\
            , .{});
        },
    }

    if (renew) {
        std.debug.print(
            \\
            \\Please authenticate with the platform by navigating to the
            \\following URL: 
            \\
            \\
        , .{});
    } else {
        std.debug.print(
            \\
            \\The OAuth token expired, we must refresh it.
            \\Please re-authenticate: 
            \\
            \\
        , .{});
    }

    switch (platform) {
        .youtube => {
            std.debug.print(google_oauth, .{});
        },
        .twitch => {
            std.debug.print(twitch_oauth_url, .{
                client_id,
                scopes,
                redirect_uri,
            });
        },
    }

    std.debug.print("\n\nWaiting...\n", .{});

    const token = waitForToken(gpa) catch |err| {
        std.debug.print("\nAn error occurred while waiting for the OAuth flow to complete: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    const path = switch (platform) {
        .youtube => "bork/youtube-token.secret",
        .twitch => "bork/twitch-token.secret",
    };

    var token_file = try config_base.createFile(path, .{ .truncate = true });
    defer token_file.close();

    try token_file.writer().print("{s}\n", .{token});

    const in = std.io.getStdIn();
    // const original_termios = try std.posix.tcgetattr(in.handle);
    {
        // defer std.posix.tcsetattr(in.handle, .FLUSH, original_termios) catch {};
        // var termios = original_termios;
        // // set immediate input mode
        // termios.lflag.ICANON = false;
        // try std.posix.tcsetattr(in.handle, .FLUSH, termios);

        std.debug.print(
            \\
            \\
            \\Success, great job!
            \\The token has been saved in your Bork config directory.
            \\
            \\Press any key to continue.
            \\
        , .{});

        _ = try in.reader().readByte();
    }

    return token;
}

fn waitForToken(gpa: std.mem.Allocator) ![]const u8 {
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
            const maybe_auth = try handleRequest(gpa, &request);
            return maybe_auth orelse continue :accept;
        }
    }
}

const collect_fragment_html = @embedFile("collect_fragment.html");
fn handleRequest(gpa: std.mem.Allocator, request: *std.http.Server.Request) !?[]const u8 {
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
                return try std.fmt.allocPrint(gpa, "Bearer {s}", .{value});
            }
        }

        return error.BadURI;
    }
}
