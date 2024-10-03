const Chat = @This();

const std = @import("std");
const display = @import("zbox");
const url = @import("./utils/url.zig");

allocator: std.mem.Allocator,
nick: []const u8,
last_message: ?*Message = null,
last_link_message: ?*Message = null,
bottom_message: ?*Message = null,
scroll_offset: isize = 0,

disconnected: bool = false,

const log = std.log.scoped(.chat);

pub const Message = struct {
    prev: ?*Message = null,
    next: ?*Message = null,

    // Points to the closest previous message that contains a link.
    prev_links: ?*Message = null,
    next_links: ?*Message = null,

    login_name: []const u8,
    time: [5]u8,
    // TODO: line doesn't really have a associated login name,
    //       check how much of a problem that is.

    kind: union(enum) {
        chat: Comment,
        line,
        raid: Raid,
        resub: Resub,
        sub_mistery_gift: SubMisteryGift,
        sub_gift: SubGift,
        sub: Sub,
        follow: Follow,
        charity: Charity,
    },

    pub const Comment = struct {
        text: []const u8,
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

    pub const Follow = struct {
        display_name: []const u8,
    };
    pub const Charity = struct {
        display_name: []const u8,
        amount: []const u8,
    };

    pub const Raid = struct {
        display_name: []const u8,
        profile_picture_url: []const u8,
        /// How many raiders
        count: usize,
    };

    /// When somebody gifts X subs to random people
    pub const SubMisteryGift = struct {
        display_name: []const u8,
        count: usize,
        tier: SubTier,
    };

    pub const SubGift = struct {
        sender_display_name: []const u8,
        months: usize,
        tier: SubTier,
        recipient_login_name: []const u8,
        recipient_display_name: []const u8,
    };

    pub const Sub = struct {
        display_name: []const u8,
        tier: SubTier,
    };

    pub const Resub = struct {
        display_name: []const u8,
        count: usize,
        tier: SubTier,
        resub_message: []const u8,
        resub_message_emotes: []Emote,
    };

    // ------

    pub const SubTier = enum {
        prime,
        t1,
        t2,
        t3,

        pub fn name(self: SubTier) []const u8 {
            return switch (self) {
                .prime => "Prime",
                .t1 => "Tier 1",
                .t2 => "Tier 2",
                .t3 => "Tier 3",
            };
        }
    };

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

pub fn setConnectionStatus(self: *Chat, status: enum { disconnected, reconnected }) !void {
    switch (status) {
        .disconnected => self.disconnected = true,
        .reconnected => {
            if (self.disconnected) {
                self.disconnected = false;

                const last = self.last_message orelse return;
                if (last.kind != .line) {
                    // TODO print a line or something also it needs a time.
                    // var msg = try self.allocator.create(Message);
                    // msg.* = Message{ .kind = .line, .login_name = &[0]u8{}, tim };
                    // _ = self.addMessage(msg);
                }
            }
        },
    }
}

pub fn scroll(self: *Chat, n: isize) void {
    self.scroll_offset += n;
    if (self.scroll_offset < 0) {
        const changed = self.scrollBottomMessage(.down);
        if (!changed) self.scroll_offset = 0;
    }
}

// returns if the scroll did any effect
pub fn scrollBottomMessage(self: *Chat, direction: enum { up, down }) bool {
    log.debug("scroll {}", .{direction});

    var msg = self.bottom_message;
    if (msg) |m| {
        msg = switch (direction) {
            .up => m.prev,
            .down => m.next,
        };

        if (msg != null) {
            self.bottom_message = msg;
            return true;
        }
    }

    return false;
}

// Automatically scrolls down unless the user scrolled up.
// Returns whether there was any change in the view.
pub fn addMessage(self: *Chat, msg: *Message) bool {
    log.debug("message", .{});

    // Find if the message has URLs and attach it
    // to the URL linked list, unless it's our own
    // message.
    if (!std.mem.eql(u8, msg.login_name, self.nick)) {
        switch (msg.kind) {
            .chat => |c| {
                var it = std.mem.tokenizeScalar(u8, c.text, ' ');
                while (it.next()) |word| {
                    if (url.sense(word)) {
                        if (self.last_link_message) |old| {
                            msg.prev_links = old;
                            old.next_links = msg;
                        }

                        self.last_link_message = msg;
                        break;
                    }
                }
            },
            else => {
                // TODO: when the resub msg hack gets removed
                //       we'll need to analize also that type of message.
            },
        }
    }

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

/// TODO: we leakin, we scanning
pub fn clearChat(self: *Chat, all_or_name: ?[]const u8) void {
    if (all_or_name) |login_name| {
        log.debug("clear chat: {s}", .{login_name});
        var current = self.last_message;
        while (current) |c| : (current = c.prev) {
            if (std.mem.eql(u8, login_name, c.login_name)) {
                // Update main linked list
                {
                    if (c.prev) |p| p.next = c.next;
                    if (c.next) |n| n.prev = c.prev;

                    // If it's the last message, update the reference
                    if (c == self.last_message) self.last_message = c.prev;
                }

                // Update URLs linked list
                {
                    if (c.prev_links) |p| p.next_links = c.next_links;
                    if (c.next_links) |n| n.prev_links = c.prev_links;

                    // If it's the last message, update the reference
                    if (c == self.last_link_message) self.last_link_message = c.prev_links;
                }

                // If it's the bottom message, scroll the view
                if (self.bottom_message) |b| {
                    if (c == b) {
                        if (c.next) |n| {
                            self.bottom_message = n;
                        } else {
                            self.bottom_message = c.prev;
                        }
                    }
                }
            }
        }
    } else {
        log.debug("clear chat all", .{});
        self.last_message = null;
        self.bottom_message = null;
        self.last_link_message = null;
    }
}
