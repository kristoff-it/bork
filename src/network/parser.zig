const std = @import("std");
const mecha = @import("mecha");
const datetime = @import("datetime");
const Chat = @import("../Chat.zig");

const ParseResult = union(enum) {
    none,
    ping,
    message: *Chat.Message,
};

pub fn parseMessage(data: []u8, alloc: *std.mem.Allocator, log: std.fs.File.Writer) ParseResult {
    if (data.len == 0) return .none;

    // Split the message in  2 or 3 parts
    var it = std.mem.tokenize(data, " ");
    const metadata: ?[]const u8 = blk: {
        if (data[0] == '@') {
            break :blk it.next() orelse {
                nosuspend log.print("parser warning #1: [{}]\n", .{data}) catch {};
                return .none;
            };
        } else {
            break :blk null;
        }
    };
    nosuspend log.print("metadata: [{}]\n", .{metadata}) catch {};

    const hostname = hostname: {
        const tok = it.next() orelse {
            nosuspend log.print("parser warning #2: [{}]\n", .{data}) catch {};
            return .none;
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
        return .none;
    };
    nosuspend log.print("msgType: [{}]\n", .{msgType}) catch {};

    const channel = it.next() orelse {
        // nosuspend log.print("parser warning #??: [{}]\n", .{data}) catch {};
        return .none;
    };
    nosuspend log.print("channel: [{}]\n", .{channel}) catch {};

    // The actual chat message
    const msg = blk: {
        const rest = it.rest();
        nosuspend log.print("rest: [{}]\n", .{rest}) catch {};
        if (!std.mem.startsWith(u8, rest, ":")) {
            nosuspend log.print("parser warning #4: [{}]\n", .{data}) catch {};
            return .none;
        }
        break :blk rest[1..];
    };
    nosuspend log.print("msg: [{}]\n", .{msg}) catch {};

    // Handle each message type
    if (std.mem.eql(u8, msgType, "PRIVMSG")) {
        // Parse all the metadata
        if (!std.mem.startsWith(u8, hostname, ":")) {
            nosuspend log.print("parser warning #5: [{}]\n", .{data}) catch {};
            return .none;
        }

        const nick = std.mem.tokenize(hostname[1..], "!").next() orelse {
            nosuspend log.print("parser warning #6: [{}]\n", .{data}) catch {};
            return .none;
        };

        var time: [5]u8 = undefined;
        var now = datetime.Datetime.now().shiftTimezone(&datetime.timezones.Europe.Rome);
        _ = std.fmt.bufPrint(&time, "{d:0>2}:{d:0>2}", .{
            now.time.hour,
            now.time.minute,
        }) catch unreachable;

        var chat_message = alloc.create(Chat.Message) catch {
            // TODO: be smart about allocating
            nosuspend log.print("parser warning OOM: [{}]\n", .{data}) catch {};
            return .none;
        };
        chat_message.* = Chat.Message{
            .kind = .{
                .chat = .{ .name = nick, .text = msg, .time = time },
            },
        };

        // nosuspend log.print("msg: [{}]\n", .{chat_message.*}) catch {};
        return ParseResult{ .message = chat_message };

        // } else if (std.mem.eql(u8, msgType, "ROOMSTATE")) {
    } else {
        nosuspend log.print("parser warning unknown msg type: [{}]\n", .{data}) catch {};
        return .none;
    }
}
