//! Bookkeeping of stopped R jumps, with an in-process stand-in for R.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const Ctx = @import("alloc.zig").Ctx;
const rcall = @import("rcall.zig");

var mock_nil: u8 = 0;
var mock_tokens: [4]u8 = @splat(0);
var tokens_made: usize = 0;
var preserved: isize = 0;
var simulate_jump = false;

export var R_NilValue: c.SEXP = @ptrCast(&mock_nil);

export fn R_MakeUnwindCont() c.SEXP {
    const token: c.SEXP = @ptrCast(&mock_tokens[tokens_made]);
    tokens_made += 1;
    return token;
}

export fn R_PreserveObject(object: c.SEXP) void {
    _ = object;
    preserved += 1;
}

export fn R_ReleaseObject(object: c.SEXP) void {
    _ = object;
    preserved -= 1;
}

export fn SETCAR(cell: c.SEXP, value: c.SEXP) c.SEXP {
    _ = cell;
    return value;
}

export fn R_ToplevelExec(
    callback: *const fn (?*anyopaque) callconv(.c) void,
    data: ?*anyopaque,
) c.Rboolean {
    callback(data);
    return c.TRUE;
}

// rzig_unwind_run() of src/entry.c: run the body, or report a jump of R
// without running it.
export fn rzig_unwind_run(
    body: *const fn (?*anyopaque) callconv(.c) c.SEXP,
    data: ?*anyopaque,
    token: c.SEXP,
    result: *c.SEXP,
) c_int {
    _ = token;
    if (simulate_jump) return 1;
    result.* = body(data);
    return 0;
}

const Counter = struct {
    runs: usize = 0,

    fn run(self: *Counter) void {
        self.runs += 1;
    }
};

fn reset() void {
    es.reset();
    tokens_made = 0;
    preserved = 0;
    simulate_jump = false;
}

test "an intercepted body reuses one spare token" {
    reset();
    var ctx = Ctx.init();
    var counter = Counter{};
    try rcall.intercept(&ctx, &counter, Counter.run);
    try rcall.intercept(&ctx, &counter, Counter.run);
    try std.testing.expectEqual(@as(usize, 2), counter.runs);
    try std.testing.expectEqual(@as(usize, 1), tokens_made);
    try std.testing.expectEqual(@as(isize, 1), preserved);
    ctx.deinit();
    try std.testing.expectEqual(@as(isize, 0), preserved);
}

test "a jump is kept for the boundary and its token leaves the context" {
    reset();
    var ctx = Ctx.init();
    var counter = Counter{};
    simulate_jump = true;
    try std.testing.expectError(es.Error.RZigError, rcall.intercept(&ctx, &counter, Counter.run));
    try std.testing.expect(es.jumpPending());
    simulate_jump = false;
    try rcall.intercept(&ctx, &counter, Counter.run);
    try std.testing.expectEqual(@as(usize, 2), tokens_made);
    ctx.deinit();
    try std.testing.expectEqual(@as(isize, 1), preserved);
    const jump = es.takeJump().?;
    try std.testing.expect(!jump.superseded);
    try std.testing.expect(!es.jumpPending());
}

test "a later error supersedes a kept jump" {
    reset();
    var token: u8 = 0;
    es.noteJump(@ptrCast(&token));
    es.record("replaced", .{});
    const jump = es.takeJump().?;
    try std.testing.expect(jump.superseded);
    es.noteJump(@ptrCast(&token));
    try std.testing.expectEqual(es.Error.RZigError, es.interrupt());
    try std.testing.expect(es.takeJump().?.superseded);
}

test "the error state waits while R code runs and comes back" {
    reset();
    var token: u8 = 0;
    es.record("outer message", .{});
    es.noteJump(@ptrCast(&token));
    var saved: es.Saved = .{};
    es.save(&saved);
    try std.testing.expectEqualStrings("", es.take());
    try std.testing.expect(!es.jumpPending());
    es.record("inner message", .{});
    _ = es.take();
    es.restore(&saved);
    try std.testing.expect(es.jumpPending());
    try std.testing.expectEqualStrings("outer message", es.take());
    _ = es.takeJump();
}
