const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

/// Route ReleaseSafe failures through R while retaining the Zig test runner.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

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
