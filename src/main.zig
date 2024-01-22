const std = @import("std");
const options = @import("build_options");
const datetime = @import("datetime");
const zfetch = @import("zfetch");
const folders = @import("known-folders");

const Channel = @import("utils/channel.zig").Channel;
const senseUserTZ = @import("utils/sense_tz.zig").senseUserTZ;
const remote = @import("remote.zig");
const Network = @import("Network.zig");
const Display = @import("Display.zig");
const Chat = @import("Chat.zig");

pub const Event = union(enum) {
    display: Display.Event,
    network: Network.Event,
    remote: remote.Server.Event,
};

// for my xdg fans out there
pub const known_folders_config = .{
    .xdg_force_default = true,
    .xdg_on_mac = true,
};

pub const BorkConfig = struct {
    nick: []const u8,
    prevent_ctrlc: bool = false,
    top_emoji: []const u8 = "⚡",
    afk_position: AfkPosition = .bottom,

    const AfkPosition = enum {
        top,
        hover,
        bottom,

        pub fn jsonStringify(
            self: AfkPosition,
            js: anytype,
        ) !void {
            try js.print(
                \\"{s}"
            , .{@tagName(self)});
        }
    };
};

const Subcommand = enum {
    @"--help",
    @"-h",
    start,
    links,
    send,
    ban,
    afk,
    quit,
    reconnect,
    version,
};

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_impl.allocator();

    setupLogging(gpa) catch @panic("could not setup logging");

    var it = try std.process.ArgIterator.initWithAllocator(gpa);
    defer it.deinit();

    _ = it.skip(); // skip exe name

    const subcommand = subcommand: {
        const subc_string = it.next() orelse printHelpFatal();

        break :subcommand std.meta.stringToEnum(Subcommand, subc_string) orelse {
            std.debug.print("Invalid subcommand: {s}\n\n", .{subc_string});
            printHelpFatal();
        };
    };

    const starting = subcommand == .start;
    if (starting) {
        std.debug.print("Checking token validity... \n", .{});
    }
    const cat = try getConfigAndToken(gpa, starting);
    const config = cat.config;
    const token = cat.token;

    switch (subcommand) {
        .start => try borkStart(gpa, config, token),
        .send => try remote.client.send(gpa, &it),
        .quit => try remote.client.quit(gpa, config, &it),
        .reconnect => try remote.client.reconnect(gpa, config, &it),
        .links => try remote.client.links(gpa, config, &it),
        .afk => try remote.client.afk(gpa, &it),
        .ban => try remote.client.ban(gpa, config, &it),
        .version => printVersion(),
        .@"--help", .@"-h" => printHelpFatal(),
    }
}

