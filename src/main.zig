const std = @import("std");
const options = @import("build_options");
const datetime = @import("datetime");
const clap = @import("clap");
const zfetch = @import("zfetch");
const folders = @import("known-folders");

const Channel = @import("utils/channel.zig").Channel;
const senseUserTZ = @import("utils/sense_tz.zig").senseUserTZ;
const remote = @import("remote.zig");
const Network = @import("Network.zig");
const Terminal = @import("Terminal.zig");
const Chat = @import("Chat.zig");

pub const io_mode = .evented;

pub const Event = union(enum) {
    display: Terminal.Event,
    network: Network.Event,
    remote: remote.Server.Event,
};

// for my xdg fans out there
pub const known_folders_config = .{
    .xdg_on_mac = true,
};

pub const BorkConfig = struct {
    const version = 1;
    const path = std.fmt.comptimePrint(".bork/config_v{d}.json", .{version});
    const AfkPosition = enum {
        top,
        hover,
        bottom,

        pub fn jsonStringify(
            self: AfkPosition,
            _: std.json.StringifyOptions,
            w: std.fs.File.Writer,
        ) !void {
            try w.print(
                \\"{s}"
            , .{@tagName(self)});
        }
    };

    nick: []const u8,
    top_emoji: []const u8 = "⚡",
    remote: bool = false,
    remote_port: u16 = default_port,
    afk_position: AfkPosition = .bottom,

    // TODO what's the right size for port numbers?
    const default_port: u16 = 6226;
};

var log_level: std.log.Level = .warn;

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
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    var it = try clap.args.OsIterator.init(alloc);
    defer it.deinit();

    const subcommand = subcommand: {
        const subc_string = (try it.next()) orelse {
            printHelp();
            return;
        };

        break :subcommand std.meta.stringToEnum(Subcommand, subc_string) orelse {
            std.debug.print("Invalid subcommand.\n\n", .{});
            printHelp();
            return;
        };
    };

    const cat = try get_config_and_token(alloc, subcommand == .start);
    const config = cat.config;
    const token = cat.token;
    // const config = BorkConfig{ .nick = "blah" };
    // const token = "blah";

    switch (subcommand) {
        .start => try bork_start(alloc, config, token),
        .send => try remote.client.send(alloc, config, &it),
        .quit => try remote.client.quit(alloc, config, &it),
        .reconnect => try remote.client.reconnect(alloc, config, &it),
        .links => try remote.client.links(alloc, config, &it),
        .afk => try remote.client.afk(alloc, config, &it),
        .ban => try remote.client.ban(alloc, config, &it),
        .@"--help", .@"-h" => printHelp(),
    }
}

