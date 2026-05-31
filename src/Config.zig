const Config = @This();
const std = @import("std");
const ziggy = @import("ziggy");

youtube: bool = false,
ctrl_c_protection: bool = false,
notifications: struct {
    follows: bool = true,
    charity: bool = true,
} = .{},

pub fn get(io: std.Io, gpa: std.mem.Allocator, config_base: std.Io.Dir, stdin: *std.Io.File.Reader) !Config {
    const bytes = config_base.readFileAllocOptions(io, "bork/config.ziggy", gpa, .limited(ziggy.max_size), .fromByteUnits(1), 0) catch |err| switch (err) {
        else => return err,
        error.FileNotFound => return create(io, config_base, stdin),
    };
    defer gpa.free(bytes);

    var meta: ziggy.Deserializer.Meta = .init;
    return ziggy.deserializeLeaky(Config, gpa, bytes, &meta, .{});
}

pub fn create(io: std.Io, config_base: std.Io.Dir, stdin: *std.Io.File.Reader) !Config {
    std.debug.print(
        \\
        \\Hi, welcome to Bork!
        \\This is the initial setup procedure that will
        \\help you create an initial config file.
        \\
    , .{});

    // Inside this scope user input is set to immediate mode.
    const config: Config = blk: {
        var config: Config = .{};
        // const original_termios = try std.posix.tcgetattr(in.handle);
        // defer std.posix.tcsetattr(in.handle, .FLUSH, original_termios) catch {};
        {
            // var termios = original_termios;
            // // set immediate input mode
            // termios.lflag.ICANON = false;
            // try std.posix.tcsetattr(in.handle, .FLUSH, termios);

            std.debug.print(
                \\
                \\=============================================================
                \\
                \\Bork allows you to interact with it in three ways:
                \\
                \\- Keyboard
                \\  Up/Down Arrows and Page Up/Down will allow you to
                \\  scroll message history.
                \\
                \\- Mouse
                \\  Left click on messages to highlight them, clicking
                \\  on the message author will toggle highlight all
                \\  messages from that same user.
                \\  Wheel Up/Down to scroll message history.
                \\
                \\- Remote CLI
                \\  By invoking the `bork` command in a shell you will
                \\  be able to issue various commands, from sending
                \\  messages to issuing bans. See the full list of
                \\  commands by calling `bork help`.
                \\
                \\Press any key to continue reading...
                \\
                \\
            , .{});

            _ = try stdin.interface.discard(.limited(1));

            std.debug.print(
                \\
                \\--- YouTube Support
                \\
                \\If you plan to simulcast to both Twitch and YouTube,
                \\Bork can display live chat from both platforms in a
                \\unified stream.
                \\
                \\Enabling YouTube support will require you to authenticate
                \\with YouTube when launching Bork. You can always enable
                \\it later by modifiyng Bork's config file.
                \\
                \\Enable YouTube support? [y/N]
            , .{});

            config.youtube = switch (try stdin.interface.takeByte()) {
                else => false,
                'y', 'Y' => true,
            };

            std.debug.print(
                \\
                \\
                \\         ======> ! IMPORTANT ! <======
                \\To protect you from accidentally closing Bork while
                \\streaming, with CTRL+C protection enabled, Bork will
                \\not close when you press CTRL+C.
                \\
                \\To close it, you will instead have to execute in a
                \\separate shell:
                \\
                \\                `bork quit`
                \\
                \\Enable CTRL+C protection? [Y/n]
            , .{});

            config.ctrl_c_protection = switch (try stdin.interface.takeByte()) {
                else => false,
                'y', 'Y', '\n' => true,
            };
        }
        break :blk config;
    };

    {
        // create the config file
        var file = try config_base.createFile(io, "bork/config.ziggy", .{});
        defer file.close(io);
        var buffer: [128]u8 = undefined;
        var w = file.writer(io, &buffer);
        try w.interface.print(".ctrl_c_protection = {},\n", .{config.ctrl_c_protection});
        try w.interface.print(".youtube = {},\n", .{config.youtube});
        try w.flush();
    }

    {
        // ensure presence of the schema file
        var schema_file = try config_base.createFile(io, "bork/config.ziggy-schema", .{});
        defer schema_file.close(io);
        var buffer: [128]u8 = undefined;
        var w = schema_file.writer(io, &buffer);
        try w.interface.writeAll(@embedFile("config.ziggy-schema"));
        try w.flush();
    }

    return config;
}
