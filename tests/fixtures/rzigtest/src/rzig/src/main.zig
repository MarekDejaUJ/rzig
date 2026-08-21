const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

/// Route ReleaseSafe failures through R while retaining the Zig test runner.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

var unwind_cleanup_count_value: i32 = 0;

const UnwindProbe = struct {
    memory: []u8,
    cleaned: bool = false,
    jumped: bool = false,

    fn returnNil(state: *UnwindProbe) rzig.internal.c.SEXP {
        _ = state;
        return rzig.internal.c.R_NilValue;
    }

    fn stopInR(state: *UnwindProbe) rzig.internal.c.SEXP {
        _ = state;
        const c = rzig.internal.c;
        const stop_symbol = c.Rf_install("stop");
        var stack = rzig.internal.protect.Stack.init();
        const call = stack.push(c.Rf_lang1(stop_symbol));
        const result = c.Rf_eval(call, c.R_BaseEnv);
        stack.unwindAll();
        stack.deinit();
        return result;
    }

    fn cleanup(state: *UnwindProbe, jumped: bool) void {
        std.heap.c_allocator.free(state.memory);
        state.cleaned = true;
        state.jumped = jumped;
        unwind_cleanup_count_value +|= 1;
    }
};

fn newUnwindProbe() rzig.Error!UnwindProbe {
    const memory = std.heap.c_allocator.alloc(u8, 4096) catch
        return rzig.raise("unable to allocate unwind test resource", .{});
    return .{ .memory = memory };
}

/// Add one to every value in a numeric vector.
/// @export
pub fn add_one(ctx: *rzig.Ctx, values: []const f64) rzig.Error![]f64 {
    const result = try ctx.alloc(f64, values.len);
    for (values, result) |value, *slot| slot.* = value + 1.0;
    return result;
}

/// Return a scalar double unchanged.
/// @export
pub fn echo_f64(value: f64) f64 {
    return value;
}

/// Return a scalar integer unchanged.
/// @export
pub fn echo_i32(value: i32) i32 {
    return value;
}

/// Return a scalar logical unchanged.
/// @export
pub fn echo_bool(value: bool) bool {
    return value;
}

/// Convert a non-negative Zig-sized integer to an R integer.
/// @export
pub fn echo_usize(value: usize) i32 {
    return @intCast(value);
}

/// Return an optional scalar double unchanged.
/// @export
pub fn echo_optional(value: ?f64) ?f64 {
    return value;
}

/// Return a borrowed numeric vector for copying to R.
/// @export
pub fn echo_reals(values: []const f64) []const f64 {
    return values;
}

/// Return a borrowed integer vector for copying to R.
/// @export
pub fn echo_integers(values: []const i32) []const i32 {
    return values;
}

/// Return an arena-backed logical vector for copying to R.
/// @export
pub fn echo_logicals(values: []const bool) []const bool {
    return values;
}

/// Count values in an integer vector.
/// @export
pub fn integer_length(values: []const i32) rzig.Error!i32 {
    if (values.len > std.math.maxInt(i32)) {
        return rzig.raise("integer vector is too long", .{});
    }
    return @intCast(values.len);
}

/// Count true values in a logical vector.
/// @export
pub fn logical_count(values: []const bool) rzig.Error!i32 {
    var count: usize = 0;
    for (values) |value| count += @intFromBool(value);
    if (count > std.math.maxInt(i32)) return rzig.raise("logical vector is too long", .{});
    return @intCast(count);
}

/// Return one UTF-8 string unchanged.
/// @export
pub fn echo_string(value: []const u8) []const u8 {
    return value;
}

/// Return an arena-backed UTF-8 character vector for copying to R.
/// @export
pub fn echo_strings(values: []const []const u8) []const []const u8 {
    return values;
}

/// Count strings in a character vector.
/// @export
pub fn string_count(values: []const []const u8) rzig.Error!i32 {
    if (values.len > std.math.maxInt(i32)) return rzig.raise("string vector is too long", .{});
    return @intCast(values.len);
}

/// Return an arbitrary borrowed R value unchanged.
/// @export
pub fn identity_sexp(value: rzig.Sexp) rzig.Sexp {
    return value;
}

