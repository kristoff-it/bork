const std = @import("std");
const display = @import("zbox");

allocator: *std.mem.Allocator,
last_message: ?*Message = null,
bottom_message: ?*Message = null,
disconnected: bool = false,

const Self = @This();

pub const Message = struct {
    prev: ?*Message = null,
    next: ?*Message = null,
    kind: union(enum) {
        chat: Comment,
        line,
        raid: Raid,
        resub: Resub,
        sub_mistery_gift: SubMisteryGift,
        sub_gift: SubGift,
        sub: Sub,
    },

    pub const Comment = struct {
        login_name: []const u8,
        text: []const u8,
        time: [5]u8,
        /// Author's name (w/ unicode support, empty if not present)
        display_name: []const u8,
        /// Total months the user was subbed (0 = non sub)
        sub_months: usize,
        /// Does the user have a founder badge?
        is_founder: bool,
        /// List of emotes and their position. Must be sorted (asc) by end position
        emotes: []Emote = &[0]Emote{},
        /// Moderator status
        is_mod: bool = false,
        /// Highlighed message by redeeming points
        is_highlighted: bool = false,
    };

    pub const Raid = struct {
        login_name: []const u8,
        display_name: []const u8,
        profile_picture_url: []const u8,
        /// How many raiders
        count: usize,
    };

    /// When somebody gifts X subs to random people
    pub const SubMisteryGift = struct {
        login_name: []const u8,
        display_name: []const u8,
        count: usize,
        tier: SubTier,
    };

    pub const SubGift = struct {
        sender_login_name: []const u8,
        sender_display_name: []const u8,
        months: usize,
        tier: SubTier,
        recipient_login_name: []const u8,
        recipient_display_name: []const u8,
    };

    pub const Sub = struct {
        login_name: []const u8,
        display_name: []const u8,
        tier: SubTier,
    };
    pub const Resub = struct {
        login_name: []const u8,
        display_name: []const u8,
        count: usize,
        tier: SubTier,
        time: [5]u8,
        resub_message: []const u8,
        resub_message_emotes: []Emote,
    };
    // ------

    pub const SubTier = enum { prime, t1, t2, t3 };
    pub const Emote = struct {
        twitch_id: []const u8,
        start: usize,
        end: usize,
        img_data: ?[]const u8 = null, // TODO: should this be in
        idx: u32 = 0, // surely this will never cause problematic bugs
        // Used to sort the emote list by ending poisition.
        pub fn lessThan(_: void, lhs: Emote, rhs: Emote) bool {
            return lhs.end < rhs.end;
        }
    };
};

pub fn setConnectionStatus(self: *Self, status: enum { disconnected, reconnected }) !void {
    switch (status) {
        .disconnected => self.disconnected = true,
        .reconnected => {
            if (self.disconnected) {
                self.disconnected = false;

                const last = self.last_message orelse return;
                if (last.kind != .line) {
                    var msg = try self.allocator.create(Message);
                    msg.* = Message{ .kind = .line };
                    _ = self.addMessage(msg);
                }
            }
        },
    }
}

// Returns whether the scroll had any effect.
pub fn scroll(self: *Self, direction: enum { up, down }, n: usize) bool {
    std.log.debug("scroll", .{});
    var i = n;
    var msg = self.bottom_message;
    while (i > 0) : (i -= 1) {
        if (msg) |m| {
            msg = switch (direction) {
                .up => m.prev,
                .down => m.next,
            };

            if (msg != null) {
                self.bottom_message = msg;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    return i != n;
}

// Automatically scrolls down unless the user scrolled up.
// Returns whether there was any change in the view.
pub fn addMessage(self: *Self, msg: *Message) bool {
    std.log.debug("message", .{});

    var need_render = false;
    if (self.last_message == self.bottom_message) {
        // Scroll!
        self.bottom_message = msg;
        need_render = true;
    }

    if (self.last_message) |last| {
        last.next = msg;
        msg.prev = self.last_message;
    }

    self.last_message = msg;

    return need_render;
}
