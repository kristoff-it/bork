const std = @import("std");

const Held = @TypeOf(@as(std.Thread.Mutex, undefined).impl).Held;

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
            const held = self.lock.acquire();

            if (pop(&self.getters)) |waiter| {
                held.release();
                waiter.item = item;
                loop_instance.onNextTick(&waiter.task);
                return;
            }

            if (self.tail -% self.head < self.buffer.len) {
                if (@sizeOf(T) > 0)
                    self.buffer[self.tail % self.buffer.len] = item;
                self.tail +%= 1;
                held.release();
                return;
            }

            _ = wait(&self.putters, held, item);
        }

        // Tries to put but, if full, it returns an error
        // instead of suspending.
        pub fn tryPut(self: *Self, item: T) !void {
            const held = self.lock.acquire();

            if (pop(&self.getters)) |waiter| {
                held.release();
                waiter.item = item;
                loop_instance.onNextTick(&waiter.task);
                return;
            }

            if (self.tail -% self.head < self.buffer.len) {
                if (@sizeOf(T) > 0)
                    self.buffer[self.tail % self.buffer.len] = item;
                self.tail +%= 1;
                held.release();
                return;
            }

            return error.FullChannel;
        }

        pub fn get(self: *Self) T {
            var held: Held = undefined;

            if (self.tryGet(&held)) |item|
                return item;

            return wait(&self.getters, held, undefined);
        }

        pub fn getOrNull(self: *Self) ?T {
            var held: Held = undefined;

            if (self.tryGet(&held)) |item|
                return item;

            held.release();
            return null;
        }

        fn tryGet(self: *Self, held: *Held) ?T {
            held.* = self.lock.acquire();

            if (self.tail -% self.head > 0) {
                var item: T = undefined;
                if (@sizeOf(T) > 0)
                    item = self.buffer[self.head % self.buffer.len];
                self.head +%= 1;
                held.release();
                return item;
            }

            if (pop(&self.putters)) |waiter| {
                held.release();
                const item = waiter.item;
                loop_instance.onNextTick(&waiter.task);
                return item;
            }

            return null;
        }

        fn wait(queue: *?*Waiter, held: Held, item: T) T {
            var waiter: Waiter = undefined;
            push(queue, &waiter);
            waiter.item = item;

            suspend {
                waiter.task = Task{ .data = @frame() };
                held.release();
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
