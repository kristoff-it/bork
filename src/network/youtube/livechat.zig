const std = @import("std");
const build_opts = @import("build_options");
const Network = @import("../../Network.zig");

const log = std.log.scoped(.livechat);

const broadcasts_url = "https://www.googleapis.com/youtube/v3/liveBroadcasts?mine=true&part=id,snippet,status&maxResults=5";
const livechat_url = "https://www.googleapis.com/youtube/v3/liveChat/messages?part=id,snippet,authorDetails&liveChatId={s}&pageToken={s}";

// Must be accessed atomically, used by the `bork yt` remote command
// to set a new youtube livestream to connect to.
pub var new_chat_id: ?[*:0]const u8 = null;

pub fn poll(n: *Network) !void {
    var arena_impl = std.heap.ArenaAllocator.init(n.gpa);
    const arena = arena_impl.allocator();

    var yt: std.http.Client = .{ .allocator = n.gpa };

    var state: union(enum) {
        searching,
        attached: []const u8,
        err,
    } = .searching;

    var livechat: std.BoundedArray(u8, 4096) = .{};
    var page_token: std.BoundedArray(u8, 128) = .{};

    while (true) : (_ = arena_impl.reset(.retain_capacity)) {
        if (@atomicRmw(?[*:0]const u8, &new_chat_id, .Xchg, null, .acq_rel)) |nc| {
            const new = std.mem.span(nc);
            switch (state) {
                else => {},
                .attached => |chat_id| {
                    n.gpa.free(chat_id);
                },
            }
            state = .{ .attached = new };
            page_token.len = 0;
        }

        switch (state) {
            .err => {
                // Sleep for a bit waiting for a new remote command
                std.time.sleep(1 * std.time.ns_per_s);
            },
            .searching => {
                const maybe_chat_id = findLive(arena, n.auth.youtube.token) catch {
                    state = .err;
                    continue;
                };

                if (maybe_chat_id) |c| {
                    state = .{ .attached = try n.gpa.dupe(u8, c) };
                    continue;
                }

                std.time.sleep(3 * std.time.ns_per_s);
            },
            .attached => |chat_id| {
                livechat.len = 0;
                try livechat.writer().print(livechat_url, .{ chat_id, page_token.slice() });
                // std.debug.print("polling {s}\n", .{url_buf.items});

                var buf = std.ArrayList(u8).init(arena);
                const chat_res = yt.fetch(.{
                    .location = .{ .url = livechat.slice() },
                    .method = .GET,
                    .response_storage = .{ .dynamic = &buf },
                    .extra_headers = &.{
                        .{ .name = "Authorization", .value = n.auth.youtube.token },
                    },
                }) catch {
                    state = .err;
                    continue;
                };

                if (chat_res.status != .ok) {
                    log.err("bad reply: {s}\n{s}\n", .{
                        livechat.slice(),
                        buf.items,
                    });
                    state = .err;
                }

                const messages = std.json.parseFromSliceLeaky(Messages, arena, buf.items, .{
                    .ignore_unknown_fields = true,
                }) catch {
                    state = .err;
                    continue;
                };

                page_token.len = 0;
                page_token.appendSlice(messages.nextPageToken) catch @panic("increase pageToken buffer");

                for (messages.items) |m| {
                    const name = try n.gpa.dupe(u8, m.authorDetails.displayName);
                    const msg = try n.gpa.dupe(u8, m.snippet.textMessageDetails.messageText);

                    log.debug("{s}\n{s}\n\n", .{ name, msg });

                    n.ch.postEvent(.{
                        .network = .{
                            .message = .{
                                .login_name = name,
                                .time = "--:--".*,
                                .kind = .{
                                    .chat = .{
                                        .text = msg,
                                        .display_name = name,
                                        .sub_months = 0,
                                        .is_founder = false,
                                    },
                                },
                            },
                        },
                    });
                }

                // std.debug.print("Sleeping for {}ms", .{messages.pollingIntervalMillis});
                const delay = messages.pollingIntervalMillis * std.time.ns_per_ms;
                std.time.sleep(delay);
            },
        }
    }
}

// Searches for an active livestream and doubles as a token validation
// function since the call will fail if the token has expired.
pub fn findLive(gpa: std.mem.Allocator, token: []const u8) !?[]const u8 {
    if (build_opts.local) return .{ .enabled = false };

    var yt: std.http.Client = .{ .allocator = gpa };
    defer yt.deinit();

    var buf = std.ArrayList(u8).init(gpa);
    defer buf.deinit();

    const res = try yt.fetch(.{
        .location = .{ .url = broadcasts_url },
        .method = .GET,
        .response_storage = .{ .dynamic = &buf },
        .extra_headers = &.{
            .{ .name = "Authorization", .value = token },
        },
    });

    if (res.status != .ok) {
        return error.InvalidToken;
    }

    const lives = try std.json.parseFromSlice(LiveBroadcasts, gpa, buf.items, .{
        .ignore_unknown_fields = true,
    });
    defer lives.deinit();

    const chat_id: ?[]const u8 = for (lives.value.items) |l| {
        if (std.mem.eql(u8, l.status.lifeCycleStatus, "live")) break try gpa.dupe(u8, l.snippet.liveChatId);
    } else null;

    return chat_id;
}

pub const LiveBroadcasts = struct {
    items: []const struct {
        id: []const u8,
        snippet: struct {
            channelId: []const u8,
            liveChatId: []const u8,
            title: []const u8,
        },
        status: struct {
            lifeCycleStatus: []const u8,
        },
    },
};

const Messages = struct {
    nextPageToken: []const u8,
    offlineAt: ?[]const u8 = null,
    pollingIntervalMillis: usize,
    items: []const ChatMessage,

    pub const ChatMessage = struct {
        snippet: struct {
            textMessageDetails: struct {
                messageText: []const u8,
            },
        },
        authorDetails: struct {
            displayName: []const u8,
        },
    };
};
