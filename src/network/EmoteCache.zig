const builtin = @import("builtin");
const std = @import("std");
const os = std.os;
const b64 = std.base64.standard_encoder;

const Emote = @import("../Chat.zig").Message.Comment.Metadata.Emote;
const our_lib = @cImport({
    @cInclude("EmoteCache.h");
});

allocator: *std.mem.Allocator,
cache: std.AutoHashMap(u32, []const u8),

const Self = @This();
// TODO: for people with 8k SUMQHD terminals, let them use bigger size emotes
const hostname = "https://static-cdn.jtvnw.net";
// const twitch_pem = @embedFile("../../twitch.pem");
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
            const img = img: {
                nosuspend {
                    const path = try std.fmt.allocPrint(self.allocator, hostname ++ "/emoticons/v1/{}/1.0\x00", .{emote.id});
                    defer self.allocator.free(path);

                    var chunk: our_lib.MemoryStruct = undefined;
                    const code: c_int = our_lib.getEmotes(path.ptr, &chunk);
                    var image: []const u8 = undefined;
                    if (code != 0)
                        return error.CFailed;
                    image.ptr = chunk.memory;
                    image.len = chunk.size;
                    std.log.debug("image: {s}\n", .{image});

                    break :img image;
                }
            };

            var encode_buf = try self.allocator.alloc(u8, std.base64.Base64Encoder.calcSize(img.len));
            result.entry.value = b64.encode(encode_buf, img);
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
