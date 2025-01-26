const Network = @This();

const options = @import("build_options");
const std = @import("std");
const zeit = @import("zeit");
const ws = @import("ws");
const vaxis = @import("vaxis");

const GlobalEventUnion = @import("main.zig").Event;
const Chat = @import("Chat.zig");
const Config = @import("Config.zig");
const oauth = @import("network/oauth.zig");
const livechat = @import("network/youtube/livechat.zig");
const irc_parser = @import("network/twitch/irc_parser.zig");
const event_parser = @import("network/twitch/event_parser.zig");
const EmoteCache = @import("network/twitch/EmoteCache.zig");
pub const TwitchAuth = @import("network/twitch/Auth.zig");
pub const YouTubeAuth = @import("network/youtube/Auth.zig");

pub const Auth = struct {
    twitch: TwitchAuth,
    youtube: YouTubeAuth = .{},
};

pub const Event = union(enum) {
    // chat
    message: Chat.Message,
    connected,
    disconnected,
    reconnected,
    clear: ?[]const u8, // optional nickname, if empty delete all
};

pub const UserCommand = union(enum) {
    message: []const u8,
    // ban: []const u8,
};

const log = std.log.scoped(.network);
const wslog = std.log.scoped(.ws);

const Command = union(enum) {
    user: UserCommand,
    pong,
};

config: Config,
auth: Auth,
tz: zeit.TimeZone,
gpa: std.mem.Allocator,
ch: *vaxis.Loop(GlobalEventUnion),
emote_cache: EmoteCache,
socket: std.net.Stream = undefined,
writer_lock: std.Thread.Mutex = .{},

pub fn init(
    self: *Network,
    gpa: std.mem.Allocator,
    ch: *vaxis.Loop(GlobalEventUnion),
    config: Config,
    auth: Auth,
) !void {
    var env = try std.process.getEnvMap(gpa);
    defer env.deinit();
    const tz = try zeit.local(gpa, &env);

    self.* = Network{
        .config = config,
        .auth = auth,
        .tz = tz,
        .gpa = gpa,
        .ch = ch,
        .emote_cache = EmoteCache.init(gpa),
    };

    const irc_thread = try std.Thread.spawn(.{}, ircHandler, .{self});
    irc_thread.detach();

    const ws_thread = try std.Thread.spawn(.{}, wsHandler, .{self});
    ws_thread.detach();

    if (auth.youtube.enabled) {
        const yt_thread = try std.Thread.spawn(.{}, livechat.poll, .{self});
        yt_thread.detach();
    }
}

const ws_host = if (options.local) "localhost" else "eventsub.wss.twitch.tv";
fn noopSigHandler(_: c_int) callconv(.C) void {}
fn wsHandler(self: *Network) void {
    // copy and pasted from std.start.maybeIgnoreSigpipe
    // TODO make maybeIgnoreSigpipe pub so we don't have to copy and paste it
    const have_sigpipe_support = switch (@import("builtin").os.tag) {
        .linux,
        .plan9,
        .solaris,
        .netbsd,
        .openbsd,
        .haiku,
        .macos,
        .ios,
        .watchos,
        .tvos,
        .dragonfly,
        .freebsd,
        => true,

        else => false,
    };

    if (have_sigpipe_support and !std.options.keep_sigpipe) {
        // const posix = std.posix;
        // const act: posix.Sigaction = .{
        //     // Set handler to a noop function instead of `SIG.IGN` to prevent
        //     // leaking signal disposition to a child process.
        //     .handler = .{ .handler = noopSigHandler },
        //     .mask = posix.empty_sigset,
        //     .flags = 0,
        // };
        // posix.sigaction(posix.SIG.PIPE, &act, null) catch |err|
        //     std.debug.panic("failed to set noop SIGPIPE handler: {s}", .{@errorName(err)});
    }

    const h: Handler = .{ .network = self };
    while (true) {
        var retries: usize = 0;
        var client = while (true) : (retries += 1) {
            switch (retries) {
                0...1 => {},
                else => {
                    const t: usize = @min(10, 2 * retries);
                    std.time.sleep(t * std.time.ns_per_s);
                },
            }
            var client = ws.Client.init(self.gpa, .{
                .host = ws_host,
                .port = 443,
                .tls = !options.local,
            }) catch |err| {
                wslog.debug("connection failed: {s}", .{@errorName(err)});
                continue;
            };

            client.handshake("/ws", .{
                .timeout_ms = 5000,
                .headers = "Host: " ++ ws_host,
            }) catch |err| {
                wslog.debug("handshake failed: {s}", .{@errorName(err)});
                continue;
            };
            break client;
        };

        wslog.debug("connected!", .{});

        client.readLoop(h) catch |err| {
            wslog.debug("read loop failed: {s}", .{@errorName(err)});
            continue;
        };
    }
}

