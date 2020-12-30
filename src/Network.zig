const std = @import("std");
const datetime = @import("datetime");
const Channel = @import("utils/channel.zig").Channel;
const GlobalEventUnion = @import("main.zig").Event;
const Chat = @import("Chat.zig");
const parser = @import("network/parser.zig");
const EmoteCache = @import("network/EmoteCache.zig");

pub const Event = union(enum) {
    message: Chat.Message,
    connected,
    disconnected,
    reconnected,
};

pub const UserCommand = union(enum) {
    message: []const u8,
    ban: []const u8,
};
const Command = union(enum) {
    user: UserCommand,
    pong,
};

name: []const u8,
oauth: []const u8,
tz: datetime.Timezone,
allocator: *std.mem.Allocator,
ch: *Channel(GlobalEventUnion),
emote_cache: EmoteCache,
socket: std.fs.File,
reader: std.fs.File.Reader,
writer: std.fs.File.Writer,
writer_lock: std.event.Lock = .{},
_atomic_reconnecting: bool = false,

const Self = @This();

var reconnect_frame: @Frame(_reconnect) = undefined;
// var messages_frame: @Frame(receiveMessages) = undefined;
var messages_frame_bytes: []align(16) u8 = undefined;
var messages_result: void = undefined;

pub fn init(
    self: *Self,
    alloc: *std.mem.Allocator,
    ch: *Channel(GlobalEventUnion),
    name: []const u8,
    oauth: []const u8,
    tz: datetime.Timezone,
) !void {
    var socket = try connect(alloc, name, oauth);
    self.* = Self{
        .name = name,
        .oauth = oauth,
        .tz = tz,
        .allocator = alloc,
        .ch = ch,
        .emote_cache = EmoteCache.init(alloc),
        .socket = socket,
        .reader = socket.reader(),
        .writer = socket.writer(),
    };

    // Allocate
    messages_frame_bytes = try alloc.alignedAlloc(u8, @alignOf(@Frame(receiveMessages)), @sizeOf(@Frame(receiveMessages)));

    // Start the reader
    {
        // messages_frame_bytes = async self.receiveMessages();
        _ = @asyncCall(messages_frame_bytes, &messages_result, receiveMessages, .{self});
    }
}

pub fn deinit(self: *Self) void {
    // Try to grab the reconnecting flag
    while (@atomicRmw(bool, &self._atomic_reconnecting, .Xchg, true, .SeqCst)) {
        std.time.sleep(10 * std.time.ns_per_ms);
    }

    // Now we can kill the connection and nobody will try to reconnect
    std.os.shutdown(self.socket.handle, .both) catch unreachable;
    await @ptrCast(anyframe->void, messages_frame_bytes);
    self.socket.close();
}

fn receiveMessages(self: *Self) void {
    defer std.log.debug("receiveMessages done", .{});
    std.log.debug("reader started", .{});
    // yield immediately so callers can go on
    // with their lives instead of risking being
    // trapped reading a spammy socket forever
    std.event.Loop.instance.?.yield();
    while (true) {
        var data = self.reader.readUntilDelimiterAlloc(self.allocator, '\n', 4096) catch {
            std.log.debug("receiveMessages errored out", .{});
            self.reconnect(null);
            return;
        };
        std.log.debug("receiveMessages succeded", .{});

        if (data.len == 0) continue;

        const p = parser.parseMessage(data[0 .. data.len - 1], self.allocator, self.tz) catch |err| {
            std.log.debug("parsing error: [{}]", .{err});
            continue;
        };
        switch (p) {
            .ping => {
                self.send(.pong);
            },
            .message => |msg| {
                switch (msg.kind) {
                    .line => {},
                    .chat => |c| {
                        self.emote_cache.fetch(c.meta.emotes) catch |err| {
                            std.log.debug("fetching error: [{}]", .{err});
                            continue;
                        };
                    },
                }
                self.ch.put(GlobalEventUnion{ .network = .{ .message = msg } });
            },
        }
    }
}

// Public interface for sending commands (messages, bans, ...)
pub fn sendCommand(self: *Self, cmd: UserCommand) !void {
    return self.send(Command{ .user = cmd });
    if (self.isReconnecting()) {
        return error.Reconnecting;
    }

    // NOTE: it could still be possible for a command
    //       to remain stuck here while we are reconnecting,
    //       but in most cases we'll be able to correctly
    //       report that we can't carry out any command.
    //       if the twitch chat system had unique command ids,
    //       we could have opted to retry instead of failing
    //       immediately, but without unique ids you risk
    //       sending the same command twice.
}

