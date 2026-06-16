const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const options = @import("build_options");
const datetime = @import("datetime");
const zfetch = @import("zfetch");
const folders = @import("known-folders");
const vaxis = @import("vaxis");

const logging = @import("logging.zig");
const Channel = @import("utils/channel.zig").Channel;
const remote = @import("remote.zig");
const Config = @import("Config.zig");
const Network = @import("Network.zig");
const display = @import("display.zig");
const Auth = Network.Auth;
const TwitchAuth = Network.TwitchAuth;
const YouTubeAuth = Network.YouTubeAuth;
const Chat = @import("Chat.zig");

pub const known_folders_config: folders.KnownFolderConfig = .{
    .xdg_force_default = true,
    .xdg_on_mac = true,
};

pub const std_options: std.Options = .{
    .logFn = logging.logFn,
};

// TODO: handle panic
// pub fn panic(
//     msg: []const u8,
//     error_return_trace: ?*std.builtin.StackTrace,
//     ret_addr: ?usize,
// ) noreturn {
//     display.teardown();
//     vaxis.recover();
//     std.log.err("{s}\n\n", .{msg});
//     if (error_return_trace) |t| std.debug.dumpStackTrace(t.*);
//     std.debug.dumpCurrentStackTrace(ret_addr orelse @returnAddress());
//
//     if (builtin.mode == .Debug) @breakpoint();
//     std.process.exit(1);
// }

pub const Event = union(enum) {
    display: display.Event,
    network: Network.Event,
    remote: remote.Server.Event,

    // vaxis-specific events
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    // focus_in,
};

const Subcommand = enum {
    help,
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
    yt,
    youtube,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const environ = init.environ_map;

    logging.setup(io, gpa, environ);

    var it = try init.minimal.args.iterateAllocator(gpa);
    defer it.deinit();

    _ = it.skip(); // exe name

    const subcommand = subcommand: {
        const subc_string = it.next() orelse printHelpFatal();

        break :subcommand std.meta.stringToEnum(Subcommand, subc_string) orelse {
            std.debug.print("Invalid subcommand: {s}\n\n", .{subc_string});
            printHelpFatal();
        };
    };

    var stdin_buffer: [64]u8 = undefined;
    var stdin = Io.File.stdin().reader(io, &stdin_buffer);
    var stdout_buffer: [128]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &stdout_buffer);
    var stderr_buffer: [128]u8 = undefined;
    var stderr = Io.File.stderr().writer(io, &stderr_buffer);
    switch (subcommand) {
        .start => try borkStart(io, gpa, environ, &stdin),
        .send => try remote.client.send(io, gpa, environ, &it),
        .quit => try remote.client.quit(io, gpa, environ),
        .reconnect => try remote.client.reconnect(io, gpa, environ, &it),
        .links => try remote.client.links(io, gpa, environ, &it, &stdout.interface),
        .afk => try remote.client.afk(io, gpa, environ, &it, &stderr.interface),
        .ban => try remote.client.ban(io, gpa, environ, &it),
        .youtube, .yt => try remote.client.youtube(io, gpa, environ, &it, &stdout.interface),
        .version => printVersion(),
        .help, .@"--help", .@"-h" => printHelpFatal(),
    }
    try stdout.flush();
    try stderr.flush();
}

