const builtin = @import("builtin");
const std = @import("std");
const os = std.os;
const b64 = std.base64.standard.Encoder;
// const zfetch = @import("zfetch");
const hzzp = @import("hzzp");
const tls = @import("iguanaTLS");
const Emote = @import("../Chat.zig").Message.Emote;

const EmoteHashMap = std.StringHashMap(struct {
    data: []const u8,
    idx: u32,
});

allocator: std.mem.Allocator,
idx_counter: u32 = 1,
cache: EmoteHashMap,

const Self = @This();
// TODO: for people with 8k SUMQHD terminals, let them use bigger size emotes
// const path_fmt = "https://localhost:443/emoticons/v1/{s}/3.0";
const hostname = "static-cdn.jtvnw.net";

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .cache = EmoteHashMap.init(allocator),
    };
}

// TODO: make this concurrent
// TODO: make so failing one emote doesn't fail the whole job!
pub fn fetch(self: *Self, emote_list: []Emote) !void {
    for (emote_list) |*emote| {
        std.log.debug("fetching  {}", .{emote.*});
        const result = try self.cache.getOrPut(emote.twitch_id);
        errdefer _ = self.cache.remove(emote.twitch_id);
        if (!result.found_existing) {
            std.log.debug("need to download", .{});
            // Need to download the image
            var img = img: {
                const TLSStream = tls.Client(std.net.Stream.Reader, std.net.Stream.Writer, tls.ciphersuites.all, true);
                const HttpClient = hzzp.base.client.BaseClient(TLSStream.Reader, TLSStream.Writer);

                var sock = try std.net.tcpConnectToHost(self.allocator, hostname, 443);
                defer sock.close();

                var defaultCsprng = blk: {
                    var seed: [std.rand.DefaultCsprng.secret_seed_length]u8 = undefined;
                    try std.os.getrandom(&seed);
                    break :blk &std.rand.DefaultCsprng.init(seed);
                };

                var rand = defaultCsprng.random();

                var tls_sock = try tls.client_connect(.{
                    .rand = rand,
                    .temp_allocator = self.allocator,
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

                const path = try std.fmt.allocPrint(
                    self.allocator,
                    "/emoticons/v1/{s}/1.0",
                    .{emote.twitch_id},
                );
                defer self.allocator.free(path);

                client.writeStatusLine("GET", path) catch {
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
                                std.log.debug("http bad response code: {d}", .{code});
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
            // var img = img: {
            //     const path = try std.fmt.allocPrint(
            //         self.allocator,
            //         path_fmt,
            //         .{emote.twitch_id},
            //     );
            //     defer self.allocator.free(path);

            //     std.log.debug("emote url = ({s})", .{path});

            //     var headers = zfetch.Headers.init(self.allocator);
            //     defer headers.deinit();

            //     try headers.appendValue("Host", "static-cdn.jtvnw.net");
            //     try headers.appendValue("User-Agent", "Bork");
            //     try headers.appendValue("Accept", "*/*");

            //     var req = try zfetch.Request.init(self.allocator, path, null);
            //     defer req.deinit();

            //     try req.do(.GET, headers, null);

            //     if (req.status.code != 200) {
            //         std.log.err("emote request failed ({s})", .{path});
            //         return error.HttpError;
            //     }

            //     break :img try req.reader().readAllAlloc(self.allocator, 1024 * 100);
            // };

            var encode_buf = try self.allocator.alloc(u8, std.base64.standard.Encoder.calcSize(img.len));
            result.value_ptr.* = .{
                .data = b64.encode(encode_buf, img),
                .idx = self.idx_counter,
            };
            self.idx_counter += 1;
        }

        emote.img_data = result.value_ptr.data;
        emote.idx = result.value_ptr.idx;
    }
}
