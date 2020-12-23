const std = @import("std");
const display = @import("zbox");

log: std.fs.File.Writer,
allocator: *std.mem.Allocator,
last_message: ?*Message = null,
bottom_message: ?*Message = null,
disconnected: bool = false,

const Self = @This();

pub const Message = struct {
    prev: ?*Message = null,
    next: ?*Message = null,
    kind: union(enum) {
        chat: struct {
            name: []const u8,
            text: []const u8,
            meta: Metadata,
            time: [5]u8,
        },
        line,
    },

    pub const Metadata = struct {
        /// Author's name
        name: []const u8,
        /// Total months the user was subbed (null = non sub)
        sub_months: usize,
        /// List of emotes and their positions.
        /// Must be sorted (asc) by start position.
        emotes: []Emote = &[0]Emote{},
        /// Number of chars that need to be replaced with emotes
        emote_chars: usize = 0,
        /// The message is entirely comprised of emotes
        emote_only: bool = false,

        pub const Emote = struct {
            id: u32,
            start: usize,
            end: usize,
            image: ?[]const u8 = null,

            // Used to sort the emote list by starting poisition.
            pub fn lessThan(context: void, lhs: Emote, rhs: Emote) bool {
                return lhs.start < rhs.start;
            }
        };
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
    self.log.writeAll("scroll\n") catch unreachable;
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
    self.log.writeAll("message\n") catch unreachable;

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
