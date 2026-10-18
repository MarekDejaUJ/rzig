//! Parallel worker tests using only plain Zig state.

const std = @import("std");
const Ctx = @import("alloc.zig").Ctx;
const parallel = @import("parallel.zig");

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
