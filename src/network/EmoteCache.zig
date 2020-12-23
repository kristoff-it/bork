const builtin = @import("builtin");
const std = @import("std");
const os = std.os;
const b64 = std.base64.standard_encoder;
const hzzp = @import("hzzp");
const ssl = @import("bearssl");
const Emote = @import("../Chat.zig").Message.Metadata.Emote;

const SslStream = ssl.Stream(*std.fs.File.Reader, *std.fs.File.Writer);
const HttpClient = hzzp.base.client.BaseClient(SslStream.DstInStream, SslStream.DstOutStream);

log: std.fs.File.Writer,
allocator: *std.mem.Allocator,
cache: std.AutoHashMap(u32, []const u8),

const Self = @This();
// TODO: for people with 8k SUMHD terminals, let them use bigger size emotes
const hostname = "static-cdn.jtvnw.net";

pub fn init(allocator: *std.mem.Allocator, log: std.fs.File.Writer) Self {
    return Self{
        .log = log,
        .allocator = allocator,
        .cache = std.AutoHashMap(u32, []const u8).init(allocator),
    };
}

// TODO: make this concurrent
pub fn fetch(self: *Self, emote_list: []Emote) !void {
    for (emote_list) |*emote| {
        const result = try self.cache.getOrPut(emote.id);
        if (!result.found_existing) {
            // Need to download the image
            const img = img: {
                nosuspend {
                    var trust_anchor = ssl.TrustAnchorCollection.init(self.allocator);
                    errdefer trust_anchor.deinit();

                    var x509 = ssl.x509.Minimal.init(trust_anchor);
                    switch (builtin.os.tag) {
                        .linux, .macos => pem: {
                            const file = std.fs.openFileAbsolute("/etc/ssl/cert.pem", .{ .read = true }) catch |err| {
                                if (err == error.FileNotFound) {
                                    // try trust_anchor.appendFromPEM(github_pem);
                                    break :pem;
                                } else return err;
                            };
                            defer file.close();

                            const certs = try file.readToEndAlloc(self.allocator, 500000);
                            defer self.allocator.free(certs);

                            try trust_anchor.appendFromPEM(certs);
                        },
                        else => {
                            return error.DunnoHowToTrustAnchor;
                            // try trust_anchor.appendFromPEM(github_pem);
                        },
                    }

                    var ssl_client = ssl.Client.init(x509.getEngine());
                    ssl_client.relocate();
                    try ssl_client.reset(hostname, false);

                    var socket = try tcpConnectToHost(self.allocator, hostname, 443);
                    errdefer socket.close();
                    var socket_reader = socket.reader();
                    var socket_writer = socket.writer();

                    var ssl_socket = ssl.initStream(
                        ssl_client.getEngine(),
                        &socket_reader,
                        &socket_writer,
                    );
                    errdefer ssl_socket.close() catch {};

                    var buf: [1024]u8 = undefined;
                    var client = HttpClient.init(
                        &buf,
                        ssl_socket.inStream(),
                        ssl_socket.outStream(),
                    );

                    const path = try std.fmt.allocPrint(self.allocator, "/emoticons/v1/{}/1.0", .{emote.id});
                    defer self.allocator.free(path);

                    try client.writeStatusLine("GET", path);
                    try client.writeHeaderValue("Host", hostname);
                    try client.writeHeaderValue("User-Agent", "Zig");
                    try client.writeHeaderValue("Accept", "*/*");
                    try client.finishHeaders();
                    try ssl_socket.flush();

                    // Consume headers
                    while (try client.next()) |event| {
                        switch (event) {
                            .status => |status| switch (status.code) {
                                200 => {},
                                302 => @panic("no redirects plz"),
                                else => {
                                    self.log.print("got an HTTP return code: {}", .{status.code}) catch {};
                                    return error.HttpFailed;
                                },
                            },
                            .header => {},
                            .head_done => break,
                            else => |val| self.log.print("got other: {}\n", .{val}) catch {},
                        }
                    }
                    break :img try client.reader().readAllAlloc(self.allocator, 1024 * 100);
                }
            };

            var encoded_img = try self.allocator.alloc(u8, std.base64.Base64Encoder.calcSize(img.len));
            b64.encode(encoded_img, img);

            result.entry.value = encoded_img;
        }

        emote.image = result.entry.value;
    }
}

fn noop(_: []const u8) void {}

pub fn tcpConnectToHost(allocator: *std.mem.Allocator, name: []const u8, port: u16) !std.fs.File {
    const list = try std.net.getAddressList(allocator, name, port);
    defer list.deinit();

    if (list.addrs.len == 0) return error.UnknownHostName;

    for (list.addrs) |addr| {
        return tcpConnectToAddress(addr) catch |err| switch (err) {
            error.ConnectionRefused => {
                continue;
            },
            else => return err,
        };
    }
    return os.ConnectError.ConnectionRefused;
}

pub fn tcpConnectToAddress(address: std.net.Address) !std.fs.File {
    const nonblock = 0;
    const sock_flags = os.SOCK_STREAM | nonblock |
        (if (builtin.os.tag == .windows) 0 else os.SOCK_CLOEXEC);
    const sockfd = try os.socket(address.any.family, sock_flags, os.IPPROTO_TCP);
    errdefer os.closeSocket(sockfd);

    try os.connect(sockfd, &address.any, address.getOsSockLen());

    return std.fs.File{ .handle = sockfd, .intended_io_mode = .blocking };
}
