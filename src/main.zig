const std = @import("std");
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

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    display.teardown();
    vaxis.recover();
    std.log.err("{s}\n\n", .{msg});
    if (error_return_trace) |t| std.debug.dumpStackTrace(t.*);
    std.debug.dumpCurrentStackTrace(ret_addr orelse @returnAddress());

    if (builtin.mode == .Debug) @breakpoint();
    std.process.exit(1);
}

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

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_impl.allocator();

    logging.setup(gpa);

    var it = try std.process.ArgIterator.initWithAllocator(gpa);
    defer it.deinit();

    _ = it.skip(); // exe name

    const subcommand = subcommand: {
        const subc_string = it.next() orelse printHelpFatal();

        break :subcommand std.meta.stringToEnum(Subcommand, subc_string) orelse {
            std.debug.print("Invalid subcommand: {s}\n\n", .{subc_string});
            printHelpFatal();
        };
    };

    switch (subcommand) {
        .start => try borkStart(gpa),
        .send => try remote.client.send(gpa, &it),
        .quit => try remote.client.quit(gpa, &it),
        .reconnect => try remote.client.reconnect(gpa, &it),
        .links => try remote.client.links(gpa, &it),
        .afk => try remote.client.afk(gpa, &it),
        .ban => try remote.client.ban(gpa, &it),
        .youtube, .yt => try remote.client.youtube(gpa, &it),
        .version => printVersion(),
        .help, .@"--help", .@"-h" => printHelpFatal(),
    }
}

fn borkStart(gpa: std.mem.Allocator) !void {
    const config_base = try folders.open(gpa, .local_configuration, .{}) orelse
        try folders.open(gpa, .home, .{}) orelse
        try folders.open(gpa, .executable_dir, .{}) orelse
        std.fs.cwd();

    try config_base.makePath("bork");

    const config = try Config.get(gpa, config_base);
    const auth: Network.Auth = .{
        .twitch = try TwitchAuth.get(gpa, config_base),
        .youtube = if (config.youtube) try YouTubeAuth.get(gpa, config_base) else .{},
    };

    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    var vx = try vaxis.init(gpa, .{});
    defer vx.deinit(null, tty.anyWriter());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();

    try loop.start();
    defer loop.stop();

    // const remote_server: remote.Server = undefined;
    // remote_server.init(gpa, auth, &loop) catch |err| {
    //     std.debug.print(
    //         \\ Unable to listen for remote control.
    //         \\ Error: {}
    //         \\
    //     , .{err});
    //     std.process.exit(1);
    // };

    // defer remote_server.deinit();

    var network: Network = undefined;
    try network.init(gpa, &loop, config, auth);
    defer network.deinit();

    var chat = Chat{ .allocator = gpa, .nick = auth.twitch.login };

    try vx.enterAltScreen(tty.anyWriter());

    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    try display.setup(gpa, &loop, config, &chat);
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
                        remote.Server.replyLinks(&chat, conn);
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

                vx.screen.width = ws.cols;
                vx.screen.height = ws.rows;
                vx.screen.width_pix = ws.x_pixel;
                vx.screen.height_pix = ws.y_pixel;

                // try vx.resize(gpa, tty.anyWriter(), ws),
            },

            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else {
                    need_repaint = true;
                    std.log.debug("key pressed: {}", .{key});
                }
            },
            .mouse => |m| {
                if (m.type != .press) continue;
                std.log.debug("click at {}:{}", .{ m.row, m.col });
                need_repaint = try display.handleClick(m.row + 1, m.col + 1);
            },
            .display => |de| {
                switch (de) {
                    else => {},
                    .tick => {
                        need_repaint = display.wantTick();
                    },
                    // .ctrl_c => {
                    //     if (config.ctrl_c_protection) {
                    //         need_repaint = try Display.showCtrlCMessage();
                    //     } else {
                    //         return;
                    //     }
                    // },
                    // .up, .wheel_up, .page_up => {
                    //     chat.scroll(1);
                    //     need_repaint = true;
                    // },
                    // .down, .wheel_down, .page_down => {
                    //     chat.scroll(-1);
                    //     need_repaint = true;
                    // },

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
