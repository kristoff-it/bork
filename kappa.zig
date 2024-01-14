const std = @import("std");

// extern fn time(?*usize) usize;
// extern fn localtime(*const usize) *tm;
// const tm = extern struct {
//     tm_sec: c_int, // seconds,  range 0 to 59
//     tm_min: c_int, // minutes, range 0 to 59
//     tm_hour: c_int, // hours, range 0 to 23
//     tm_mday: c_int, // day of the month, range 1 to 31
//     tm_mon: c_int, // month, range 0 to 11
//     tm_year: c_int, // The number of years since 1900
//     tm_wday: c_int, // day of the week, range 0 to 6
//     tm_yday: c_int, // day in the year, range 0 to 365
//     tm_isdst: c_int, // daylight saving time
//     tm_gmtoff: c_long,
//     tm_zone: [*:0]const u8,
// };
pub fn main() !void {
    // const t = time(null);
    // std.debug.print("{}\n", .{t});
    // const local = localtime(&t);

    // std.debug.print("{}\n", .{local});

    // Iterm
    std.debug.print("kappa: {c}]1337;File=inline=1;width=2;height=1;size=2164;:{}{c}\n", .{
        0x1b,
        "iVBORw0KGgoAAAANSUhEUgAAABkAAAAcCAQAAAA+LdxbAAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAAAEgAAABIAEbJaz4AAALDSURBVDjLddRLa5xlGIDh65vpJF8mk0xmJiapiSY10gNSlWorilJ0IejabRduXbkT/4H/QrEbcSG4cFURV8UDtlYQp01LaJI2hyaZUyeZ4/e6sDhJmz7bhwte3gfuqOvJ+SrkzVj2QNGl6PFt9Dj5Jaz4QeysdZueUTDk0+ip5NewpCZrRVfaqIyeNW2vmfNBdAT5OWwJghl31T1UNeqWmjmnLWlIXI4OkR9DRSJlzIoa/vYXEiUz0iqWpZzwfcSx/8CN0BTbd0+s6b51D81Zl1WyIVLStmsCj8hyqMnouGtVw55dm2YUTJq2aN0dd7Qldgak7KGWsttuq8rL6euYdN5JRW1LbvjdvgcD8puujrJl60aUTDluytvOGdeyb9KiYEVnQP4Qa1hVkRhR9KbEnDeMaunqYdh5N5UHJGXbPR2RFy2YN+84hh3T0dPXsqfggs0Bia2pGjXrdafMec6sIRmRRCQrlkjMGxuQb6IzIRKJTXnXGTGo29aQktfSQ8H4gHBMT2LG+16WQs1VN2QsKFq1bE1a3uxB8qFv5XzkHS3X/eO2mxqmjCi54ictec86NyBXw0Up153Gni23lHUVLXjJKaNiY2IzXhiQt6I/wwVBgoL3nLXmvq4TTiq5aEjasGnFgw/LmXXJlD1ZY8acUJfRE0mbt6Uo1lI7SCZNK6ir68sYkpJX0VHEpLyMYTs2DpKJKB36+tI6GrqCiqq8lnEPVLSN2NY8SGhqI6NvX0VVz/OarmjbVTetae/Rvf4ncVQOeeOCIRP6svJSFi3ZEPSVRKLDhFeja6ElK5IzbsM1Qd++WFPauIZPoscIdTtyYlVDmFazrCIxrWjt0X89EaXvQiKjK3jFnFVlq3qKdmz6InpKx/gykLcop6pmW1Nk3edHRWkwX4esvAkFfVt2VHx8IH5HEi6HfX05Qc2ezw7V8l8tNhNJnVppEAAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAxMi0wMy0wNlQxNTowMzozNS0wODowMACjc9IAAAAldEVYdGRhdGU6bW9kaWZ5ADIwMTItMDMtMDZUMTU6MDM6MzUtMDg6MDBx/stuAAAARnRFWHRzb2Z0d2FyZQBJbWFnZU1hZ2ljayA2LjYuNi0yIDIwMTAtMTItMDMgUTE2IGh0dHA6Ly93d3cuaW1hZ2VtYWdpY2sub3JnQBY9wgAAABh0RVh0VGh1bWI6OkRvY3VtZW50OjpQYWdlcwAxp/+7LwAAABd0RVh0VGh1bWI6OkltYWdlOjpoZWlnaHQAMjhTy6IIAAAAFnRFWHRUaHVtYjo6SW1hZ2U6OldpZHRoADI1VyScmwAAABl0RVh0VGh1bWI6Ok1pbWV0eXBlAGltYWdlL3BuZz+yVk4AAAAXdEVYdFRodW1iOjpNVGltZQAxMzMxMDc1MDE1jO/flwAAABF0RVh0VGh1bWI6OlNpemUAODU3QkK8TFNyAAAALXRFWHRUaHVtYjo6VVJJAGZpbGU6Ly8vdG1wL21pbmltYWdpY2sxNzcxNy0yMy5wbmcV7/n0AAAAAElFTkSuQmCC",
        // "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",
        0x07,
    });

    // kitty
    // std.debug.print("kappa: {c}_Gf=100,a=T,r=1,c=2,q=1;{}{c}\\\n", .{
    //     0x1b,
    //     "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",
    //     0x1b,
    // });
}
// const std = @import("std");

