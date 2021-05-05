const std = @import("std");
const hzzp = @import("hzzp");
const tls = @import("iguanaTLS");
const build_opts = @import("build_options");

const hostname = "id.twitch.tv";

pub fn checkTokenValidity(allocator: *std.mem.Allocator, token: []const u8) !bool {
    if (build_opts.local) return true;

    const TLSStream = tls.Client(std.net.Stream.Reader, std.net.Stream.Writer, tls.ciphersuites.all, true);
    const HttpClient = hzzp.base.client.BaseClient(TLSStream.Reader, TLSStream.Writer);

    var sock = try std.net.tcpConnectToHost(allocator, hostname, 443);
    defer sock.close();

    var randBuf: [32]u8 = undefined;
    try std.os.getrandom(&randBuf);
    var rng = std.rand.DefaultCsprng.init(randBuf);

    var rand = blk: {
        var seed: [std.rand.DefaultCsprng.secret_seed_length]u8 = undefined;
        try std.os.getrandom(&seed);
        break :blk &std.rand.DefaultCsprng.init(seed).random;
    };

    var tls_sock = try tls.client_connect(.{
        .rand = rand,
        .temp_allocator = allocator,
        .reader = sock.reader(),
        .writer = sock.writer(),
        .cert_verifier = .none,
        .ciphersuites = tls.ciphersuites.all,
        .protocols = &[_][]const u8{"http/1.1"},
    }, hostname);
    defer tls_sock.close_notify() catch {};

    var buf: [1024]u8 = undefined;
    var client = HttpClient.init(
        &buf,
        tls_sock.reader(),
        tls_sock.writer(),
    );

    var it = std.mem.tokenize(token, ":");
    _ = it.next();
    const header_oauth = try std.fmt.allocPrint(allocator, "OAuth {s}", .{it.next().?});
    defer allocator.free(header_oauth);

    client.writeStatusLine("GET", "/oauth2/validate") catch |err| {
        return error.Error;
    };
    client.writeHeaderValue("Host", hostname) catch unreachable;
    client.writeHeaderValue("User-Agent", "Bork") catch unreachable;
    client.writeHeaderValue("Accept", "*/*") catch unreachable;
    client.writeHeaderValue("Authorization", header_oauth) catch unreachable;
    client.finishHeaders() catch unreachable;

    // Consume headers
    while (try client.next()) |event| {
        switch (event) {
            .status => |status| switch (status.code) {
                200 => {},
                else => |code| {
                    std.log.debug("token is not good: {d}", .{code});
                    return false;
                },
            },
            .header => {},
            .head_done => {
                break;
            },
            else => |val| {
                std.log.debug("got other: {}", .{val});
                return error.HttpFailed;
            },
        }
    }
    return true;
}
