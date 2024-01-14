const std = @import("std");

pub fn Channel(comptime T: type) type {
    return struct {
        lock: std.Thread.Mutex = .{},
        fifo: Fifo,

        const Fifo = std.fifo.LinearFifo(T, .Slice);
        const Self = @This();

        pub fn init(buffer: []T) Self {
            return Self{ .fifo = Fifo.init(buffer) };
        }

        pub fn put(self: *Self, item: T) void {
            self.lock.lock();
            defer self.lock.unlock();

            while (true) return self.fifo.writeItem(item) catch {
                self.lock.unlock();
                std.Thread.yield() catch {};
                self.lock.lock();
                continue;
            };
        }

        pub fn tryPut(self: *Self, item: T) !void {
            self.lock.lock();
            defer self.lock.unlock();

            return self.fifo.writeItem(item);
        }

        pub fn get(self: *Self) T {
            self.lock.lock();
            defer self.lock.unlock();

            while (true) return self.fifo.readItem() orelse {
                self.lock.unlock();
                std.Thread.yield() catch {};
                self.lock.lock();
                continue;
            };
        }

        pub fn getOrNull(self: *Self) ?T {
            self.lock.lock();
            defer self.lock.unlock();

            return self.fifo.readItem();
        }
    };
}