/// Add two numeric vectors elementwise.
/// @export
pub fn add_vectors(ctx: *rzig.Ctx, a: []const f64, b: []const f64) rzig.Error![]f64 {
    if (a.len != b.len) return rzig.raise("lengths differ: {d} vs {d}", .{ a.len, b.len });
    const result = try ctx.alloc(f64, a.len);
    for (a, b, result) |left, right, *slot| slot.* = left + right;
    return result;
}

/// Return a named list containing a vector and its length.
/// @export
pub fn named_summary(ctx: *rzig.Ctx, values: []const f64) rzig.Error!rzig.List {
    if (values.len > std.math.maxInt(i32)) return rzig.raise("numeric vector is too long", .{});
    var result = rzig.List.init(ctx);
    try result.put("values", values);
    try result.put("count", @as(i32, @intCast(values.len)));
    return result;
}

/// Return every supported vector kind inside a named R list.
/// @export
pub fn vector_summary(
    ctx: *rzig.Ctx,
    integers: []const i32,
    logicals: []const bool,
    strings: []const []const u8,
) rzig.Error!rzig.List {
    var result = rzig.List.init(ctx);
    try result.put("integers", integers);
    try result.put("logicals", logicals);
    try result.put("strings", strings);
    return result;
}

/// Attach matrix dimensions to a logical vector.
/// @export
pub fn reshape_logicals(
    ctx: *rzig.Ctx,
    values: []const bool,
    nrow: usize,
) rzig.Error!rzig.Attributed([]const bool) {
    const ncol = if (nrow == 0) blk: {
        if (values.len != 0) return rzig.raise("zero rows require an empty vector", .{});
        break :blk @as(usize, 0);
    } else blk: {
        if (values.len % nrow != 0) {
            return rzig.raise("length {d} is not divisible by {d} rows", .{ values.len, nrow });
        }
        break :blk values.len / nrow;
    };
    if (nrow > std.math.maxInt(i32) or ncol > std.math.maxInt(i32)) {
        return rzig.raise("matrix dimensions exceed R's integer limit", .{});
    }

    const dimensions = [_]i32{ @intCast(nrow), @intCast(ncol) };
    var result = rzig.Attributed([]const bool).init(ctx, values);
    try result.setDim(&dimensions);
    return result;
}

/// Scale a duplicated numeric vector without mutating the caller's input.
/// @export
pub fn scale_in_place(values: rzig.Mut([]f64), factor: f64) void {
    for (values.data) |*value| value.* *= factor;
}

/// Attach names and a class to a numeric vector.
/// @export
pub fn decorate_values(
    ctx: *rzig.Ctx,
    values: []const f64,
    labels: []const []const u8,
) rzig.Error!rzig.Attributed([]const f64) {
    var result = rzig.Attributed([]const f64).init(ctx, values);
    try result.setNames(labels);
    try result.setClass("rzig_values");
    return result;
}

/// Give a numeric vector two-dimensional matrix dimensions.
/// @export
pub fn reshape_values(
    ctx: *rzig.Ctx,
    values: []const f64,
    nrow: usize,
) rzig.Error!rzig.Attributed([]const f64) {
    const ncol = if (nrow == 0) blk: {
        if (values.len != 0) return rzig.raise("zero rows require an empty vector", .{});
        break :blk @as(usize, 0);
    } else blk: {
        if (values.len % nrow != 0) {
            return rzig.raise("length {d} is not divisible by {d} rows", .{ values.len, nrow });
        }
        break :blk values.len / nrow;
    };
    if (nrow > std.math.maxInt(i32) or ncol > std.math.maxInt(i32)) {
        return rzig.raise("matrix dimensions exceed R's integer limit", .{});
    }

    const dimensions = [_]i32{ @intCast(nrow), @intCast(ncol) };
    var result = rzig.Attributed([]const f64).init(ctx, values);
    try result.setDim(&dimensions);
    return result;
}

/// Sum the diagonal of a borrowed numeric matrix.
/// @export
pub fn matrix_trace(values: rzig.Matrix) rzig.Error!f64 {
    if (values.nrow != values.ncol) {
        return rzig.raise("matrix must be square; got {d} x {d}", .{ values.nrow, values.ncol });
    }
    var result: f64 = 0;
    for (0..values.nrow) |index| result += values.data[index + index * values.nrow];
    return result;
}

/// Draw uniforms from R's random-number stream.
/// @export
pub fn draw_uniforms(ctx: *rzig.Ctx, count: usize) rzig.Error![]f64 {
    const random = try ctx.rng();
    const result = try ctx.alloc(f64, count);
    for (result) |*value| value.* = random.uniform();
    return result;
}

