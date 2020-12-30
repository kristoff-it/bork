const builtin = @import("builtin");
const std = @import("std");
const os = std.os;
const b64 = std.base64.standard_encoder;
const hzzp = @import("hzzp");
const tls = @import("iguanaTLS");
const Emote = @import("../Chat.zig").Message.Comment.Metadata.Emote;

const TLSStream = tls.Client(std.fs.File.Reader, std.fs.File.Writer);
const HttpClient = hzzp.base.client.BaseClient(TLSStream.Reader, TLSStream.Writer);

allocator: *std.mem.Allocator,
cache: std.AutoHashMap(u32, []const u8),

const Self = @This();
// TODO: for people with 8k SUMQHD terminals, let them use bigger size emotes
const hostname = "static-cdn.jtvnw.net";
pub fn init(allocator: *std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .cache = std.AutoHashMap(u32, []const u8).init(allocator),
    };
}

// TODO: make this concurrent
// TODO: make so failing one emote doesn't fail the whole job!
pub fn fetch(self: *Self, emote_list: []Emote) !void {
    for (emote_list) |*emote| {
        std.log.debug("fetching  {}", .{emote.*});
        const result = try self.cache.getOrPut(emote.id);
        errdefer _ = self.cache.remove(emote.id);
        if (!result.found_existing) {
            std.log.debug("need to download", .{});
            // Need to download the image
            var img = img: {
                var sock = try std.net.tcpConnectToHost(self.allocator, hostname, 443);
                defer sock.close();

                var tls_sock = try tls.client_connect(.{
                    .rand = null,
                    .reader = sock.reader(),
                    .writer = sock.writer(),
                    .cert_verifier = .none,
                }, hostname);
                defer tls_sock.close_notify() catch {};

                var buf: [1024]u8 = undefined;
                var client = HttpClient.init(
                    &buf,
                    tls_sock.reader(),
                    tls_sock.writer(),
                );

                const path = try std.fmt.allocPrint(self.allocator, "/emoticons/v1/{}/1.0", .{emote.id});
                defer self.allocator.free(path);

                client.writeStatusLine("GET", path) catch |err| {
                    return error.Error;
                };
                client.writeHeaderValue("Host", hostname) catch unreachable;
                client.writeHeaderValue("User-Agent", "Zig") catch unreachable;
                client.writeHeaderValue("Accept", "*/*") catch unreachable;
                client.finishHeaders() catch unreachable;

                // Consume headers
                while (try client.next()) |event| {
                    switch (event) {
                        .status => |status| switch (status.code) {
                            200 => {},
                            else => |code| {
                                std.log.debug("http bad response code: {}", .{code});
                                return error.HttpFailed;
                            },
                        },
                        .header => {},
                        .head_done => break,
                        else => |val| std.log.debug("got other: {}", .{val}),
                    }
                }
                break :img try client.reader().readAllAlloc(self.allocator, 1024 * 100);
            };

            var encode_buf = try self.allocator.alloc(u8, std.base64.Base64Encoder.calcSize(img.len));
            result.entry.value = b64.encode(encode_buf, img);
        }

        emote.image = result.entry.value;
    }
}