fn borkStart(alloc: std.mem.Allocator, config: BorkConfig, token: []const u8) !void {
    var buf: [24]Event = undefined;
    var ch = Channel(Event).init(&buf);

    var remote_server: remote.Server = undefined;
    remote_server.init(alloc, config, token, &ch) catch |err| {
        switch (err) {
            // error.AddressInUse => {
            //     std.debug.print(
            //         \\ Unable to start Bork, the socket is already in use.
            //         \\ Make sure all other instances of Bork are closed first.
            //         \\
            //     , .{});
            // },
            else => {
                std.debug.print(
                    \\ Unable to listen for remote control.
                    \\ Error: {}
                    \\
                , .{err});
            },
        }
        std.os.exit(1);
    };

    defer remote_server.deinit();

    std.debug.print("Connecting to Twitch... \n", .{});
    var network: Network = undefined;
    try network.init(alloc, &ch, config.nick, token, try senseUserTZ(alloc));
    defer network.deinit();

    var chat = Chat{ .allocator = alloc, .nick = config.nick };
    try Display.setup(alloc, &ch, config, &chat);
    defer Display.teardown();

    // Initial paint!
    try Display.render();

    // Main control loop
    while (true) {
        var need_repaint = false;
        const event = ch.get();
        switch (event) {
            .remote => |re| {
                switch (re) {
                    .quit => return,
                    .reconnect => {
                        network.askToReconnect();
                    },
                    .send => |msg| {
                        std.log.debug("got send event in channel: {s}", .{msg});
                        network.sendCommand(.{ .message = msg });
                    },
                    .links => |conn| {
                        remote.Server.replyLinks(&chat, conn);
                    },
                    .afk => |afk| {
                        try Display.setAfkMessage(afk.target_time, afk.reason, afk.title);
                        need_repaint = true;
                    },
                }
            },
            .display => |de| {
                switch (de) {
                    .size_changed => {
                        need_repaint = Display.sizeChanged();
                    },
                    .tick => need_repaint = true,
                    .left_click => |pos| {
                        std.log.debug("click at {}", .{pos});
                        need_repaint = try Display.handleClick(pos.row - 1, pos.col - 1);
                    },
                    .ctrl_c => {
                        if (config.prevent_ctrlc) {
                            need_repaint = try Display.showCtrlCMessage();
                        } else {
                            return;
                        }
                    },
                    .up, .wheel_up, .page_up => {
                        chat.scroll(1);
                        need_repaint = true;
                    },
                    .down, .wheel_down, .page_down => {
                        chat.scroll(-1);
                        need_repaint = true;
                    },

                    .left, .right => {},
                }
            },
            .network => |ne| switch (ne) {
                .connected => {},
                .disconnected => {
                    try chat.setConnectionStatus(.disconnected);
                    need_repaint = true;
                },
                .reconnected => {
                    try chat.setConnectionStatus(.reconnected);
                    need_repaint = true;
                },
                .message => |m| {
                    std.log.debug("got msg!", .{});
                    // Terminal wants to pre-render the message
                    // and keep a small buffer attached to the message
                    // as a form of caching.
                    const msg = try Display.prepareMessage(m);
                    need_repaint = chat.addMessage(msg);
                },
                .clear => |c| {
                    Display.clearActiveInteraction(c);
                    chat.clearChat(c);
                    need_repaint = true;
                },
            },
        }

        need_repaint = need_repaint or Display.needAnimationFrame();
        if (need_repaint) try Display.render();
    }

    // TODO: implement real cleanup
}

var log_file: ?std.fs.File = null;
pub const std_options = struct {
    var log_level: std.log.Level = .warn;
    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
        const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;
        const mutex = std.debug.getStderrMutex();
        mutex.lock();
        defer mutex.unlock();

        const l = log_file orelse {
            std.debug.print(format, args);
            return;
        };

        const writer = l.writer();
        writer.print(prefix ++ format ++ "\n", args) catch return;
    }
};

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = ret_addr;
    Display.teardown();
    std.log.err("{s}\n\n{?}", .{ msg, trace });
    @breakpoint();
    std.process.exit(1);
}

fn printHelpFatal() noreturn {
    std.debug.print(
        \\Bork is a TUI chat client for Twitch.
        \\
        \\Available commands: start, quit, send, links, ban, unban, afk, version.
        \\
        \\Examples:
        \\  ./bork start
        \\  ./bork quit
        \\  ./bork reconnect
        \\  ./bork send "welcome to my stream Kappa"
        \\  ./bork links
        \\  ./bork ban "baduser"
        \\  ./bork unban "innocentuser"
        \\  ./bork afk 25m "dinner"
        \\  ./bork version
        \\
        \\Use `bork <command> --help` to get subcommand-specific information.
        \\
    , .{});
    std.process.exit(1);
}

const ConfigAndToken = struct {
    config: BorkConfig,
    token: []const u8,
};