fn bork_start(alloc: std.mem.Allocator, config: BorkConfig, token: []const u8) !void {
    // king's fault
    defer if (config.remote) std.os.exit(0);

    var buf: [24]Event = undefined;
    var ch = Channel(Event).init(&buf);

    // If remote control is enabled, do that first
    // so that we can immediately know if there's
    // another instance of Bork running.
    var remote_server: remote.Server = undefined;
    if (config.remote) {
        remote_server.init(config, token, alloc, &ch) catch |err| {
            switch (err) {
                error.AddressInUse => {
                    std.debug.print(
                        \\ Unable to start Bork, port {} is already in use.
                        \\ Make sure all other instances of Bork are closed first.
                        \\
                    , .{config.remote_port});
                },
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
    }
    defer if (config.remote) remote_server.deinit();

    var display = try Terminal.init(alloc, &ch, config);
    defer display.deinit();

    var network: Network = undefined;
    try network.init(alloc, &ch, config.nick, token, try senseUserTZ(alloc));
    defer network.deinit();

    var chat = Chat{ .allocator = alloc, .nick = config.nick };
    // Initial paint!
    try display.renderChat(&chat);

    // Main control loop
    var chaos = false;
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
                        try display.setAfkMessage(afk.target_time, afk.reason, afk.title);
                        need_repaint = true;
                    },
                }
            },
            .display => |de| {
                switch (de) {
                    // TODO: SIGWINCH is disabled because of
                    //       rendering bugs. Re-enable .calm
                    //       and .chaos when restoring resize
                    //       signal support
                    .chaos => {
                        // chaos = true;
                    },
                    .calm => {
                        // chaos = false;
                        // try display.sizeChanged();
                        // need_repaint = true;
                    },
                    .dirty => {
                        try display.sizeChanged();
                        need_repaint = true;
                    },
                    .disableCtrlCMessage => {
                        need_repaint = try display.toggleCtrlCMessage(false);
                    },
                    .other => |c| {
                        std.log.debug("[key] [{s}]", .{c});
                        switch (c[0]) {
                            'r', 'R' => {
                                try display.sizeChanged();
                                need_repaint = true;
                                chaos = false;
                            },
                            else => {},
                        }
                    },
                    .leftClick => |pos| {
                        std.log.debug("click at {}", .{pos});
                        need_repaint = try display.handleClick(pos.row - 1, pos.col - 1);
                    },

                    .CTRL_C => {
                        if (config.remote) {
                            // TODO: show something
                            need_repaint = try display.toggleCtrlCMessage(true);
                        } else {
                            return;
                        }
                    },
                    .up, .wheelUp, .pageUp => {
                        need_repaint = chat.scroll(.up, 1);
                    },
                    .down, .wheelDown, .pageDown => {
                        need_repaint = chat.scroll(.down, 1);
                    },
                    .escape, .right, .left, .tick => {},
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
                    const msg = try display.prepareMessage(m);
                    need_repaint = chat.addMessage(msg);
                },
                .clear => |c| {
                    display.clearActiveInteraction(c);
                    chat.clearChat(c);
                    need_repaint = true;
                },
            },
        }

        need_repaint = need_repaint or display.needAnimationFrame();
        if (need_repaint and !chaos) {
            try display.renderChat(&chat);
        }
    }

    // TODO: implement real cleanup
}

var log_path: ?[]const u8 = null;
var log_file: ?std.fs.File = null;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    nosuspend {
        const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
        const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;
        const mutex = std.debug.getStderrMutex();
        mutex.lock();
        defer mutex.unlock();

        const l = log_file orelse blk: {
            const file_path = log_path orelse if (options.local)
                "bork-local.log"
            else
                return; // no logs in this case, too bad

            const log_inner = std.fs.cwd().createFile(file_path, .{ .truncate = false, .intended_io_mode = .blocking }) catch return;
            const end = log_inner.getEndPos() catch return;
            log_inner.seekTo(end) catch return;
            log_file = log_inner;
            break :blk log_inner;
        };

        const writer = l.writer();
        writer.print(prefix ++ format ++ "\n", args) catch return;
    }
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    nosuspend Terminal.panic();
    log(.err, .default, "{s}", .{msg});
    std.builtin.default_panic(msg, trace);
}

fn printHelp() void {
    std.debug.print(
        \\Bork is a TUI chat client for Twitch.
        \\
        \\Available commands: start, quit, send, links, ban, unban, afk.
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
        \\
        \\Use `bork <command> --help` to get subcommand-specific information.
        \\
    , .{});
}

const ConfigAndToken = struct {
    config: BorkConfig,
    token: []const u8,
};

