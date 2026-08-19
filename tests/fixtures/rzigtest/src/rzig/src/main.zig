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

comptime {
    rzig.registerModule(@This());
}