fn getConfigAndToken(gpa: std.mem.Allocator, check_token: bool) !ConfigAndToken {
    const config_base = try folders.open(gpa, .local_configuration, .{}) orelse
        try folders.open(gpa, .home, .{}) orelse
        try folders.open(gpa, .executable_dir, .{}) orelse
        std.fs.cwd();

    try config_base.makePath("bork");

    const config: BorkConfig = config: {
        const file = config_base.openFile("bork/config.json", .{}) catch |err| switch (err) {
            else => return err,
            error.FileNotFound => break :config try createConfig(gpa, config_base),
        };
        defer file.close();

        const config_json = try file.reader().readAllAlloc(gpa, 4096);
        const res = try std.json.parseFromSliceLeaky(BorkConfig, gpa, config_json, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });
        gpa.free(config_json);

        break :config res;
    };

    const token: []const u8 = token: {
        const file = config_base.openFile("bork/token.secret", .{}) catch |err| switch (err) {
            else => return err,
            error.FileNotFound => {
                break :token try createToken(gpa, config_base, .new);
            },
        };
        defer file.close();

        const token_raw = try file.reader().readAllAlloc(gpa, 4096);
        const token = std.mem.trim(u8, token_raw, " \n");

        if (check_token) {
            // Check that the token is not expired in the meantime
            if (try Network.checkTokenValidity(gpa, token)) {
                break :token token;
            }
        } else {
            break :token token;
        }

        // Token needs to be renewed
        break :token try createToken(gpa, config_base, .renew);
    };

    return ConfigAndToken{
        .config = config,
        .token = token,
    };
}

fn createConfig(
    gpa: std.mem.Allocator,
    config_base: std.fs.Dir,
) !BorkConfig {
    const in = std.io.getStdIn();
    const in_reader = in.reader();

    std.debug.print(
        \\
        \\ Hi, welcome to Bork!
        \\ This is the initial setup procedure that will 
        \\ help you create an initial config file.
        \\
        \\ Please input your Twich username.
        \\
        \\ Your Twitch username: 
    , .{});

    const nickname: []const u8 = while (true) {
        const maybe_nick_raw = try in_reader.readUntilDelimiterOrEofAlloc(gpa, '\n', 1024);

        if (maybe_nick_raw) |nick_raw| {
            const nick = std.mem.trim(u8, nick_raw, " ");

            // TODO: proper validation rules
            if (nick.len >= 3) {
                break nick;
            }

            gpa.free(nick_raw);
        }

        std.debug.print(
            \\
            \\ The username provided doesn't seem valid.
            \\ Please try again.
            \\
            \\ Your Twitch username:
        , .{});
    };

    // Inside this scope user input is set to immediate mode.
    const protection: bool = blk: {
        const original_termios = try std.os.tcgetattr(in.handle);
        defer std.os.tcsetattr(in.handle, .FLUSH, original_termios) catch {};
        {
            var termios = original_termios;
            // set immediate input mode
            termios.lflag &= ~@as(std.os.system.tcflag_t, std.os.system.ICANON);
            try std.os.tcsetattr(in.handle, .FLUSH, termios);

            std.debug.print(
                \\ 
                \\ ===========================================================
                \\
                \\ Bork allows you to interact with it in two ways: clicking
                \\ on messages, which will allow you to highlight them, and
                \\ by invoking the Bork executable with various subcommands 
                \\ that will interact with the main Bork instance. 
                \\
                \\ This second mode will allow you to send messages to Twitch 
                \\ chat, display popups in Bork, set AFK status, etc.
                \\ 
                \\
                \\ Press any key to continue reading...
                \\
                \\
            , .{});

            _ = try in_reader.readByte();

            std.debug.print(
                \\         ======> ! IMPORTANT ! <======
                \\ To protect you from accidentally closing Bork while
                \\ streaming, with CTRL+C protection enabled, Bork will
                \\ not close when you press CTRL+C. 
                \\
                \\ To close it, you will instead have to execute in a 
                \\ separate shell:
                \\
                \\                 `bork quit`
                \\ 
                \\ Enable CTRL+C protection? [Y/n] 
            , .{});

            const enable = try in_reader.readByte();
            switch (enable) {
                else => {
                    std.debug.print(
                        \\
                        \\
                        \\ CTRL+C protection is disabled.
                        \\ You can enable it in the future by editing the 
                        \\ configuration file.
                        \\ 
                        \\
                    , .{});
                    break :blk false;
                },
                'y', 'Y', '\n' => {
                    break :blk true;
                },
            }
        }
    };

    const result: BorkConfig = .{
        .nick = nickname,
        .prevent_ctrlc = protection,
    };

    // create the config file
    var file = try config_base.createFile("bork/config.json", .{});
    try std.json.stringify(result, .{}, file.writer());
    return result;
}

