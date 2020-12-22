const std = @import("std");
const Emote = @import("../Chat.zig").Message.Metadata.Emote;

log: std.fs.File.Writer,
allocator: *std.mem.Allocator,
cache: std.AutoHashMap(u32, []const u8),

const Self = @This();
// TODO: for people with 8k SUMHD terminals, let them use bigger size emotes
const url_template = "http://static-cdn.jtvnw.net/emoticons/v1/{}/1.0";

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
            var buf = std.ArrayList(u8).init(self.allocator);
            errdefer buf.deinit();

            // var downloadState = ziget.request.DownloadState.init();
            // const options = ziget.request.DownloadOptions{
            //     .flags = 0,
            //     .allocator = self.allocator,
            //     .maxRedirects = 5,
            //     .forwardBufferSize = 8192,
            //     .maxHttpResponseHeaders = 8192,
            //     .onHttpRequest = noop,
            //     .onHttpResponse = noop,
            // };

            // const url = try std.fmt.allocPrint(self.allocator, url_template, .{emote.id});
            // defer self.allocator.free(url);

            // ziget.request.download(
            //     try ziget.url.parseUrl(url),
            //     buf.writer(),
            //     options,
            //     &downloadState,
            // ) catch |e| switch (e) {
            //     error.UnknownUrlScheme => unreachable,
            //     else => return e,
            // };

            result.entry.value = buf.items;
        }

        emote.image = result.entry.value;
    }
}

fn noop(_: []const u8) void {}
