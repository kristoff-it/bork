const std = @import("std");
const hzzp = @import("hzzp");

fn read_timer() u64 {
    return asm volatile (
        \\rdtsc
        \\shlq $32, %%rdx
        \\orq %%rdx, %%rax
        : [ret] "={rax}" (-> u64)
        :
        : "rax", "rdx"
    );
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = &gpa.allocator;

    const response_content = try std.fs.cwd().readFileAlloc(allocator, "response.http", 2048);
    defer allocator.free(response_content);

    var lowest: u64 = std.math.maxInt(u64);
    var highest: u64 = std.math.minInt(u64);
    var average: f64 = 0.0;

    var trial: u32 = 0;
    while (trial < 1000000) : (trial += 1) {
        var response = std.io.fixedBufferStream(response_content);
        const reader = response.reader();

        const start = read_timer();

        var buffer: [256]u8 = undefined;

        var client = hzzp.base.client.create(&buffer, reader, std.io.null_writer);

        while (try client.next()) |event| {
            std.mem.doNotOptimizeAway(event);
            std.math.doNotOptimizeAway(event);
        }

        const stop = read_timer();
        const time = stop - start;

        if (time < lowest) lowest = time;
        if (time > highest) highest = time;
        average += @intToFloat(f64, time);
    }

    average = average / @intToFloat(f64, trial);

    std.debug.print("Highest: {d}\n", .{highest});
    std.debug.print("Lowest: {d}\n", .{lowest});
    std.debug.print("Average: {d:.3}\n", .{average});
}

// zig run benchmark.zig --pkg-begin hzzp ../src/main.zig --pkg-end