fn get_config_and_token(alloc: std.mem.Allocator, check_token: bool) !ConfigAndToken {
    var base_path = (try folders.getPath(alloc, .home)) orelse
        (try folders.getPath(alloc, .executable_dir)) orelse
        @panic("couldn't find a way of creating a config file");

    var base = try std.fs.openDirAbsolute(base_path, .{});
    defer base.close();

    // Ensure existence of .bork/
    try base.makePath(".bork");

    // Prepare the log_file path for `log`.
    {
        const mutex = std.debug.getStderrMutex();
        mutex.lock();
        defer mutex.unlock();

        const log_name = if (options.local) "bork-local.log" else "bork.log";
        log_path = try std.fmt.allocPrint(alloc, "{s}/.bork/{s}", .{ base_path, log_name });
    }

    // Check if we still have an old .bork-oauth file that needs to be migrated
    var old = cleanupOldTokenAndGreet(alloc) catch null;

    var config: BorkConfig = config: {
        const file = base.openFile(BorkConfig.path, .{}) catch |err| switch (err) {
            else => return err,
            error.FileNotFound => break :config try create_config(alloc, base, base_path, old == null),
        };
        defer file.close();

        const config_json = try file.reader().readAllAlloc(alloc, 4096);
        var stream = std.json.TokenStream.init(config_json);

        const res = try std.json.parse(
            BorkConfig,
            &stream,
            .{ .allocator = alloc },
        );

        alloc.free(config_json);

        break :config res;
    };

    const port_override = std.os.getenv("BORK_PORT");
    if (port_override) |po| config.remote_port = try std.fmt.parseInt(u16, po, 10);

    const token: []const u8 = token: {
        const file = base.openFile(".bork/token.secret", .{}) catch |err| switch (err) {
            else => return err,
            error.FileNotFound => {
                if (old) |o| {
                    var token_file = try base.createFile(".bork/token.secret", .{});
                    defer token_file.close();
                    try token_file.writer().print("{s}\n", .{o.token});
                    break :token o.token;
                }
                break :token try create_token(alloc, base, .new);
            },
        };
        defer file.close();

        const token_raw = try file.reader().readAllAlloc(alloc, 4096);
        const token = std.mem.trim(u8, token_raw, " \n");

        if (check_token) {
            // Check that the token is not expired in the meantime
            if (try Network.checkTokenValidity(alloc, token)) {
                break :token token;
            }
        } else {
            break :token token;
        }

        // Token needs to be renewed
        break :token try create_token(alloc, base, .renew);
    };

    // Only delete the file if everything went ok.
    if (old) |*o| o.tryDeleteFile();

    return ConfigAndToken{
        .config = config,
        .token = token,
    };
}

const OldTokenAndPath = struct {
    const file_name = ".bork-oauth";

    token: []const u8,
    dir: std.fs.Dir,

    pub fn tryDeleteFile(self: *OldTokenAndPath) void {
        defer self.dir.close();
        self.dir.deleteFile(file_name) catch |err| {
            std.debug.print(
                \\Error while trying to delete the old .bork-oauth file:
                \\{}
                \\
            , .{err});
        };
    }
};

fn cleanupOldTokenAndGreet(alloc: std.mem.Allocator) !OldTokenAndPath {
    // Find out it the user has an old bork auth token file
    const old_dir_p = std.os.getenv("HOME") orelse ".";
    var old_dir = try std.fs.openDirAbsolute(old_dir_p, .{});
    errdefer old_dir.close();

    // error.FileNotFound will make us bail out
    const old_oauth_file = try old_dir.openFile(OldTokenAndPath.file_name, .{});
    defer old_oauth_file.close();

    const old_oauth = try old_oauth_file.reader().readAllAlloc(alloc, 150);

    return OldTokenAndPath{ .token = old_oauth, .dir = old_dir };
}

