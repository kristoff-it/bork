const std = @import("std");

pub fn Channel(comptime T: type) type {
    return struct {
        lock: std.Thread.Mutex = .{},
        buffer: []T,
        head: usize = 0,
        tail: usize = 0,
        getters: ?*Waiter = null,
        putters: ?*Waiter = null,

        const Task = std.event.Loop.NextTickNode;
        const loop_instance = std.event.Loop.instance orelse {
            @compileError("Only supported in evented mode");
        };

        const Self = @This();
        const Waiter = struct {
            next: ?*Waiter,
            tail: *Waiter,
            item: T,
            task: Task,
        };

        pub fn init(buffer: []T) Self {
            return Self{ .buffer = buffer };
        }

        pub fn put(self: *Self, item: T) void {
            self.lock.lock();

            if (pop(&self.getters)) |waiter| {
                self.lock.unlock();
                waiter.item = item;
                loop_instance.onNextTick(&waiter.task);
                return;
            }

            if (self.tail -% self.head < self.buffer.len) {
                if (@sizeOf(T) > 0)
                    self.buffer[self.tail % self.buffer.len] = item;
                self.tail +%= 1;
                self.lock.unlock();
                return;
            }

            _ = wait(&self.putters, &self.lock, item);
        }

        // Tries to put but, if full, it returns an error
        // instead of suspending.
        pub fn tryPut(self: *Self, item: T) !void {
            self.lock.lock();
            defer self.lock.unlock();

            if (pop(&self.getters)) |waiter| {
                waiter.item = item;
                loop_instance.onNextTick(&waiter.task);
                return;
            }

            if (self.tail -% self.head < self.buffer.len) {
                if (@sizeOf(T) > 0)
                    self.buffer[self.tail % self.buffer.len] = item;
                self.tail +%= 1;
                return;
            }

            return error.FullChannel;
        }

        pub fn get(self: *Self) T {
            if (self.tryGet()) |item|
                return item;

            return wait(&self.getters, &self.lock, undefined);
        }

        pub fn getOrNull(self: *Self) ?T {
            if (self.tryGet()) |item|
                return item;

            self.lock.unlock();
            return null;
        }

        fn tryGet(self: *Self) ?T {
            self.lock.lock();

            if (self.tail -% self.head > 0) {
                var item: T = undefined;
                if (@sizeOf(T) > 0)
                    item = self.buffer[self.head % self.buffer.len];
                self.head +%= 1;
                self.lock.unlock();
                return item;
            }

            if (pop(&self.putters)) |waiter| {
                self.lock.unlock();
                const item = waiter.item;
                loop_instance.onNextTick(&waiter.task);
                return item;
            }

            return null;
        }

        fn wait(queue: *?*Waiter, held: *std.Thread.Mutex, item: T) T {
            var waiter: Waiter = undefined;
            push(queue, &waiter);
            waiter.item = item;

            suspend {
                waiter.task = Task{ .data = @frame() };
                held.unlock();
            }

            return waiter.item;
        }

        fn push(queue: *?*Waiter, waiter: *Waiter) void {
            waiter.next = null;
            if (queue.*) |head| {
                head.tail.next = waiter;
                head.tail = waiter;
            } else {
                waiter.tail = waiter;
                queue.* = waiter;
            }
        }

        fn pop(queue: *?*Waiter) ?*Waiter {
            const waiter = queue.* orelse return null;
            queue.* = waiter.next;
            if (queue.*) |new_head|
                new_head.tail = waiter.tail;
            return waiter;
        }
    };
}
