const std = @import("std");
const mecha = @import("mecha");
const datetime = @import("datetime");
const Chat = @import("../Chat.zig");
const Metadata = Chat.Message.Metadata;
const Emote = Metadata.Emote;

const ParseResult = union(enum) {
    ping,
    message: Chat.Message,
};

const PrivateMessage = struct {
    tags: Tags,
    nick: []const u8,
    host: []const u8,
    channel: []const u8,
    message: []const u8,
};

const privmsg = mecha.map(PrivateMessage, mecha.toStruct(PrivateMessage), mecha.combine(.{
    mecha.ascii.char('@'),
    tags,
    mecha.string(" :"),
    nick,
    mecha.ascii.char('!'),
    host,
    mecha.string(" PRIVMSG #"),
    channel,
    mecha.string(" :"),
    mecha.rest,
}));

const nick = mecha.many(
    mecha.ascii.not(mecha.ascii.char('!')),
);

const host = mecha.many(
    mecha.ascii.not(mecha.ascii.char(' ')),
);

const channel = mecha.many(
    mecha.ascii.not(mecha.ascii.char(' ')),
);

const Tags = struct {
    @"badge-info": []const u8,
    badges: []const u8,
    @"client-nonce": []const u8,
    color: []const u8,
    @"display-name": []const u8,
    emotes: []const u8,
    flags: []const u8,
    id: []const u8,
    mod: []const u8,
    @"room-id": []const u8,
    subscriber: []const u8,
    @"tmi-sent-ts": []const u8,
    turbo: []const u8,
    @"user-id": []const u8,
    @"user-type": []const u8,
};

const tags = mecha.map(Tags, mecha.toStruct(Tags), mecha.combine(.{
    keyValue("badge-info", any_tag_value),   mecha.ascii.char(';'),
    keyValue("badges", any_tag_value),       mecha.ascii.char(';'),
    keyValue("client-nonce", any_tag_value), mecha.ascii.char(';'),
    keyValue("color", any_tag_value),        mecha.ascii.char(';'),
    keyValue("display-name", any_tag_value), mecha.ascii.char(';'),
    keyValue("emotes", any_tag_value),       mecha.ascii.char(';'),
    keyValue("flags", any_tag_value),        mecha.ascii.char(';'),
    keyValue("id", any_tag_value),           mecha.ascii.char(';'),
    keyValue("mod", any_tag_value),          mecha.ascii.char(';'),
    keyValue("room-id", any_tag_value),      mecha.ascii.char(';'),
    keyValue("subscriber", any_tag_value),   mecha.ascii.char(';'),
    keyValue("tmi-sent-ts", any_tag_value),  mecha.ascii.char(';'),
    keyValue("turbo", any_tag_value),        mecha.ascii.char(';'),
    keyValue("user-id", any_tag_value),      mecha.ascii.char(';'),
    keyValue("user-type", any_tag_value),
}));

fn keyValue(key: []const u8, value: anytype) mecha.Parser(mecha.ParserResult(@TypeOf(value))) {
    return mecha.combine(.{
        mecha.string(key ++ "="),
        value,
    });
}

const any_tag_value = mecha.many(
    mecha.ascii.not(mecha.oneOf(.{
        mecha.ascii.char(';'),
        mecha.ascii.char(' '),
    })),
);

pub fn parseMessage(data: []u8, alloc: *std.mem.Allocator, log: std.fs.File.Writer) ParseResult {
    nosuspend log.print("message: {}\n", .{data}) catch {};
    if (std.mem.startsWith(u8, data, "PING "))
        return .ping;
    if (privmsg(data)) |res| {
        const msg = res.value;
        var time: [5]u8 = undefined;
        var now = datetime.Datetime.now().shiftTimezone(&datetime.timezones.Europe.Rome);
        _ = std.fmt.bufPrint(&time, "{d:0>2}:{d:0>2}", .{
            now.time.hour,
            now.time.minute,
        }) catch unreachable; // we know we have the space

        // Parse the metadata
        const meta = try parseMetadata(metadata orelse return error.MissingMetaData, alloc, log);

        // Build Chatpoint representation
        // const cp = try buldChatpoints(alloc, metadata, msg);

        return ParseResult{
            .message = Chat.Message{
                .kind = .{
                    .chat = .{
                        .name = msg.nick,
                        .text = msg.message,
                        .time = time,
                    },
                },
            },
        };
    }

    return .none;
}
