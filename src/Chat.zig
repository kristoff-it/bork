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
        chat: []u8,
        line,
    },
};

pub fn setConnectionStatus(self: *Self, status: enum { disconnected, reconnected }) !void {
    switch (status) {
        .disconnected => self.disconnected = true,
        .reconnected => {
            if (self.disconnected) {
                self.disconnected = false;
                var msg = try self.allocator.create(Message);
                msg.* = Message{ .kind = .line };
                _ = self.addMessage(msg);
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