const Handler = struct {
    network: *Network,

    var seen_follows: std.StringHashMapUnmanaged(void) = .{};
    pub fn serverMessage(self: Handler, data: []u8) !void {
        errdefer |err| {
            wslog.debug("websocket handler errored out: {s}", .{@errorName(err)});
        }

        wslog.debug("ws event: {s}", .{data});

        const event = try event_parser.parseEvent(self.network.gpa, data);

        wslog.debug("parsed event: {any}", .{event});
        switch (event) {
            .none, .session_keepalive => {
                wslog.debug("event: {s}", .{@tagName(event)});
            },
            .charity => |c| {
                self.network.ch.postEvent(GlobalEventUnion{
                    .network = .{
                        .message = Chat.Message{
                            .login_name = c.login_name,
                            .time = c.time,
                            .kind = .{
                                .charity = .{
                                    .display_name = c.display_name,
                                    .amount = c.amount,
                                },
                            },
                        },
                    },
                });
            },
            .follower => |f| {
                const gop = try seen_follows.getOrPut(
                    self.network.gpa,
                    f.login_name,
                );
                if (!gop.found_existing) {
                    self.network.ch.postEvent(GlobalEventUnion{
                        .network = .{
                            .message = Chat.Message{
                                .login_name = f.login_name,
                                .time = f.time,
                                .kind = .{
                                    .follow = .{
                                        .display_name = f.display_name,
                                    },
                                },
                            },
                        },
                    });
                }
            },
            .session_welcome => |session_id| {
                log.debug("got session welcome, subscribing!", .{});
                const notifs = self.network.config.notifications;
                if (notifs.follows) {
                    try self.subscribeToEvent(
                        session_id,
                        "channel.follow",
                        "2",
                    );
                }
                if (notifs.charity) {
                    try self.subscribeToEvent(
                        session_id,
                        "channel.charity_campaign.donate",
                        "1",
                    );
                }
            },
        }
        // try self.network.ws_client.write(data); // echo the message back
    }

    pub fn close(_: Handler) void {}

    fn subscribeToEvent(
        self: Handler,
        session_id: []const u8,
        event_name: []const u8,
        version: []const u8,
    ) !void {
        const client_id = oauth.client_id;
        const user_id = self.network.auth.twitch.user_id;
        const token = self.network.auth.twitch.token;
        const gpa = self.network.gpa;

        var client: std.http.Client = .{
            .allocator = gpa,
        };

        const header_oauth = try std.fmt.allocPrint(
            gpa,
            "Bearer {s}",
            .{token},
        );
        defer gpa.free(header_oauth);

        const headers: []const std.http.Header = &.{
            .{
                .name = "Authorization",
                .value = header_oauth,
            },
            .{
                .name = "Client-Id",
                .value = client_id,
            },
        };

        const body_fmt =
            \\{{
            \\    "type": "{s}",
            \\    "version": "{s}",
            \\    "condition": {{
            \\        "broadcaster_user_id": "{s}",
            \\        "moderator_user_id": "{s}"
            \\    }},
            \\    "transport": {{
            \\        "method": "websocket",
            \\        "session_id": "{s}"
            \\    }}
            \\}}                        
        ;

        const body = try std.fmt.allocPrint(gpa, body_fmt, .{
            event_name, version, user_id, user_id, session_id,
        });

        const url = "https://api.twitch.tv/helix/eventsub/subscriptions";
        const result = try client.fetch(.{
            .method = .POST,
            .headers = .{
                .content_type = .{ .override = "application/json" },
            },
            .extra_headers = headers,
            .location = .{ .url = url },
            .payload = body,
        });

        log.debug("sub request reply: name: {s} code: {}", .{
            event_name,
            result.status,
        });
    }
};

pub fn deinit(self: *Network) void {
    _ = self;
    // // Try to grab the reconnecting flag
    // while (@atomicRmw(bool, &self._atomic_reconnecting, .Xchg, true, .SeqCst)) {
    //     std.time.sleep(10 * std.time.ns_per_ms);
    // }

    // // Now we can kill the connection and nobody will try to reconnect
    // std.posix.shutdown(self.socket.handle, .both) catch |err| {
    //     log.debug("shutdown failed, err: {}", .{err});
    // };
    // self.socket.close();
}

fn ircHandler(self: *Network) void {
    self.writer_lock.lock();
    while (true) {
        var retries: usize = 0;
        while (true) : (retries += 1) {
            switch (retries) {
                0...1 => {},
                else => {
                    const t: usize = @min(10, 2 * retries);
                    std.time.sleep(t * std.time.ns_per_s);
                },
            }
            self.socket = connect(
                self.gpa,
                self.auth.twitch.login,
                self.auth.twitch.token,
            ) catch |reconnect_err| {
                log.debug("reconnect attempt #{} failed: {s}", .{
                    retries,
                    @errorName(reconnect_err),
                });
                continue;
            };

            log.debug("reconnected!", .{});
            break;
        }

        self.writer_lock.unlock();

        self.receiveIrcMessages() catch |err| {
            log.debug("reconnecting after network error: {s}", .{@errorName(err)});

            self.writer_lock.lock();
            std.posix.shutdown(self.socket.handle, .both) catch |sherr| {
                log.debug("reader thread shutdown failed err: {}", .{sherr});
            };
            self.socket.close();
        };
    }
}

