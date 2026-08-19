//! Conversion between borrowed R values and Zig values.
//!
//! Everything here can allocate on the R side, so everything here can trigger
//! GC. Protect immediately after every allocation.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const na = @import("na.zig");
const protect = @import("protect.zig");
const Ctx = @import("alloc.zig").Ctx;

/// Opt-in mutable input. The wrapper duplicates the incoming SEXP first,
/// because R vectors are copy-on-modify and may be shared.
pub fn Mut(comptime T: type) type {
    return struct {
        pub const rzig_mut_inner = T;
        data: T,
    };
}

/// SEXP -> Zig. `pos` is the zero-based parameter index and `name` its
/// identifier, both used only to build a good error message.
pub fn fromSexp(
    comptime T: type,
    ctx: *Ctx,
    x: c.SEXP,
    comptime name: []const u8,
) es.Error!T {
    if (comptime T == f64) return scalarF64(x, name);
    if (comptime T == i32) return scalarI32(x, name, "i32");
    if (comptime T == bool) return scalarBool(x, name);
    if (comptime T == usize) return scalarUsize(x, name);
    if (comptime T == []const f64) return realSlice(x, name);
    if (comptime T == []const i32) return integerSlice(x, name);
    if (comptime T == []const bool) return logicalSlice(ctx, x, name);

    return switch (@typeInfo(T)) {
        .optional => |info| optionalScalar(info.child, ctx, x, name),
        // TODO: slices and strings.
        else => @compileError(unsupportedMessage(T, name)),
    };
}

