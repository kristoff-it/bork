const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const datetime = @import("datetime");
const zfetch = @import("zfetch");
const folders = @import("known-folders");

const logging = @import("logging.zig");
const Channel = @import("utils/channel.zig").Channel;
const senseUserTZ = @import("utils/sense_tz.zig").senseUserTZ;
const remote = @import("remote.zig");
const Config = @import("Config.zig");
const Network = @import("Network.zig");
const Auth = Network.Auth;
const Display = @import("Display.zig");
const Chat = @import("Chat.zig");

pub const known_folders_config = .{
    .xdg_force_default = true,
    .xdg_on_mac = true,
};

pub const std_options: std.Options = .{
    .logFn = logging.logFn,
};

pub fn panic(
    msg: []const u8,
    trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    _ = ret_addr;
    Display.teardown();
    std.log.err("{s}\n\n{?}", .{ msg, trace });
    if (builtin.mode == .Debug) @breakpoint();
    std.process.exit(1);
}

pub const Event = union(enum) {
    display: Display.Event,
    network: Network.Event,
    remote: remote.Server.Event,
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
        .version => printVersion(),
        .help, .@"--help", .@"-h" => printHelpFatal(),
    }
}

fn borkStart(gpa: std.mem.Allocator) !void {
    var buf: [24]Event = undefined;
    var ch = Channel(Event).init(&buf);

    const config_base = try folders.open(gpa, .local_configuration, .{}) orelse
        try folders.open(gpa, .home, .{}) orelse
        try folders.open(gpa, .executable_dir, .{}) orelse
        std.fs.cwd();

    try config_base.makePath("bork");

    const config = try Config.get(gpa, config_base);
    const auth = try Auth.get(gpa, config_base);

    var remote_server: remote.Server = undefined;
    remote_server.init(gpa, auth, &ch) catch |err| {
        std.debug.print(
            \\ Unable to listen for remote control.
            \\ Error: {}
            \\
        , .{err});
        std.os.exit(1);
    };

    defer remote_server.deinit();

    var network: Network = undefined;
    try network.init(gpa, &ch, config, auth, try senseUserTZ(gpa));
    defer network.deinit();

    var chat = Chat{ .allocator = gpa, .nick = auth.login };
    try Display.setup(gpa, &ch, config, &chat);
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
                    .reconnect => {},
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
                    .tick => {
                        need_repaint = Display.wantTick();
                    },
                    .size_changed => {
                        need_repaint = Display.sizeChanged();
                    },
                    .left_click => |pos| {
                        std.log.debug("click at {}", .{pos});
                        need_repaint = try Display.handleClick(pos.row - 1, pos.col - 1);
                    },
                    .ctrl_c => {
                        if (config.ctrl_c_protection) {
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

        if (need_repaint) try Display.render();
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
