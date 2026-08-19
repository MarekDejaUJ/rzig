const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");
const c = rzig.internal.c;
const boundary = rzig.internal.boundary;

/// Route ReleaseSafe failures through R while retaining the Zig test runner.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

fn addOne(ctx: *rzig.Ctx, values: []const f64) rzig.Error![]f64 {
    const result = try ctx.alloc(f64, values.len);
    for (values, result) |value, *slot| slot.* = value + 1.0;
    return result;
}

fn echoF64(value: f64) f64 {
    return value;
}

fn echoI32(value: i32) i32 {
    return value;
}

fn echoBool(value: bool) bool {
    return value;
}

fn echoUsize(value: usize) i32 {
    return @intCast(value);
}

fn echoOptional(value: ?f64) ?f64 {
    return value;
}

fn echoReals(values: []const f64) []const f64 {
    return values;
}

fn integerLength(values: []const i32) rzig.Error!i32 {
    if (values.len > std.math.maxInt(i32)) {
        return rzig.raise("integer vector is too long", .{});
    }
    return @intCast(values.len);
}

fn logicalCount(values: []const bool) rzig.Error!i32 {
    var count: usize = 0;
    for (values) |value| count += @intFromBool(value);
    if (count > std.math.maxInt(i32)) return rzig.raise("logical vector is too long", .{});
    return @intCast(count);
}

fn echoString(value: []const u8) []const u8 {
    return value;
}

fn stringCount(values: []const []const u8) rzig.Error!i32 {
    if (values.len > std.math.maxInt(i32)) return rzig.raise("string vector is too long", .{});
    return @intCast(values.len);
}

fn identitySexp(value: rzig.Sexp) rzig.Sexp {
    return value;
}

fn addVectors(ctx: *rzig.Ctx, a: []const f64, b: []const f64) rzig.Error![]f64 {
    if (a.len != b.len) return rzig.raise("lengths differ: {d} vs {d}", .{ a.len, b.len });
    const result = try ctx.alloc(f64, a.len);
    for (a, b, result) |left, right, *slot| slot.* = left + right;
    return result;
}

fn panicBounds(values: []const f64) void {
    const one = [_]u8{0};
    if (one[values.len] == 0) return;
}

fn allocateThenError(ctx: *rzig.Ctx) rzig.Error!void {
    const memory = try ctx.alloc(u8, 10 * 1024 * 1024);
    memory[0] = 1;
    memory[memory.len - 1] = 1;
    return rzig.raise("intentional error after allocating 10 MiB", .{});
}

export fn add_one(value: c.SEXP) c.SEXP {
    return boundary.invoke(addOne, "add_one", .{value});
}

export fn echo_f64(value: c.SEXP) c.SEXP {
    return boundary.invoke(echoF64, "echo_f64", .{value});
}

export fn echo_i32(value: c.SEXP) c.SEXP {
    return boundary.invoke(echoI32, "echo_i32", .{value});
}

export fn echo_bool(value: c.SEXP) c.SEXP {
    return boundary.invoke(echoBool, "echo_bool", .{value});
}

export fn echo_usize(value: c.SEXP) c.SEXP {
    return boundary.invoke(echoUsize, "echo_usize", .{value});
}

export fn echo_optional(value: c.SEXP) c.SEXP {
    return boundary.invoke(echoOptional, "echo_optional", .{value});
}

export fn echo_reals(value: c.SEXP) c.SEXP {
    return boundary.invoke(echoReals, "echo_reals", .{value});
}

export fn integer_length(value: c.SEXP) c.SEXP {
    return boundary.invoke(integerLength, "integer_length", .{value});
}

export fn logical_count(value: c.SEXP) c.SEXP {
    return boundary.invoke(logicalCount, "logical_count", .{value});
}

export fn echo_string(value: c.SEXP) c.SEXP {
    return boundary.invoke(echoString, "echo_string", .{value});
}

export fn string_count(value: c.SEXP) c.SEXP {
    return boundary.invoke(stringCount, "string_count", .{value});
}

export fn identity_sexp(value: c.SEXP) c.SEXP {
    return boundary.invoke(identitySexp, "identity_sexp", .{value});
}

export fn add_vectors(a: c.SEXP, b: c.SEXP) c.SEXP {
    return boundary.invoke(addVectors, "add_vectors", .{ a, b });
}

export fn panic_bounds(value: c.SEXP) c.SEXP {
    return boundary.invoke(panicBounds, "panic_bounds", .{value});
}

export fn allocate_then_error() c.SEXP {
    return boundary.invoke(allocateThenError, "allocate_then_error", .{});
}

const call_methods = [_]c.R_CallMethodDef{
    .{ .name = "add_one", .fun = @ptrCast(&add_one), .numArgs = 1 },
    .{ .name = "echo_f64", .fun = @ptrCast(&echo_f64), .numArgs = 1 },
    .{ .name = "echo_i32", .fun = @ptrCast(&echo_i32), .numArgs = 1 },
    .{ .name = "echo_bool", .fun = @ptrCast(&echo_bool), .numArgs = 1 },
    .{ .name = "echo_usize", .fun = @ptrCast(&echo_usize), .numArgs = 1 },
    .{ .name = "echo_optional", .fun = @ptrCast(&echo_optional), .numArgs = 1 },
    .{ .name = "echo_reals", .fun = @ptrCast(&echo_reals), .numArgs = 1 },
    .{ .name = "integer_length", .fun = @ptrCast(&integer_length), .numArgs = 1 },
    .{ .name = "logical_count", .fun = @ptrCast(&logical_count), .numArgs = 1 },
    .{ .name = "echo_string", .fun = @ptrCast(&echo_string), .numArgs = 1 },
    .{ .name = "string_count", .fun = @ptrCast(&string_count), .numArgs = 1 },
    .{ .name = "identity_sexp", .fun = @ptrCast(&identity_sexp), .numArgs = 1 },
    .{ .name = "add_vectors", .fun = @ptrCast(&add_vectors), .numArgs = 2 },
    .{ .name = "panic_bounds", .fun = @ptrCast(&panic_bounds), .numArgs = 1 },
    .{ .name = "allocate_then_error", .fun = @ptrCast(&allocate_then_error), .numArgs = 0 },
    .{ .name = null, .fun = null, .numArgs = 0 },
};

/// Register every integration routine and require symbol-based lookup.
export fn rzig_init(dll: *c.DllInfo) void {
    _ = c.R_registerRoutines(dll, null, &call_methods, null, null);
    _ = c.R_useDynamicSymbols(dll, c.FALSE);
    _ = c.R_forceSymbols(dll, c.TRUE);
}