fn realSlice(x: c.SEXP, comptime name: []const u8) es.Error![]const f64 {
    if (c.TYPEOF(x) != c.REALSXP) {
        return es.raise(
            "rzig: `{s}` must be a numeric vector; got {s}; use as.numeric() in R",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    return c.REAL_RO(x)[0..length];
}

fn integerSlice(x: c.SEXP, comptime name: []const u8) es.Error![]const i32 {
    if (c.TYPEOF(x) != c.INTSXP) {
        return es.raise(
            "rzig: `{s}` must be an integer vector; got {s}; use as.integer() in R",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    return c.INTEGER_RO(x)[0..length];
}

fn logicalSlice(ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error![]const bool {
    if (c.TYPEOF(x) != c.LGLSXP) {
        return es.raise(
            "rzig: `{s}` must be a logical vector; got {s}",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    const source = c.LOGICAL_RO(x)[0..length];
    for (source, 0..) |value, index| {
        if (na.isNaLogical(value)) {
            return es.raise(
                "rzig: `{s}` cannot contain NA; found NA at position {d}",
                .{ name, index + 1 },
            );
        }
    }

    const result = try ctx.alloc(bool, length);
    for (source, result) |value, *slot| slot.* = value != c.FALSE;
    return result;
}

fn vectorLength(x: c.SEXP, comptime name: []const u8) es.Error!usize {
    const length = c.Rf_xlength(x);
    if (length < 0) {
        return es.raise("rzig: `{s}` has an invalid negative length", .{name});
    }
    return @intCast(length);
}

fn optionalScalar(
    comptime T: type,
    ctx: *Ctx,
    x: c.SEXP,
    comptime name: []const u8,
) es.Error!?T {
    if (comptime !isScalar(T)) @compileError(unsupportedMessage(?T, name));
    if (c.Rf_isNull(x) != c.FALSE) return null;

    try validateScalar(T, x, name);
    if (scalarIsNa(x)) return null;
    return try fromSexp(T, ctx, x, name);
}

fn scalarF64(x: c.SEXP, comptime name: []const u8) es.Error!f64 {
    try validateScalar(f64, x, name);
    const value = switch (@as(c.SEXPTYPE, @intCast(c.TYPEOF(x)))) {
        c.REALSXP => c.REAL_ELT(x, 0),
        c.INTSXP => @as(f64, @floatFromInt(c.INTEGER_ELT(x, 0))),
        c.LGLSXP => @as(f64, @floatFromInt(c.LOGICAL_ELT(x, 0))),
        else => return es.raise("rzig: internal scalar conversion error for `{s}`", .{name}),
    };
    if (scalarIsNa(x)) {
        return es.raise("rzig: `{s}` cannot be NA; use ?f64 to accept missing values", .{name});
    }
    return value;
}

fn scalarI32(
    x: c.SEXP,
    comptime name: []const u8,
    comptime target_name: []const u8,
) es.Error!i32 {
    try validateScalar(i32, x, name);
    if (scalarIsNa(x)) {
        return es.raise(
            "rzig: `{s}` cannot be NA; use ?{s} to accept missing values",
            .{ name, target_name },
        );
    }

    return switch (@as(c.SEXPTYPE, @intCast(c.TYPEOF(x)))) {
        c.INTSXP => @intCast(c.INTEGER_ELT(x, 0)),
        c.LGLSXP => @intCast(c.LOGICAL_ELT(x, 0)),
        c.REALSXP => realToI32(c.REAL_ELT(x, 0), name),
        else => es.raise("rzig: internal scalar conversion error for `{s}`", .{name}),
    };
}

fn realToI32(value: f64, comptime name: []const u8) es.Error!i32 {
    const min: f64 = @floatFromInt(std.math.minInt(i32));
    const max: f64 = @floatFromInt(std.math.maxInt(i32));
    if (!std.math.isFinite(value) or @trunc(value) != value or value < min or value > max) {
        return es.raise(
            "rzig: `{s}` must be a whole number representable as i32; got {d}",
            .{ name, value },
        );
    }
    return @intFromFloat(value);
}

fn scalarBool(x: c.SEXP, comptime name: []const u8) es.Error!bool {
    try validateScalar(bool, x, name);
    const value = c.LOGICAL_ELT(x, 0);
    if (na.isNaLogical(value)) {
        return es.raise("rzig: `{s}` cannot be NA; use ?bool to accept missing values", .{name});
    }
    return value != c.FALSE;
}

fn scalarUsize(x: c.SEXP, comptime name: []const u8) es.Error!usize {
    try validateScalar(usize, x, name);
    if (scalarIsNa(x)) {
        return es.raise("rzig: `{s}` cannot be NA; use ?usize to accept missing values", .{name});
    }

    const kind: c.SEXPTYPE = @intCast(c.TYPEOF(x));
    const value: f64 = switch (kind) {
        c.INTSXP => @floatFromInt(c.INTEGER_ELT(x, 0)),
        c.LGLSXP => @floatFromInt(c.LOGICAL_ELT(x, 0)),
        c.REALSXP => c.REAL_ELT(x, 0),
        else => return es.raise("rzig: internal scalar conversion error for `{s}`", .{name}),
    };
    if (std.math.isFinite(value) and value < 0) {
        return es.raise("rzig: `{s}` must be non-negative; got {d}", .{ name, value });
    }
    const max: f64 = @floatFromInt(std.math.maxInt(i32));
    if (!std.math.isFinite(value) or @trunc(value) != value or value > max) {
        return es.raise(
            "rzig: `{s}` must be a whole number from 0 to 2147483647; got {d}",
            .{ name, value },
        );
    }
    return @intFromFloat(value);
}

fn validateScalar(comptime T: type, x: c.SEXP, comptime name: []const u8) es.Error!void {
    const kind: c.SEXPTYPE = @intCast(c.TYPEOF(x));
    const valid_type = if (comptime T == bool)
        kind == c.LGLSXP
    else
        kind == c.REALSXP or kind == c.INTSXP or kind == c.LGLSXP;

    if (!valid_type) {
        if (comptime T == bool) {
            return es.raise(
                "rzig: `{s}` must be a logical vector of length 1; got {s}",
                .{ name, typeName(x) },
            );
        }
        return es.raise(
            "rzig: `{s}` must be a double, integer, or logical vector of length 1; got {s}",
            .{ name, typeName(x) },
        );
    }

    const length = c.Rf_xlength(x);
    if (length != 1) {
        return es.raise("rzig: `{s}` must have length 1; got length {d}", .{ name, length });
    }
}

fn scalarIsNa(x: c.SEXP) bool {
    const kind: c.SEXPTYPE = @intCast(c.TYPEOF(x));
    return switch (kind) {
        c.REALSXP => na.isNaReal(c.REAL_ELT(x, 0)),
        c.INTSXP => na.isNaInt(c.INTEGER_ELT(x, 0)),
        c.LGLSXP => na.isNaLogical(c.LOGICAL_ELT(x, 0)),
        else => false,
    };
}

fn isScalar(comptime T: type) bool {
    return T == f64 or T == i32 or T == bool or T == usize;
}

/// Zig -> SEXP. Pushes onto `stack` immediately after allocating.
pub fn toSexp(
    stack: *protect.Stack,
    ctx: *Ctx,
    value: anytype,
) es.Error!c.SEXP {
    _ = stack;
    _ = ctx;
    _ = value;
    // TODO: marshal supported Zig return types.
    return c.R_NilValue;
}

/// Compile-error text. Message quality is a first-class feature here - it is
/// most of what RZig offers over hand-written glue. Always name the parameter,
/// the type, the supported set, and the likely intended alternative.
fn unsupportedMessage(comptime T: type, comptime name: []const u8) []const u8 {
    return "rzig: parameter `" ++ name ++ "` has unsupported type '" ++ @typeName(T) ++ "'.\n" ++
        "  supported: f64, i32, bool, usize, ?T,\n" ++
        "             []const f64, []const i32, []const bool, []const u8, []const []const u8,\n" ++
        "             rzig.Sexp (escape hatch)\n" ++
        "  for a mutable vector use rzig.Mut([]f64)\n" ++
        "  note []f64 is NOT accepted as an input: R inputs are borrowed and read-only";
}

/// Human-readable R type name, for runtime error messages. Never say "SEXP" or
/// "REALSXP" to an R user.
pub fn typeName(x: c.SEXP) []const u8 {
    return std.mem.span(c.Rf_type2char(@intCast(c.TYPEOF(x))));
}
