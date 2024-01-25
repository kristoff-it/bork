const EmoteCache = @This();

const builtin = @import("builtin");
const std = @import("std");
const os = std.os;
const b64 = std.base64.standard.Encoder;
const Emote = @import("../../Chat.zig").Message.Emote;

const EmoteHashMap = std.StringHashMap(struct {
    data: []const u8,
    idx: u32,
});

gpa: std.mem.Allocator,
idx_counter: u32 = 1,
cache: EmoteHashMap,

// TODO: for people with 8k SUMQHD terminals, let them use bigger size emotes
// const path_fmt = "https://localhost:443/emoticons/v1/{s}/3.0";
const hostname = "static-cdn.jtvnw.net";

pub fn init(gpa: std.mem.Allocator) EmoteCache {
    return EmoteCache{
        .gpa = gpa,
        .cache = EmoteHashMap.init(gpa),
    };
}

// TODO: make this concurrent
// TODO: make so failing one emote doesn't fail the whole job!
pub fn fetch(self: *EmoteCache, emote_list: []Emote) !void {
    var client: std.http.Client = .{
        .allocator = self.gpa,
    };
    defer client.deinit();
    var headers = try std.http.Headers.initList(self.gpa, &.{
        .{ .name = "User-Agent", .value = "Bork" },
        .{ .name = "Accept", .value = "*/*" },
    });
    defer headers.deinit();

    for (emote_list) |*emote| {
        std.log.debug("fetching  {}", .{emote.*});
        const result = try self.cache.getOrPut(emote.twitch_id);
        errdefer _ = self.cache.remove(emote.twitch_id);
        if (!result.found_existing) {
            std.log.debug("need to download", .{});
            // Need to download the image
            const img = img: {
                const url = try std.fmt.allocPrint(
                    self.gpa,
                    "https://{s}/emoticons/v1/{s}/1.0",
                    .{ hostname, emote.twitch_id },
                );
                defer self.gpa.free(url);

                const res = try client.fetch(self.gpa, .{
                    .headers = headers,
                    .location = .{ .url = url },
                });

                if (res.status != .ok) {
                    std.log.debug("http bad response code: {s}", .{@tagName(res.status)});
                    return error.HttpFailed;
                }

                break :img res.body orelse {
                    std.log.debug("http missing body", .{});
                    return error.HttpFailed;
                };
            };

            const encode_buf = try self.gpa.alloc(u8, std.base64.standard.Encoder.calcSize(img.len));
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