fn create_config(alloc: std.mem.Allocator, base: std.fs.Dir, base_path: []const u8, is_new_user: bool) !BorkConfig {
    const in = std.io.getStdIn();
    const in_reader = in.reader();

    if (is_new_user) {
        std.debug.print(
            \\ 
            \\ Hi, welcome to Bork!
            \\ Please input your Twich username.
            \\
            \\ Your Twitch username: 
        , .{});
    } else {
        std.debug.print(
            \\ 
            \\ Hi, you seem to be a long time user of Bork!
            \\
            \\ Thank you for putting up with the jankyness as the project
            \\ moved forward and became a reasonably functional Twitch
            \\ chat application.
            \\
            \\ This new release of bork features some improvements
            \\ that should make you happy!
            \\
            \\ - No more panicky stack traces when quitting Bork!
            \\ - No more bork.log files created in random directories!
            \\ - Bork now will automatically repaint on window resize
            \\   when running on Linux (macOS seems to have issues).
            \\ - The old `.bork-oauth` file has been cleaned up and the
            \\   token is now stored inside `.bork/` alongside a config
            \\   file and `bork.log` which has finally found a foreverhome.
            \\
            \\ Your bork config dir is located here:
            \\ 
            \\   {s}/.bork
            \\
            \\ There are also more features that will be presented soon, 
            \\ this was a special thank you note for the people that have 
            \\ been using bork for long enough to have had to pass their 
            \\ Twitch username as a command line argument every time they 
            \\ stated Bork.
            \\ 
            \\ Now that we have a config file we can finally have you 
            \\ input it once and for all :^)
            \\
            \\ Your Twitch username: 
        , .{base_path});
    }
    const nickname: []const u8 = while (true) {
        const maybe_nick_raw = try in_reader.readUntilDelimiterOrEofAlloc(alloc, '\n', 1024);

        if (maybe_nick_raw) |nick_raw| {
            const nick = std.mem.trim(u8, nick_raw, " ");

            // TODO: proper validation rules
            if (nick.len >= 3) {
                break nick;
            }

            alloc.free(nick_raw);
        }

        std.debug.print(
            \\ 
            \\ The username provided doesn't seem valid.
            \\ Please try again.
            \\ 
            \\ Your Twitch username: 
        , .{});
    } else unreachable; // TODO: remove in stage 2

    std.debug.print(
        \\
        \\ OK!
        \\
    , .{});

    const remote_port: ?u16 = remote_port: {
        // Inside this scope user input is set to immediate mode.
        {
            const original_termios = try std.os.tcgetattr(in.handle);
            defer std.os.tcsetattr(in.handle, .FLUSH, original_termios) catch {};
            {
                var termios = original_termios;
                // set immediate input mode
                termios.lflag &= ~@as(std.os.system.tcflag_t, std.os.system.ICANON);
                try std.os.tcsetattr(in.handle, .FLUSH, termios);
            }

            std.debug.print(
                \\ 
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
                \\ NOTE: some of these commands are still WIP :^)
                \\
                \\ Press any key to continue reading...
                \\
                \\
            , .{});

            _ = try in_reader.readByte();

            std.debug.print(
                \\         ======> ! IMPORTANT ! <======
                \\ To protect you from accidentally closing Bork while
                \\ streaming, with this feature enabled, Bork will not
                \\ close when you press CTRL+C. 
                \\
                \\ To close it, you will instead have to execute in a 
                \\ separate shell:
                \\
                \\                 `bork quit`
                \\ 
                \\ NOTE: yes, this command is already implemented :^)
                \\
                \\ To enable this second feature Bork will need to listen 
                \\ to a port on localhost.
                \\ 
                \\ Enable remote control? [Y/n] 
            , .{});

            const enable = try in_reader.readByte();
            switch (enable) {
                else => {
                    std.debug.print(
                        \\
                        \\
                        \\ CLI control is disabled.
                        \\ You can enable it in the future by editing the 
                        \\ configuration file.
                        \\ 
                        \\
                    , .{});
                    break :remote_port null;
                },
                'y', 'Y', '\n' => {},
            }
        }

        std.debug.print(
            \\ 
            \\ CLI control enabled!
            \\ Which port should Bork listen to?
            \\
            \\ Port? [{}]: 
        , .{BorkConfig.default_port});

        while (true) {
            const maybe_port = try in_reader.readUntilDelimiterOrEofAlloc(alloc, '\n', 1024);

            if (maybe_port) |port_raw| {
                if (port_raw.len == 0) {
                    break :remote_port BorkConfig.default_port;
                }
                break :remote_port std.fmt.parseInt(u16, port_raw, 10) catch {
                    std.debug.print(
                        \\
                        \\ Invalid port value.
                        \\ 
                        \\ Port? [{}] 
                    , .{BorkConfig.default_port});
                    continue;
                };
            } else {
                std.debug.print(
                    \\
                    \\ Success!
                    \\ 
                    \\
                , .{});
                break :remote_port BorkConfig.default_port;
            }
        }
    };

    var result: BorkConfig = .{
        .nick = nickname,
    };
    if (remote_port) |r| {
        result.remote = true;
        result.remote_port = r;
    } else {
        result.remote = false;
    }

    // create the config file
    var file = try base.createFile(BorkConfig.path, .{});

    try std.json.stringify(result, .{}, file.writer());
    return result;
}

const TokenActon = enum { new, renew };
fn create_token(alloc: std.mem.Allocator, base: std.fs.Dir, action: TokenActon) ![]const u8 {
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
            \\ oauth token you will be shown after logging in.
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

    var token_file = try base.createFile(".bork/token.secret", .{});
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