// test "fuzz" {
//     var progress: std.Progress = .{};
//     var node = try progress.start("whatever", 0);
//     var pool: ThreadPool = undefined;
//     try pool.init(std.testing.allocator);

//     var n_ran: usize = 0;
//     while (true) {
//         try testOne(node, &pool, n_ran);
//         n_ran += 1;
//     }
// }

// fn testOne(parent_node: *std.Progress.Node, pool: *ThreadPool, n_ran: usize) !void {
//     const task_name = try std.fmt.allocPrint(std.testing.allocator, "task {d}", .{n_ran});
//     defer std.testing.allocator.free(task_name);
//     const task_count = std.crypto.random.uintLessThan(usize, 100);
//     var node = parent_node.start("task", task_count);
//     defer node.end();

//     var wg: WaitGroup = undefined;
//     try wg.init();
//     defer wg.wait();

//     var i: usize = 0;
//     while (i < task_count) : (i += 1) {
//         wg.start();
//         try pool.spawn(task, .{ &node, &wg });
//     }
// }

// fn task(parent_node: *std.Progress.Node, wg: *WaitGroup) void {
//     defer wg.finish();
//     parent_node.activate();
//     work(parent_node);
// }

// fn work(parent_node: *std.Progress.Node) void {
//     const yield_count = std.crypto.random.uintLessThan(usize, 100);
//     var node = parent_node.start("work", yield_count);
//     node.activate();
//     defer node.end();

//     var i: usize = 0;
//     while (i < yield_count) : (i += 1) {
//         std.os.sched_yield() catch return;
//         node.completeOne();
//     }
// }

// const ThreadPool = struct {
//     lock: std.Mutex = .{},
//     is_running: bool = true,
//     allocator: *std.mem.Allocator,
//     workers: []Worker,
//     run_queue: RunQueue = .{},
//     idle_queue: IdleQueue = .{},

//     const IdleQueue = std.SinglyLinkedList(std.ResetEvent);
//     const RunQueue = std.SinglyLinkedList(Runnable);
//     const Runnable = struct {
//         runFn: fn (*Runnable) void,
//     };

//     const Worker = struct {
//         pool: *ThreadPool,
//         thread: *std.Thread,
//         /// The node is for this worker only and must have an already initialized event
//         /// when the thread is spawned.
//         idle_node: IdleQueue.Node,

//         fn run(worker: *Worker) void {
//             while (true) {
//                 const held = worker.pool.lock.acquire();

//                 if (worker.pool.run_queue.popFirst()) |run_node| {
//                     held.release();
//                     (run_node.data.runFn)(&run_node.data);
//                     continue;
//                 }

//                 if (worker.pool.is_running) {
//                     worker.idle_node.data.reset();

//                     worker.pool.idle_queue.prepend(&worker.idle_node);
//                     held.release();