fn borkStart(io: std.Io, gpa: std.mem.Allocator, environ: *std.process.Environ.Map, stdin: *std.Io.File.Reader) !void {
    const config_base = try folders.open(io, gpa, environ, .local_configuration, .{}) orelse
        try folders.open(io, gpa, environ, .home, .{}) orelse
        // TODO: .executable_dir removed
        // try folders.open(io, gpa, environ, .executable_dir, .{}) orelse
        std.Io.Dir.cwd();

    try config_base.createDir(io, "bork", .default_dir);

    const config = try Config.get(io, gpa, config_base, stdin);
    const auth: Network.Auth = .{
        .twitch = try TwitchAuth.get(io, gpa, config_base, &stdin.interface),
        .youtube = if (config.youtube) try YouTubeAuth.get(io, gpa, config_base, &stdin.interface) else .{},
    };

    var tty_buffer: [64]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &tty_buffer);
    defer tty.deinit();

    const tty_writer = tty.writer();
    var vx = try vaxis.init(io, gpa, environ, .{});
    defer vx.deinit(gpa, tty_writer);

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);

    try loop.start();
    defer loop.stop();

    var remote_server: remote.Server = undefined;
    remote_server.init(io, gpa, environ, auth, &loop) catch |err| {
        std.debug.print(
            \\ Unable to listen for remote control.
            \\ Error: {}
            \\
        , .{err});
        std.process.exit(1);
    };

    defer remote_server.deinit();

    var network: Network = undefined;
    try network.init(io, gpa, &loop, config, auth);
    defer network.deinit();

    var chat = Chat{ .allocator = gpa, .nick = auth.twitch.login };

    try vx.enterAltScreen(tty_writer);

    try vx.queryTerminal(tty_writer, .fromSeconds(1));

    try display.setup(io, gpa, &loop, config, &chat);
    defer display.teardown();

    // Initial paint!
    // try Display.render();

    // Main control loop
    while (true) {
        var need_repaint = false;
        const event = loop.nextEvent();
        switch (event) {
            .remote => |re| {
                switch (re) {
                    .quit => return,
                    .reconnect => {},
                    .send => |msg| {
                        std.log.debug("got send event in channel: {s}", .{msg});
                        network.sendCommand(.{ .message = msg });
                    },
                    .links => |conn| {
                        remote.Server.replyLinks(io, &chat, conn);
                    },
                    .afk => |afk| {
                        try display.setAfkMessage(afk.target_time, afk.reason, afk.title);
                        need_repaint = true;
                    },
                }
            },
            .winsize => |ws| {
                need_repaint = display.sizeChanged(.{
                    .rows = ws.rows,
                    .cols = ws.cols,
                });

                // We don't call resize directly because we
                // don't want libvaxis to allocate any memory
                // for its internal cell grid, since we render
                // everything manually.
                //
                // try vx.resize(gpa, tty.anyWriter(), ws),
                vx.screen.width = ws.cols;
                vx.screen.height = ws.rows;
                vx.screen.width_pix = ws.x_pixel;
                vx.screen.height_pix = ws.y_pixel;
            },

            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    if (config.ctrl_c_protection) {
                        need_repaint = try display.showCtrlCMessage();
                    } else {
                        break;
                    }
                } else if (key.matches(vaxis.Key.up, .{})) {
                    chat.scroll(1);
                    need_repaint = true;
                } else if (key.matches(vaxis.Key.down, .{})) {
                    chat.scroll(-1);
                    need_repaint = true;
                } else {
                    // need_repaint = true;
                    std.log.debug("key pressed: {}", .{key});
                }
            },
            .mouse => |m| {
                if (m.type != .press) continue;

                switch (m.button) {
                    else => {},
                    .left => {
                        std.log.debug("click at {}:{}", .{ m.row, m.col });
                        need_repaint = try display.handleClick(m.row + 1, m.col + 1);
                    },
                    .wheel_up => {
                        chat.scroll(1);
                        need_repaint = true;
                    },
                    .wheel_down => {
                        chat.scroll(-1);
                        need_repaint = true;
                    },
                }
            },
            .display => |de| {
                switch (de) {
                    .tick => {
                        need_repaint = display.wantTick();
                    },
                    // .left, .right => {},
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

        if (need_repaint) try display.render();
    }

    // TODO: implement real cleanup
}

fn printHelpFatal() noreturn {
    std.debug.print(
        \\Bork is a TUI chat client for Twitch.
        \\
        \\Available commands: start, quit, send, links, ban, unban, afk, version.
        \\
        \\Examples:
        \\  bork start
        \\  bork quit
        \\  bork reconnect
        \\  bork send "welcome to my stream Kappa"
        \\  bork links
        \\  bork ban "baduser"
        \\  bork unban "innocentuser"
        \\  bork afk 25m "dinner"
        \\  bork version
        \\
        \\Use `bork <command> --help` to get subcommand-specific information.
        \\
    , .{});
    std.process.exit(1);
}

fn printVersion() void {
    std.debug.print("{s}\n", .{options.version});
}