fn send(self: *Self, cmd: Command) void {
    var held = self.writer_lock.acquire();
    var comm = switch (cmd) {
        .pong => blk: {
            std.log.debug("PONG!", .{});
            break :blk self.writer.print("PONG :tmi.twitch.tv\n", .{});
        },
        .user => {},
    };

    if (comm) |_| {} else |err| {
        // Try to start the reconnect procedure
        self.reconnect(held);
    }

    held.release();
}

fn isReconnecting(self: *self) bool {
    return @atomicLoad(bool, &self._atomic_reconnecting, .SeqCst);
}

// Tries to reconnect forever.
// As an optimization, writers can pass ownership of the lock directly.
fn reconnect(self: *Self, writer_held: ?std.event.Lock.Held) void {
    if (@atomicRmw(bool, &self._atomic_reconnecting, .Xchg, true, .SeqCst)) {
        if (writer_held) |h| h.release();
        return;
    }

    // Start the reconnect procedure
    reconnect_frame = async self._reconnect(writer_held);
}

// This function is a perfect example of what runDetached does,
// with the exception that we don't want to allocate dynamic
// memory for it.
fn _reconnect(self: *Self, writer_held: ?std.event.Lock.Held) void {
    var retries: usize = 0;
    var backoff = [_]usize{
        100, 400, 800, 2000, 5000, 10000, //ms
    };

    // Notify the system the connection is borked
    self.ch.put(GlobalEventUnion{ .network = .disconnected });

    // Ensure we have the writer lock
    var held = writer_held orelse self.writer_lock.acquire();

    // Sync with the reader. It will at one point notice
    // that the connection is borked and return.
    {
        std.os.shutdown(self.socket.handle, .both) catch unreachable;
        // await messages_frame;
        await @ptrCast(anyframe->void, messages_frame_bytes);
        self.socket.close();
    }

    // Reconnect the socket
    {
        // Compiler doesn't like the straight break from while,
        // nor the labeled block version :(

        // self.socket = while (true) {
        //     break connect(self.allocator, self.name, self.oauth) catch |err| {
        //         // TODO: panic on non-transient errors.
        //         std.time.sleep(backoff[retries] * std.time.ns_per_ms);
        //         if (retries < backoff.len - 1) {
        //             retries += 1;
        //         }
        //         continue;
        //     };
        // };

        // self.socket = blk: {
        //     while (true) {
        //         break :blk connect(self.allocator, self.name, self.oauth) catch |err| {
        //             // TODO: panic on non-transient errors.
        //             std.time.sleep(backoff[retries] * std.time.ns_per_ms);
        //             if (retries < backoff.len - 1) {
        //                 retries += 1;
        //             }
        //             continue;
        //         };
        //     }
        // };
        while (true) {
            var s = connect(self.allocator, self.name, self.oauth) catch |err| {
                // TODO: panic on non-transient errors.
                std.time.sleep(backoff[retries] * std.time.ns_per_ms);
                if (retries < backoff.len - 1) {
                    retries += 1;
                }
                continue;
            };
            self.socket = s;
            break;
        }
    }
    self.reader = self.socket.reader();
    self.writer = self.socket.writer();

    // Suspend at the end to avoid a race condition
    // where the check to resume a potential awaiter
    // (nobody should be awaiting us) might end up
    // reading the frame while a second reconnect
    // attempt is running on the same frame, causing UB.
    suspend {
        // Reset the reconnecting flag
        std.debug.assert(@atomicRmw(
            bool,
            &self._atomic_reconnecting,
            .Xchg,
            false,
            .SeqCst,
        ));

        // Unblock commands
        held.release();

        // Notify the system all is good again
        self.ch.put(GlobalEventUnion{ .network = .reconnected });

        // Restart the reader
        {
            // messages_frame = async self.receiveMessages();
            _ = @asyncCall(messages_frame_bytes, &messages_result, receiveMessages, .{self});
        }
    }
}

fn connect(alloc: *std.mem.Allocator, name: []const u8, oauth: []const u8) !std.fs.File {
    var socket = try std.net.tcpConnectToHost(alloc, "irc.chat.twitch.tv", 6667);
    // var socket = try std.net.tcpConnectToHost(alloc, "localhost", 6667);
    errdefer socket.close();

    try socket.writer().print(
        \\PASS {0}
        \\NICK {1}
        \\CAP REQ :twitch.tv/tags
        \\CAP REQ :twitch.tv/commands
        \\JOIN #{1}
        \\
    , .{ oauth, name });

    // TODO: read what we got back, instead of assuming that
    //       all went well just because the bytes were shipped.

    return socket;
}
