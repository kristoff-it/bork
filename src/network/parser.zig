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

pub fn parseMessage(data: []u8, alloc: *std.mem.Allocator, log: std.fs.File.Writer) !ParseResult {
    if (data.len == 0) return error.ParseError;

    // Split the message in  2 or 3 parts
    var it = std.mem.tokenize(data, " ");
    const metadata: ?[]const u8 = blk: {
        if (data[0] == '@') {
            const m = it.next() orelse {
                nosuspend log.print("parser warning #1: [{}]\n", .{data}) catch {};
                return error.ParseError;
            };
            break :blk m[1..]; // skips the `@`
        } else {
            break :blk null;
        }
    };
    nosuspend log.print("metadata: [{}]\n", .{metadata}) catch {};

    const hostname = hostname: {
        const tok = it.next() orelse {
            nosuspend log.print("parser warning #2: [{}]\n", .{data}) catch {};
            return error.ParseError;
        };
        if (std.mem.eql(u8, tok, "PING")) {
            nosuspend log.print("PING?\n", .{}) catch {};
            // in this case we're not really parsing the hostname, the
            // message format is garbage and flips host and message
            // type around. Anyway, we just reply pong in this case and throw away
            // the rest of the message.
            return .ping;
        }
        break :hostname tok;
    };
    nosuspend log.print("host: [{}]\n", .{hostname}) catch {};

    const msgType = it.next() orelse {
        nosuspend log.print("parser warning #3: [{}]\n", .{data}) catch {};
        return error.ParseError;
    };
    nosuspend log.print("msgType: [{}]\n", .{msgType}) catch {};

    const channel = it.next() orelse {
        // nosuspend log.print("parser warning #??: [{}]\n", .{data}) catch {};
        return error.ParseError;
    };
    nosuspend log.print("channel: [{}]\n", .{channel}) catch {};

    // The actual chat message
    const msg = blk: {
        const rest = it.rest();
        nosuspend log.print("rest: [{}]\n", .{rest}) catch {};
        if (!std.mem.startsWith(u8, rest, ":")) {
            nosuspend log.print("parser warning #4: [{}]\n", .{data}) catch {};
            return error.ParseError;
        }
        break :blk rest[1..];
    };
    nosuspend log.print("msg: [{}]\n", .{msg}) catch {};

    // Handle each message type
    if (std.mem.eql(u8, msgType, "PRIVMSG")) {
        // Parse all the necessary info
        if (!std.mem.startsWith(u8, hostname, ":")) {
            nosuspend log.print("parser warning #5: [{}]\n", .{data}) catch {};
            return error.ParseError;
        }

        const nick = std.mem.tokenize(hostname[1..], "!").next() orelse {
            nosuspend log.print("parser warning #6: [{}]\n", .{data}) catch {};
            return error.ParseError;
        };

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

        // nosuspend log.print("msg: [{}]\n", .{chat_message.*}) catch {};
        return ParseResult{
            .message = Chat.Message{
                .kind = .{
                    .chat = .{
                        .name = nick,
                        .meta = meta,
                        .text = msg,
                        .time = time,
                    },
                },
            },
        };

        // } else if (std.mem.eql(u8, msgType, "ROOMSTATE")) {
        // } else if (std.mem.eql(u8, msgType, "ROOMSTATE")) {
        // } else if (std.mem.eql(u8, msgType, "ROOMSTATE")) {
        // } else if (std.mem.eql(u8, msgType, "ROOMSTATE")) {
    } else {
        nosuspend log.print("parser warning unknown msg type: [{}]\n", .{data}) catch {};
        return error.ParseError;
    }
}

fn parseMetadata(meta: []const u8, allocator: *std.mem.Allocator, log: std.fs.File.Writer) !Metadata {
    // @badge-info=subscriber/10;badges=broadcaster/1,subscriber/0;client-nonce=1f4019806352517343d0c7ecc3e66979;color=;display-name=kristoff_it;emote-only=1;emotes=58765:76-86/25:0-4/64138:6-14,88-96/302807574:16-26,28-38/302432384:40-50,52-62,64-74;flags=;id=8e703d83-315a-4413-92e7-5328e424d08b;mod=0;room-id=102701971;subscriber=1;tmi-sent-ts=1608588730843;turbo=0;user-id=102701971;user-type=
    // emote-only=1;emotes=25:0-4,30-34/302807574:6-16,18-28;
    var result = Metadata{};

    var section_it = std.mem.tokenize(meta, ";");
    while (section_it.next()) |section| {
        const name = "display-name=";
        if (std.mem.startsWith(u8, section, name)) {
            result.name = section[name.len..];
            continue;
        }

        const sub = "badge-info=subscriber/";
        if (std.mem.startsWith(u8, section, sub)) {
            result.sub_months = try std.fmt.parseInt(usize, section[sub.len..], 10);
            continue;
        }

        const emote_only = "emote-only=1";
        if (std.mem.eql(u8, section, emote_only)) {
            result.emote_only = true;
            continue;
        }

        const emotes_str = "emotes=";
        if (std.mem.startsWith(u8, section, emotes_str)) {
            // NOTE: this message format seems to be optimizing
            //       for the wrong constraint.

            // Small hack: count the dashes to know how many emotes
            // are present in the text.
            const count = std.mem.count(u8, section[emotes_str.len..], "-");
            var emotes = try allocator.alloc(Emote, count);
            errdefer allocator.free(emotes);

            var emote_it = std.mem.tokenize(section[emotes_str.len..], "/");
            var i: usize = 0;
            while (emote_it.next()) |e| {
                const colon_pos = std.mem.indexOf(u8, e, ":") orelse return error.NoColon;
                const emote_id = try std.fmt.parseInt(u32, e[0..colon_pos], 10);

                var pos_it = std.mem.tokenize(e[colon_pos + 1 ..], ",");
                while (pos_it.next()) |pos| : (i += 1) {
                    var it = std.mem.tokenize(pos, "-");
                    const start = blk: {
                        const str = it.next() orelse return error.NoStart;
                        break :blk try std.fmt.parseInt(usize, str, 10);
                    };
                    const end = blk: {
                        const str = it.next() orelse return error.NoEnd;
                        break :blk try std.fmt.parseInt(usize, str, 10);
                    };

                    if (it.next()) |_| return error.BadMetaParsing;

                    result.emote_chars += end - start;
                    emotes[i] = Emote{
                        .id = emote_id,
                        .start = start,
                        .end = end,
                    };
                }
            }

            // Sort the array by start position
            std.sort.sort(Emote, emotes, {}, Emote.lessThan);

            {
                nosuspend log.print("emotes\n", .{}) catch {};
                for (emotes) |em| {
                    nosuspend log.print("{}\n", .{em}) catch {};
                }
                nosuspend log.print("/emotes\n", .{}) catch {};
            }

            result.emotes = emotes;
            continue;
        }
    }

    return result;
}
