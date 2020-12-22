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
    @"badge-info": usize,
    badges: []const u8,
    bits: ?[]const u8,
    @"client-nonce": ?[]const u8,
    color: []const u8,
    @"display-name": []const u8,
    @"emote-only": ?bool,
    emotes: []const u8,
    flags: []const u8,
    id: []const u8,
    mod: []const u8,
    @"reply-parent-display-name": ?[]const u8,
    @"reply-parent-msg-body": ?[]const u8,
    @"reply-parent-msg-id": ?[]const u8,
    @"reply-parent-user-id": ?[]const u8,
    @"reply-parent-user-login": ?[]const u8,
    @"room-id": []const u8,
    subscriber: []const u8,
    @"tmi-sent-ts": []const u8,
    turbo: []const u8,
    @"user-id": []const u8,
    @"user-type": []const u8,
};

const tags = mecha.map(Tags, mecha.toStruct(Tags), mecha.combine(.{
    @"badge-info",                           mecha.ascii.char(';'),
    keyValue("badges", any_tag_value),       mecha.ascii.char(';'),
    mecha.opt(mecha.combine(.{
        keyValue("bits", any_tag_value), mecha.ascii.char(';'),
    })),
    mecha.opt(mecha.combine(.{
        keyValue("client-nonce", any_tag_value), mecha.ascii.char(';'),
    })),
    keyValue("color", any_tag_value),        mecha.ascii.char(';'),
    keyValue("display-name", any_tag_value), mecha.ascii.char(';'),
    mecha.opt(mecha.combine(.{
        @"emote-only", mecha.ascii.char(';'),
    })),
    keyValue("emotes", any_tag_value),       mecha.ascii.char(';'),
    keyValue("flags", any_tag_value),        mecha.ascii.char(';'),
    keyValue("id", any_tag_value),           mecha.ascii.char(';'),
    keyValue("mod", any_tag_value),          mecha.ascii.char(';'),

    mecha.opt(mecha.combine(.{
        keyValue("reply-parent-display-name", any_tag_value), mecha.ascii.char(';'),
    })),
    mecha.opt(mecha.combine(.{
        keyValue("reply-parent-msg-body", any_tag_value), mecha.ascii.char(';'),
    })),
    mecha.opt(mecha.combine(.{
        keyValue("reply-parent-msg-id", any_tag_value), mecha.ascii.char(';'),
    })),
    mecha.opt(mecha.combine(.{
        keyValue("reply-parent-user-id", any_tag_value), mecha.ascii.char(';'),
    })),
    mecha.opt(mecha.combine(.{
        keyValue("reply-parent-user-login", any_tag_value), mecha.ascii.char(';'),
    })),

    keyValue("room-id", any_tag_value),      mecha.ascii.char(';'),
    keyValue("subscriber", any_tag_value),   mecha.ascii.char(';'),
    keyValue("tmi-sent-ts", any_tag_value),  mecha.ascii.char(';'),
    keyValue("turbo", any_tag_value),        mecha.ascii.char(';'),
    keyValue("user-id", any_tag_value),      mecha.ascii.char(';'),
    keyValue("user-type", any_tag_value),
}));

const @"badge-info" = keyValue("badge-info", mecha.combine(.{
    mecha.string("subscriber/"),
    mecha.int(usize, 10),
}));

const @"emote-only" = keyValue("emote-only", mecha.map(
    bool,
    struct {
        fn toBool(i: usize) bool {
            return i != 0;
        }
    }.toBool,
    mecha.int(usize, 10),
));

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

const emoteListItem = mecha.combine(.{
    emote,
    mecha.oneOf(.{
        mecha.ascii.char('/'),
        mecha.eos,
    }),
});

const emote = mecha.combine(.{
    mecha.int(u32, 10),
    mecha.ascii.char(':'),
    mecha.int(usize, 10),
    mecha.ascii.char('-'),
    mecha.int(usize, 10),
});

pub fn parseMessage(data: []u8, alloc: *std.mem.Allocator, log: std.fs.File.Writer) !ParseResult {
    if (std.mem.startsWith(u8, data, "PING "))
        return ParseResult.ping;
    if (privmsg(data)) |res| {
        const msg = res.value;
        var time: [5]u8 = undefined;
        var now = datetime.Datetime.now().shiftTimezone(&datetime.timezones.Europe.Rome);
        _ = std.fmt.bufPrint(&time, "{d:0>2}:{d:0>2}", .{
            now.time.hour,
            now.time.minute,
        }) catch unreachable; // we know we have the space

        const count = std.mem.count(u8, msg.tags.emotes, "-");
        const emotes = try alloc.alloc(Emote, count);
        errdefer alloc.free(emotes);

        var str = msg.tags.emotes;
        for (emotes) |*em| {
            const result = emoteListItem(str) orelse return error.InvalidEmoteList;
            str = result.rest;
            em.* = .{
                .id = result.value[0],
                .start = result.value[1],
                .end = result.value[2],
            };
        }
        if (str.len != 0)
            return error.InvalidEmoteList;
        if (!std.sort.isSorted(Emote, emotes, {}, Emote.lessThan))
            return error.InvalidEmoteList;

        nosuspend log.print("message: {}\n", .{msg.message}) catch {};
        return ParseResult{
            .message = Chat.Message{
                .kind = .{
                    .chat = .{
                        .name = msg.nick,
                        .text = msg.message,
                        .time = time,
                        .meta = .{
                            .name = msg.tags.@"display-name",
                            .sub_months = msg.tags.@"badge-info",
                            .emote_only = msg.tags.@"emote-only" orelse false,
                            .emotes = emotes,
                        },
                    },
                },
            },
        };
    }

    nosuspend log.print("unknown: {}\n", .{data}) catch {};
    return error.UnknownMessage;
}
