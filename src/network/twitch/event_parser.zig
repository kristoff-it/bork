const std = @import("std");

const log = std.log.scoped(.ws);

pub const Event = union(enum) {
    none,
    session_keepalive,
    session_welcome: []const u8, // the session id
    follower: struct {
        login_name: []const u8,
        display_name: []const u8,
        time: [5]u8,
    },
    charity: struct {
        login_name: []const u8,
        display_name: []const u8,
        time: [5]u8,
        amount: []const u8,
    },
};

const MessageSausage = struct {
    metadata: struct {
        message_id: []const u8,
        message_type: []const u8,
        message_timestamp: []const u8,
        subscription_type: ?[]const u8 = null,
        subscription_version: ?[]const u8 = null,
    },
    payload: struct {
        session: ?struct {
            id: []const u8,
            status: []const u8,
            keepalive_timeout_seconds: ?usize,
            reconnect_url: ?[]const u8 = null,
            connected_at: []const u8,
        } = null,
        subscription: ?struct {
            id: []const u8,
            status: []const u8,
            type: []const u8,
            version: []const u8,
            cost: usize,
            condition: struct {},
            transport: struct {},
            created_at: []const u8,
        } = null,
        event: ?struct {
            // channel.follow
            user_login: ?[]const u8 = null,
            user_name: ?[]const u8 = null,
            // channel.charity_campaign.donate
            charity_name: ?[]const u8 = null,
            amount: ?Amount = null,
        } = null,
    },
};
const Amount = struct {
    value: usize,
    decimal_places: usize,
    currency: []const u8,
};
pub fn parseEvent(gpa: std.mem.Allocator, data: []const u8) !Event {
    const message = try std.json.parseFromSliceLeaky(MessageSausage, gpa, data, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    log.debug("ws message: {any}", .{message});

    const msg_type = message.metadata.message_type;
    if (std.mem.eql(u8, msg_type, "session_welcome")) {
        return .{
            .session_welcome = message.payload.session.?.id,
        };
    } else if (std.mem.eql(u8, msg_type, "session_keepalive")) {
        return .session_keepalive;
    } else if (std.mem.eql(u8, msg_type, "notification")) {
        return parseNotification(gpa, message);
    } else {
        log.debug("unhandled message type: {s}", .{msg_type});
        return .none;
    }
}

fn parseNotification(gpa: std.mem.Allocator, message: MessageSausage) !Event {
    const sub_type = message.metadata.subscription_type.?;
    const event = message.payload.event.?;
    if (std.mem.eql(u8, sub_type, "channel.follow")) {
        return .{
            .follower = .{
                .login_name = event.user_login.?,
                .display_name = event.user_name.?,
                .time = try getTime(message),
            },
        };
    } else if (std.mem.eql(u8, sub_type, "channel.charity_campaign.donate")) {
        return .{
            .charity = .{
                .login_name = event.user_login.?,
                .display_name = event.user_name.?,
                .time = try getTime(message),
                .amount = try parseAmount(gpa, event.amount.?),
            },
        };
    } else {
        log.debug("TODO: handle notification of type {s}", .{sub_type});
        return .none;
    }
}

fn getTime(message: MessageSausage) ![5]u8 {
    var it = std.mem.tokenizeScalar(u8, message.metadata.message_timestamp, 'T');
    _ = it.next() orelse return error.BadMessage;
    const rest = it.next() orelse return error.BadMessage;
    if (rest.len < 5) return error.BadMessage;
    return rest[0..5].*;
}

fn parseAmount(gpa: std.mem.Allocator, amount: Amount) ![]const u8 {
    var buf: [1024]u8 = undefined;
    var number = try std.fmt.bufPrint(&buf, "{}", .{amount.value});
    const split = number.len - amount.decimal_places;
    const before = number[0..split];
    const after = number[split..];
    if (std.mem.eql(u8, amount.currency, "USD")) {
        return std.fmt.allocPrint(gpa, "${s}.{s}", .{ before, after });
    } else {
        return std.fmt.allocPrint(
            gpa,
            "{s}.{s} {s}",
            .{ before, after, amount.currency },
        );
    }
}