/// Draw standard normals from R's random-number stream.
/// @export
pub fn draw_normals(ctx: *rzig.Ctx, count: usize) rzig.Error![]f64 {
    const random = try ctx.rng();
    const result = try ctx.alloc(f64, count);
    for (result) |*value| value.* = random.normal();
    return result;
}

/// Draw once, then fail so boundary cleanup must save the advanced RNG state.
/// @export
pub fn draw_then_error(ctx: *rzig.Ctx) rzig.Error!void {
    const random = try ctx.rng();
    _ = random.uniform();
    return rzig.raise("intentional error after an R RNG draw", .{});
}

/// Evaluate Rmath's normal cumulative distribution function.
/// @export
pub fn normal_cdf(value: f64) rzig.Error!f64 {
    return rzig.Rmath.normalCdf(value, 0.0, 1.0, true, false);
}

/// Evaluate Rmath's normal quantile function.
/// @export
pub fn normal_quantile(probability: f64) rzig.Error!f64 {
    return rzig.Rmath.normalQuantile(probability, 0.0, 1.0, true, false);
}

/// Count iterations while periodically checking for Ctrl-C.
/// @export
pub fn interruptible_count(iterations: usize) rzig.Error!i32 {
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        if (index % 100_000 == 0) try rzig.checkInterrupt();
    }
    return @intCast(index);
}

/// Square a numeric vector using only pure Zig worker threads.
/// @export
pub fn parallel_square(ctx: *rzig.Ctx, values: []const f64) rzig.Error![]f64 {
    const Work = struct {
        input: []const f64,
        output: []f64,

        fn run(work: *@This(), index: usize) void {
            work.output[index] = work.input[index] * work.input[index];
        }
    };

    const result = try ctx.alloc(f64, values.len);
    var work = Work{ .input = values, .output = result };
    try rzig.parallelFor(ctx, values.len, &work, Work.run);
    return result;
}

/// Return the number of resources released by unwind cleanup.
/// @export
pub fn unwind_cleanup_count() i32 {
    return unwind_cleanup_count_value;
}

/// Exercise unwind cleanup after an ordinary R callback return.
/// @export
pub fn unwind_cleanup_normal() rzig.Error!i32 {
    var state = try newUnwindProbe();
    _ = rzig.internal.unwind.protect(&state, UnwindProbe.returnNil, UnwindProbe.cleanup);
    if (!state.cleaned or state.jumped) {
        return rzig.raise("unwind cleanup did not report an ordinary return", .{});
    }
    return unwind_cleanup_count_value;
}

/// Exercise unwind cleanup when evaluation in R raises an error.
/// @export
pub fn unwind_cleanup_error() rzig.Error!void {
    var state = try newUnwindProbe();
    _ = rzig.internal.unwind.protect(&state, UnwindProbe.stopInR, UnwindProbe.cleanup);
    return rzig.raise("R evaluation unexpectedly returned", .{});
}

/// Trigger an intentional ReleaseSafe bounds failure.
/// @export
pub fn panic_bounds(values: []const f64) void {
    const one = [_]u8{0};
    if (one[values.len] == 0) return;
}

/// Allocate scratch memory and then return an intentional error.
/// @export
pub fn allocate_then_error(ctx: *rzig.Ctx) rzig.Error!void {
    const memory = try ctx.alloc(u8, 10 * 1024 * 1024);
    memory[0] = 1;
    memory[memory.len - 1] = 1;
    return rzig.raise("intentional error after allocating 10 MiB", .{});
}

/// Exercise a generated wrapper with no R-visible arguments.
/// @export
pub fn arity_zero() i32 {
    return 0;
}

/// Exercise a generated wrapper with three R-visible arguments.
/// @export
pub fn sum_three(a: f64, b: f64, c: f64) f64 {
    return a + b + c;
}

/// Exercise a generated wrapper with eight R-visible arguments.
/// @export
pub fn sum_eight(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64, g: f64, h: f64) f64 {
    return a + b + c + d + e + f + g + h;
}

/// Verify that Zig's C variadic ABI matches the R toolchain.
/// @export
pub fn ucrt_smoke(value: i32) i32 {
    rzig.internal.c.Rprintf("%s %d\n", "rzig-ucrt", @as(c_int, value));
    return value;
}

comptime {
    rzig.registerModule(@This());
}
