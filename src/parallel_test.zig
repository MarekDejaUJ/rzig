//! Parallel worker tests using only plain Zig state.

const std = @import("std");
const c = @import("c/abi.zig");
const Ctx = @import("alloc.zig").Ctx;
const es = @import("error_state.zig");
const parallel = @import("parallel.zig");
const rng = @import("rng.zig");

// Stand-ins for R: the calling thread checks for interrupts while it waits.
var interrupt_requested = std.atomic.Value(bool).init(false);

export fn R_ToplevelExec(
    callback: *const fn (?*anyopaque) callconv(.c) void,
    data: ?*anyopaque,
) c.Rboolean {
    if (interrupt_requested.load(.monotonic)) return c.FALSE;
    callback(data);
    return c.TRUE;
}

export fn R_CheckUserInterrupt() void {}

const Work = struct {
    input: []const f64,
    output: []f64,
    thread_ids: []std.Thread.Id,

    fn square(work: *Work, index: usize) void {
        work.output[index] = work.input[index] * work.input[index];
        work.thread_ids[index] = std.Thread.getCurrentId();
    }
};

test "parallelFor covers each index on worker threads" {
    var ctx = Ctx.init();
    defer ctx.deinit();
    const input = [_]f64{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var output: [input.len]f64 = @splat(0);
    var thread_ids: [input.len]std.Thread.Id = @splat(0);
    var work = Work{ .input = &input, .output = &output, .thread_ids = &thread_ids };
    const caller_id = std.Thread.getCurrentId();

    try parallel.parallelFor(&ctx, input.len, &work, Work.square);

    try std.testing.expectEqualSlices(f64, &.{ 1, 4, 9, 16, 25, 36, 49, 64 }, &output);
    for (thread_ids) |thread_id| try std.testing.expect(thread_id != caller_id);
}

test "parallelFor accepts empty ranges without invoking the worker" {
    var ctx = Ctx.init();
    defer ctx.deinit();
    var output: [0]f64 = .{};
    var thread_ids: [0]std.Thread.Id = .{};
    var work = Work{ .input = &.{}, .output = &output, .thread_ids = &thread_ids };
    try parallel.parallelFor(&ctx, 0, &work, Work.square);
}

test "thread limits parse positive whole numbers only" {
    try std.testing.expectEqual(@as(?usize, 4), parallel.parseThreadLimit("4"));
    try std.testing.expectEqual(@as(?usize, 3), parallel.parseThreadLimit(" 3\n"));
    try std.testing.expectEqual(@as(?usize, null), parallel.parseThreadLimit("0"));
    try std.testing.expectEqual(@as(?usize, null), parallel.parseThreadLimit("-2"));
    try std.testing.expectEqual(@as(?usize, null), parallel.parseThreadLimit("two"));
    try std.testing.expectEqual(@as(?usize, null), parallel.parseThreadLimit(""));
}

test "the R CMD check core limit is active unless it is false" {
    try std.testing.expect(parallel.checkLimitsCores("TRUE"));
    try std.testing.expect(parallel.checkLimitsCores("warn"));
    try std.testing.expect(!parallel.checkLimitsCores("false"));
    try std.testing.expect(!parallel.checkLimitsCores("FALSE"));
}

test "threadCount never exceeds the number of indices" {
    try std.testing.expectEqual(@as(usize, 0), try parallel.threadCount(0));
    try std.testing.expectEqual(@as(usize, 1), try parallel.threadCount(1));
    try std.testing.expect(try parallel.threadCount(1000) <= 32);
}

const Sum = struct {
    values: []const f64,

    fn value(sum: *const Sum, index: usize) f64 {
        return sum.values[index];
    }

    fn add(left: f64, right: f64) f64 {
        return left + right;
    }
};

test "parallelReduce gives one result for every number of threads" {
    var ctx = Ctx.init();
    defer ctx.deinit();
    var values: [5000]f64 = undefined;
    for (&values, 0..) |*value, index| value.* = 1.0 / @as(f64, @floatFromInt(index + 1));
    const sum = Sum{ .values = &values };
    const total = try parallel.parallelReduce(&ctx, f64, values.len, &sum, 0, Sum.value, Sum.add);
    var expected: f64 = 0;
    const chunks = 1024;
    var chunk: usize = 0;
    while (chunk < chunks) : (chunk += 1) {
        var accumulated: f64 = 0;
        for (chunk * values.len / chunks..(chunk + 1) * values.len / chunks) |index| accumulated += values[index];
        expected += accumulated;
    }
    try std.testing.expectEqual(expected, total);
    try std.testing.expectEqual(@as(f64, 0), try parallel.parallelReduce(&ctx, f64, 0, &sum, 0, Sum.value, Sum.add));
}

const Spin = struct {
    started: std.atomic.Value(usize) = .init(0),

    fn run(spin: *Spin, index: usize) void {
        _ = index;
        _ = spin.started.fetchAdd(1, .monotonic);
    }
};

test "an interrupt stops the workers and is reported" {
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    interrupt_requested.store(true, .monotonic);
    defer interrupt_requested.store(false, .monotonic);
    var spin = Spin{};
    const count = 1 << 40;
    try std.testing.expectError(es.Error.RZigError, parallel.parallelFor(&ctx, count, &spin, Spin.run));
    try std.testing.expect(es.takeInterrupt());
    try std.testing.expect(spin.started.load(.monotonic) < count);
}

test "random streams depend on the seed and the index only" {
    const streams = rng.Streams{ .seed = 42 };
    var first = streams.stream(7);
    var again = streams.stream(7);
    var other = streams.stream(8);
    const a = first.uniform();
    try std.testing.expectEqual(a, again.uniform());
    try std.testing.expect(a != other.uniform());
    try std.testing.expect(a > 0 and a < 1);
    _ = first.normal();
    _ = first.exponential();
}