fn receiveIrcMessages(self: *Network) !void {
    while (true) {
        const data = data: {
            const r = self.socket.reader();
            const d = try r.readUntilDelimiterAlloc(self.gpa, '\n', 4096);
            if (d.len >= 1 and d[d.len - 1] == '\r') {
                break :data d[0 .. d.len - 1];
            }

            break :data d;
        };

        log.debug("receiveMessages succeded", .{});

        const p = irc_parser.parseMessage(data, self.gpa, &self.tz) catch |err| {
            log.debug("parsing error: [{}]", .{err});
            continue;
        };
        switch (p) {
            .ping => {
                try self.send(.pong);
            },
            .clear => |c| {
                self.ch.postEvent(GlobalEventUnion{ .network = .{ .clear = c } });
            },
            .message => |msg| {
                switch (msg.kind) {
                    else => {},
                    .chat => |c| {
                        self.emote_cache.fetch(c.emotes) catch |err| {
                            log.debug("fetching error: [{}]", .{err});
                            continue;
                        };
                    },
                    .resub => |c| {
                        self.emote_cache.fetch(c.resub_message_emotes) catch |err| {
                            log.debug("fetching error: [{}]", .{err});
                            continue;
                        };
                    },
                }

                self.ch.postEvent(GlobalEventUnion{ .network = .{ .message = msg } });

                // Hack: when receiving resub events, we generate a fake chat message
                //       to display the resub message. In the future this should be
                //       dropped in favor of actually representing properly the resub.
                //       Also this message is pointing to data that "belongs" to another
                //       message. Kind of a bad idea.
                switch (msg.kind) {
                    .resub => |r| {
                        if (r.resub_message.len > 0) {
                            self.ch.postEvent(GlobalEventUnion{
                                .network = .{
                                    .message = Chat.Message{
                                        .login_name = msg.login_name,
                                        .time = msg.time,
                                        .kind = .{
                                            .chat = .{
                                                .display_name = r.display_name,
                                                .text = r.resub_message,
                                                .sub_months = r.count,
                                                .is_founder = false, // std.mem.eql(u8, sub_badge.name, "founder"),
                                                .emotes = r.resub_message_emotes,
                                                .is_mod = false, // is_mod,
                                                .is_highlighted = true,
                                            },
                                        },
                                    },
                                },
                            });
                        }
                    },
                    else => {},
                }
            },
        }
    }
}

// Public interface for sending commands (messages, bans, ...)
pub fn sendCommand(self: *Network, cmd: UserCommand) void {
    self.send(Command{ .user = cmd }) catch {
        std.posix.shutdown(self.socket.handle, .both) catch |err| {
            log.debug("shutdown failed, err: {}", .{err});
            @panic("");
        };
    };
}

fn send(self: *Network, cmd: Command) !void {
    self.writer_lock.lock();
    defer self.writer_lock.unlock();

    const w = self.socket.writer();
    switch (cmd) {
        .pong => {
            log.debug("PONG!", .{});
            try w.print("PONG :tmi.twitch.tv\n", .{});
        },
        .user => |uc| {
            switch (uc) {
                .message => |msg| {
                    log.debug("SEND MESSAGE!", .{});
                    try w.print("PRIVMSG #{s} :{s}\n", .{
                        self.auth.twitch.login,
                        msg,
                    });
                },
            }
        },
    }
}

pub fn connect(gpa: std.mem.Allocator, name: []const u8, token: []const u8) !std.net.Stream {
    var socket = if (options.local)
        try std.net.tcpConnectToHost(gpa, "localhost", 6667)
    else
        try std.net.tcpConnectToHost(gpa, "irc.chat.twitch.tv", 6667);

    errdefer socket.close();

    const oua = if (options.local) "##SECRET##" else blk: {
        var it = std.mem.tokenizeScalar(u8, token, ' ');
        _ = it.next().?;
        break :blk it.next().?;
    };

    try socket.writer().print(
        \\PASS oauth:{0s}
        \\NICK {1s}
        \\CAP REQ :twitch.tv/tags
        \\CAP REQ :twitch.tv/commands
        \\JOIN #{1s}
        \\
    , .{ oua, name });

    // TODO: read what we got back, instead of assuming that
    //       all went well just because the bytes were shipped.

    return socket;
}