const TokenActon = enum { new, renew };
fn createToken(
    alloc: std.mem.Allocator,
    config_base: std.fs.Dir,
    action: TokenActon,
) ![]const u8 {
    var in = std.io.getStdIn();
    const original_termios = try std.os.tcgetattr(in.handle);
    var termios = original_termios;

    // disable echo
    termios.lflag &= ~@as(std.os.system.tcflag_t, std.os.system.ECHO);

    try std.os.tcsetattr(in.handle, .FLUSH, termios);
    defer std.os.tcsetattr(in.handle, .FLUSH, original_termios) catch {};

    switch (action) {
        .new => std.debug.print(
            \\
            \\ ======================================================
            \\
            \\ Bork needs a Twitch OAuth token to connect to Twitch.
            \\ Unfortunately, this procedure can't be fully automated
            \\ and you will have to repeat it when the token expires
            \\ (Bork will let you know when that happens).
            \\
            \\ Please open the following URL and paste in here the
            \\ oauth token you will be shown after logging in.
            \\
            \\    https://twitchapps.com/tmi/
            \\
            \\ Token (input is hidden):
        , .{}),
        .renew => std.debug.print(
            \\
            \\ The Twitch OAuth token expired, we must refresh it.
            \\
            \\ Please open the following URL and paste in here the
            \\ OAuth token you will be shown after logging in.
            \\
            \\    https://twitchapps.com/tmi/
            \\
            \\ Token (input is hidden):
        , .{}),
    }

    const tok = (try in.reader().readUntilDelimiterOrEofAlloc(alloc, '\n', 1024)) orelse "";
    std.debug.print(
        \\
        \\ Validating...
        \\
    , .{});

    if (!try Network.checkTokenValidity(alloc, tok)) {
        std.debug.print(
            \\
            \\ Twitch did not accept the token, please try again.
            \\
        , .{});
        std.os.exit(1);
    }

    var token_file = try config_base.createFile("bork/token.secret", .{});
    defer token_file.close();

    try token_file.writer().print("{s}\n", .{tok});
    try std.os.tcsetattr(in.handle, .FLUSH, original_termios);
    std.debug.print(
        \\
        \\
        \\ Success, great job!
        \\ Your token has been saved in your Bork config directory.
        \\
        \\ Press any key to continue.
        \\
    , .{});

    _ = try in.reader().readByte();
    return tok;
}

fn printVersion() void {
    std.debug.print("{s}\n", .{options.version});
}

fn setupLogging(gpa: std.mem.Allocator) !void {
    const cache_base = try folders.open(gpa, .cache, .{}) orelse
        try folders.open(gpa, .home, .{}) orelse
        try folders.open(gpa, .executable_dir, .{}) orelse
        std.fs.cwd();

    try cache_base.makePath("bork");

    const log_name = if (options.local) "bork-local.log" else "bork1.log";
    const log_path = try std.fmt.allocPrint(gpa, "bork/{s}", .{log_name});

    log_file = try cache_base.createFile(log_path, .{ .truncate = false });
    const end = try log_file.?.getEndPos();
    try log_file.?.seekTo(end);
}
