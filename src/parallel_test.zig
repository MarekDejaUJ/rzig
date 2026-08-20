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
    var output = [_]f64{0} ** input.len;
    var thread_ids = [_]std.Thread.Id{0} ** input.len;
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
