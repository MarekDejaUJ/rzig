//! Scalar-conversion tests with a minimal in-process stand-in for R.

const std = @import("std");
const c = @import("c/abi.zig");
const convert = @import("convert.zig");
const es = @import("error_state.zig");
const Ctx = @import("alloc.zig").Ctx;

const FakeSexp = extern struct {
    kind: c.SEXPTYPE,
    length: c.R_xlen_t,
    reals: [2]f64 = .{ 0, 0 },
    integers: [2]c_int = .{ 0, 0 },
};

const mock_na_real: f64 = @bitCast(@as(u64, 0x7ff8_0000_0000_07a2));

fn raw(value: *FakeSexp) c.SEXP {
    return @ptrCast(value);
}

export fn TYPEOF(value: c.SEXP) c_int {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return @intCast(fake.kind);
}

export fn Rf_xlength(value: c.SEXP) c.R_xlen_t {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return fake.length;
}

export fn Rf_isNull(value: c.SEXP) c.Rboolean {
    return if (TYPEOF(value) == c.NILSXP) c.TRUE else c.FALSE;
}

export fn REAL_ELT(value: c.SEXP, index: c.R_xlen_t) f64 {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return fake.reals[@intCast(index)];
}

export fn INTEGER_ELT(value: c.SEXP, index: c.R_xlen_t) c_int {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return fake.integers[@intCast(index)];
}

export fn LOGICAL_ELT(value: c.SEXP, index: c.R_xlen_t) c_int {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return fake.integers[@intCast(index)];
}

export fn R_IsNA(value: f64) c_int {
    return @intFromBool(@as(u64, @bitCast(value)) == @as(u64, @bitCast(mock_na_real)));
}

export fn Rf_type2char(kind: c.SEXPTYPE) [*:0]const u8 {
    return switch (kind) {
        c.NILSXP => "NULL",
        c.LGLSXP => "logical",
        c.INTSXP => "integer",
        c.REALSXP => "double",
        c.STRSXP => "character",
        else => "unknown",
    };
}

fn expectConversion(comptime T: type, value: *FakeSexp, expected: T) !void {
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    try std.testing.expectEqual(expected, try convert.fromSexp(T, &ctx, raw(value), "x"));
}

fn expectConversionError(comptime T: type, value: *FakeSexp, expected: []const u8) !void {
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(T, &ctx, raw(value), "x"));
    try std.testing.expectEqualStrings(expected, es.take());
}

test "f64 accepts scalar doubles, integers, and logicals" {
    var real = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 1.25, 0 } };
    var integer = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ -7, 0 } };
    var logical = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ c.TRUE, 0 } };
    try expectConversion(f64, &real, 1.25);
    try expectConversion(f64, &integer, -7.0);
    try expectConversion(f64, &logical, 1.0);
}

test "i32 accepts integral scalar values and rejects lossy conversion" {
    var integer = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ -7, 0 } };
    var logical = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ c.FALSE, 0 } };
    var real = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 42.0, 0 } };
    var fraction = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 1.5, 0 } };
    var too_large = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 2147483648.0, 0 } };
    try expectConversion(i32, &integer, -7);
    try expectConversion(i32, &logical, 0);
    try expectConversion(i32, &real, 42);
    try expectConversionError(i32, &fraction, "rzig: `x` must be a whole number representable as i32; got 1.5");
    try expectConversionError(i32, &too_large, "rzig: `x` must be a whole number representable as i32; got 2147483648");
}

test "bool accepts only a scalar logical" {
    var yes = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ c.TRUE, 0 } };
    var no = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ c.FALSE, 0 } };
    var integer = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ 1, 0 } };
    try expectConversion(bool, &yes, true);
    try expectConversion(bool, &no, false);
    try expectConversionError(bool, &integer, "rzig: `x` must be a logical vector of length 1; got integer");
}

test "usize rejects negative scalar values" {
    var positive = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 17.0, 0 } };
    var negative = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ -1, 0 } };
    var too_large = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 2147483648.0, 0 } };
    try expectConversion(usize, &positive, 17);
    try expectConversionError(usize, &negative, "rzig: `x` must be non-negative; got -1");
    try expectConversionError(usize, &too_large, "rzig: `x` must be a whole number from 0 to 2147483647; got 2147483648");
}

test "required scalars reject NA while optionals map NULL and NA to null" {
    var nil = FakeSexp{ .kind = c.NILSXP, .length = 0 };
    var na_real = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ mock_na_real, 0 } };
    var na_integer = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ c.NA_INTEGER, 0 } };
    var na_logical = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ c.NA_LOGICAL, 0 } };
    try expectConversionError(f64, &na_real, "rzig: `x` cannot be NA; use ?f64 to accept missing values");
    try expectConversionError(i32, &na_integer, "rzig: `x` cannot be NA; use ?i32 to accept missing values");
    try expectConversionError(bool, &na_logical, "rzig: `x` cannot be NA; use ?bool to accept missing values");
    try expectConversionError(usize, &na_integer, "rzig: `x` cannot be NA; use ?usize to accept missing values");
    try expectConversion(?f64, &nil, null);
    try expectConversion(?f64, &na_real, null);
    try expectConversion(?i32, &na_integer, null);
    try expectConversion(?bool, &na_logical, null);
    try expectConversion(?usize, &na_integer, null);
}

test "ordinary NaN remains a valid f64" {
    var value = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ std.math.nan(f64), 0 } };
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    const converted = try convert.fromSexp(f64, &ctx, raw(&value), "x");
    try std.testing.expect(std.math.isNan(converted));
}

test "length errors name the parameter and actual length" {
    var empty = FakeSexp{ .kind = c.REALSXP, .length = 0 };
    var pair = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 1, 2 } };
    try expectConversionError(f64, &empty, "rzig: `x` must have length 1; got length 0");
    try expectConversionError(i32, &pair, "rzig: `x` must have length 1; got length 2");
}
