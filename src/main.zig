const std = @import("std");
const options = @import("build_options");
const datetime = @import("datetime");
const clap = @import("clap");
const Channel = @import("utils/channel.zig").Channel;
const senseUserTZ = @import("utils/sense_tz.zig").senseUserTZ;
const Network = @import("Network.zig");
const Terminal = @import("Terminal.zig");
const Chat = @import("Chat.zig");

pub const io_mode = .evented;

pub const Event = union(enum) {
    display: Terminal.Event,
    network: Network.Event,
};

const oauth_file_name = ".bork-oauth";

var log_level: std.log.Level = .warn;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = &gpa.allocator;
    const nick = nick: {
        var it = std.process.ArgIterator.init();
        var exe_name = try (it.next(alloc) orelse @panic("no executable name as first argument!?")); // burn exe name
        defer alloc.free(exe_name);

        break :nick try (it.next(alloc) orelse {
            std.debug.print("Usage: ./bork your_channel_name\n", .{});
            return;
        });
    };

    const auth = auth: {
        // Open either $HOME path, or just use cwd.
        const maybe_home = std.os.getenv("HOME") orelse ".";
        const dir = try std.fs.cwd().openDir(maybe_home, .{});
        const oauth_file = dir.openFile(oauth_file_name, .{ .read = true, .write = true }) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print(
                    \\ 
                    \\ To connect to Twitch, bork needs a Twitch OAuth token. 
                    \\ Unfortunately, this procedure can't be fully automated
                    \\ and you will have to repeat it when the token expires
                    \\ (bork will let you know when that happens).
                    \\ 
                    \\ Please open the following URL and paste in here the
                    \\ oauth token you will be shown after logging in.
                    \\  
                    \\    https://twitchapps.com/tmi/
                    \\ 
                    \\ Token (input is hidden): 
                , .{});
                const new_file = dir.createFile(oauth_file_name, .{}) catch |err2| {
                    std.debug.print(
                        \\
                        \\ Encountered an error while trying to write to 
                        \\ 
                        \\    {s}/{s}
                        \\ 
                        \\ i.e., the file that should contain the Twitch OAuth 
                        \\ token necessary to authenticate with the service.
                        \\ 
                        \\ bork needs write permission to create that file.
                        \\ This was the error encountered: 
                        \\ 
                        \\    {e}
                        \\ 
                    , .{ maybe_home, oauth_file_name, err2 });
                    std.os.exit(1);
                };
                break :auth try askUserNewToken(alloc, maybe_home, new_file);
            },
            else => {
                std.debug.print(
                    \\
                    \\ Encountered an error while trying to open 
                    \\ 
                    \\    {s}/{s}
                    \\ 
                    \\ i.e., the file that should contain the Twitch OAuth 
                    \\ token necessary to authenticate with the service.
                    \\ 
                    \\ bork needs write permission to create that file.
                    \\ This was the error encountered: 
                    \\ 
                    \\    {e}
                    \\ 
                , .{ maybe_home, oauth_file_name, err });
                std.os.exit(1);
            },
        };

        // Found  the file, test it
        if (try oauth_file.reader().readUntilDelimiterOrEofAlloc(alloc, '\n', 1024)) |old_tok| {
            if (!try Network.checkTokenValidity(alloc, old_tok)) {
                std.debug.print(
                    \\ 
                    \\ The Twitch OAuth token expired, we must refresh it.
                    \\ 
                    \\ Please open the following URL and paste in here the
                    \\ oauth token you will be shown after logging in.
                    \\  
                    \\    https://twitchapps.com/tmi/
                    \\ 
                    \\ Token (input is hidden): 
                , .{});
                try oauth_file.seekTo(0);
                try oauth_file.setEndPos(0);
                break :auth try askUserNewToken(alloc, maybe_home, oauth_file);
            }
            break :auth old_tok;
        } else {
            std.debug.print(
                \\ 
                \\ The Twitch OAuth token expired, we must refresh it.
                \\ 
                \\ Please open the following URL and paste in here the
                \\ oauth token you will be shown after logging in.
                \\  
                \\    https://twitchapps.com/tmi/
                \\ 
                \\ Token (input is hidden): 
            , .{});
            try oauth_file.seekTo(0);
            try oauth_file.setEndPos(0);
            break :auth try askUserNewToken(alloc, maybe_home, oauth_file);
        }
    };

    var buf: [24]Event = undefined;
    var ch = Channel(Event).init(&buf);

    var display = try Terminal.init(alloc, &ch, nick);
    defer display.deinit();

    var network: Network = undefined;
    try network.init(alloc, &ch, nick, auth, senseUserTZ());
    defer network.deinit();

    var chat = Chat{ .allocator = alloc };
    // Initial paint!
    try display.renderChat(&chat);

    defer std.log.debug("leaving already?", .{});

    // Main control loop
    var chaos = false;
    while (true) {
        var need_repaint = false;

        const event = ch.get();
        switch (event) {
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

                    .CTRL_C => return,
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
            },
        }

        if (need_repaint and !chaos) {
            try display.renderChat(&chat);
        }
    }

    // TODO: implement real cleanup
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    nosuspend {
        const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
        const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;
        const held = std.debug.getStderrMutex().acquire();
        defer held.release();
        const logfile = std.fs.cwd().createFile("bork.log", .{ .truncate = false, .intended_io_mode = .blocking }) catch return;
        defer logfile.close();
        const writer = logfile.writer();
        const end = logfile.getEndPos() catch return;
        logfile.seekTo(end) catch return;
        writer.print(prefix ++ format ++ "\n", args) catch return;
    }
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    nosuspend Terminal.panic();
    log(.emerg, .default, "{s}", .{msg});
    std.builtin.default_panic(msg, trace);
}
fn askUserNewToken(alloc: *std.mem.Allocator, maybe_home: []const u8, oauth_file: std.fs.File) ![]const u8 {
    var in = std.io.getStdIn();
    const original_termios = try std.os.tcgetattr(in.handle);
    var termios = original_termios;

    // disable echo
    termios.lflag &= ~@as(std.os.tcflag_t, std.os.ECHO);

    try std.os.tcsetattr(in.handle, .FLUSH, termios);
    defer std.os.tcsetattr(in.handle, .FLUSH, original_termios) catch {};

    const tok = (try in.reader().readUntilDelimiterOrEofAlloc(alloc, '\n', 1024)) orelse "";
    if (try Network.checkTokenValidity(alloc, tok)) {
        try oauth_file.writer().print("{s}\n", .{tok});
        std.debug.print(
            \\ 
            \\ 
            \\ Success, great job!
            \\ Your token has been saved here:
            \\ 
            \\    {s}/{s}
            \\ 
            \\ Press any key to and continue.
            \\ 
        , .{ maybe_home, oauth_file_name });
        try std.os.tcsetattr(in.handle, .FLUSH, original_termios);
        _ = try in.reader().readByte();
        return tok;
    } else {
        std.debug.print(
            \\
            \\ Twitch did not accept the token, please try again.
            \\
        , .{});
        std.os.exit(1);
    }
}