//                     worker.idle_node.data.wait();
//                     continue;
//                 }

//                 held.release();
//                 return;
//             }
//         }
//     };

//     pub fn init(self: *ThreadPool, allocator: *std.mem.Allocator) !void {
//         self.* = .{
//             .allocator = allocator,
//             .workers = &[_]Worker{},
//         };
//         if (std.builtin.single_threaded)
//             return;

//         const worker_count = std.math.max(1, std.Thread.cpuCount() catch 1);
//         self.workers = try allocator.alloc(Worker, worker_count);
//         errdefer allocator.free(self.workers);

//         var worker_index: usize = 0;
//         errdefer self.destroyWorkers(worker_index);
//         while (worker_index < worker_count) : (worker_index += 1) {
//             const worker = &self.workers[worker_index];
//             worker.pool = self;

//             // Each worker requires its ResetEvent to be pre-initialized.
//             try worker.idle_node.data.init();
//             errdefer worker.idle_node.data.deinit();

//             worker.thread = try std.Thread.spawn(worker, Worker.run);
//         }
//     }

//     fn destroyWorkers(self: *ThreadPool, spawned: usize) void {
//         for (self.workers[0..spawned]) |*worker| {
//             worker.thread.wait();
//             worker.idle_node.data.deinit();
//         }
//     }

//     pub fn deinit(self: *ThreadPool) void {
//         {
//             const held = self.lock.acquire();
//             defer held.release();

//             self.is_running = false;
//             while (self.idle_queue.popFirst()) |idle_node|
//                 idle_node.data.set();
//         }

//         self.destroyWorkers(self.workers.len);
//         self.allocator.free(self.workers);
//     }

//     pub fn spawn(self: *ThreadPool, comptime func: anytype, args: anytype) !void {
//         if (std.builtin.single_threaded) {
//             const result = @call(.{}, func, args);
//             return;
//         }

//         const Args = @TypeOf(args);
//         const Closure = struct {
//             arguments: Args,
//             pool: *ThreadPool,
//             run_node: RunQueue.Node = .{ .data = .{ .runFn = runFn } },

//             fn runFn(runnable: *Runnable) void {
//                 const run_node = @fieldParentPtr(RunQueue.Node, "data", runnable);
//                 const closure = @fieldParentPtr(@This(), "run_node", run_node);
//                 const result = @call(.{}, func, closure.arguments);

//                 const held = closure.pool.lock.acquire();
//                 defer held.release();
//                 closure.pool.allocator.destroy(closure);
//             }
//         };

//         const held = self.lock.acquire();
//         defer held.release();

//         const closure = try self.allocator.create(Closure);
//         closure.* = .{
//             .arguments = args,
//             .pool = self,
//         };

//         self.run_queue.prepend(&closure.run_node);

//         if (self.idle_queue.popFirst()) |idle_node|
//             idle_node.data.set();
//     }
// };

// const WaitGroup = struct {
//     lock: std.Mutex = .{},
//     counter: usize = 0,
//     event: std.ResetEvent,

//     pub fn init(self: *WaitGroup) !void {
//         self.* = .{
//             .lock = .{},
//             .counter = 0,
//             .event = undefined,
//         };
//         try self.event.init();
//     }

//     pub fn deinit(self: *WaitGroup) void {
//         self.event.deinit();
//         self.* = undefined;
//     }

//     pub fn start(self: *WaitGroup) void {
//         const held = self.lock.acquire();
//         defer held.release();

//         self.counter += 1;
//     }

//     pub fn finish(self: *WaitGroup) void {
//         const held = self.lock.acquire();
//         defer held.release();

//         self.counter -= 1;

//         if (self.counter == 0) {
//             self.event.set();
//         }
//     }

//     pub fn wait(self: *WaitGroup) void {
//         while (true) {
//             const held = self.lock.acquire();

//             if (self.counter == 0) {
//                 held.release();
//                 return;
//             }

//             held.release();
//             self.event.wait();
//         }
//     }

//     pub fn reset(self: *WaitGroup) void {
//         self.event.reset();
//     }
// };
