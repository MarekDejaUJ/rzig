//! NA values and predicates. R's NA value is distinct from an ordinary NaN.
//!
//! R's NA_REAL is one specific NaN payload (a NaN with low word 1954, the
//! year of R Ihaka's birth). A plain isNan check conflates NA with a genuine
//! NaN produced by 0/0, which silently changes statistical results.

const std = @import("std");
const c = @import("c/abi.zig");

/// One element of an R logical vector in R's representation: an `int`
/// holding 1 (`TRUE`), 0 (`FALSE`) or `NA_LOGICAL`. Slices of it borrow R
/// logical vectors without a copy. R treats any other nonzero value as
/// `TRUE`, and so does `isTrue`.
pub const Logical = enum(i32) {
    FALSE = 0,
    TRUE = 1,
    NA = std.math.minInt(i32),
    _,

    /// `TRUE` or `FALSE`.
    pub fn fromBool(value: bool) Logical {
        return if (value) .TRUE else .FALSE;
    }

    /// Whether the value is `NA`.
    pub fn isNa(self: Logical) bool {
        return self == .NA;
    }

    /// Whether the value is `TRUE` (any value other than `FALSE` and `NA`).
    pub fn isTrue(self: Logical) bool {
        return self != .FALSE and self != .NA;
    }

    /// Whether the value is `FALSE`.
    pub fn isFalse(self: Logical) bool {
        return self == .FALSE;
    }
};

/// R's missing double (`NA_real_`): the NaN whose low word is 1954.
pub const real: f64 = @bitCast(@as(u64, 0x7FF0_0000_0000_07A2));
/// R's missing integer (`NA_integer_`), `std.math.minInt(i32)`.
pub const integer: i32 = std.math.minInt(i32);
/// The missing value of bit64::integer64 vectors, `std.math.minInt(i64)`.
pub const integer64: i64 = std.math.minInt(i64);
/// R's missing logical (`NA`).
pub const logical: Logical = .NA;

/// True only for R's distinguished missing-real NaN payload.
pub inline fn isNaReal(x: f64) bool {
    return c.R_IsNA(x) != 0;
}

/// True for a genuine NaN that is not R's NA.
pub inline fn isNaNNotNa(x: f64) bool {
    return c.R_IsNaN(x) != 0;
}

/// True for R's missing-integer sentinel.
pub inline fn isNaInt(x: c_int) bool {
    return x == c.NA_INTEGER;
}

/// True for R's missing-logical sentinel.
pub inline fn isNaLogical(x: c_int) bool {
    return x == c.NA_LOGICAL;
}

test "NA constants have R's representations" {
    const bits: u64 = @bitCast(real);
    try std.testing.expect(std.math.isNan(real));
    try std.testing.expectEqual(@as(u64, 1954), bits & 0xFFFF_FFFF);
    try std.testing.expectEqual(@as(i32, c.NA_INTEGER), integer);
    try std.testing.expectEqual(@as(i32, c.NA_LOGICAL), @intFromEnum(logical));
    try std.testing.expect(Logical.fromBool(true).isTrue());
    try std.testing.expect(Logical.fromBool(false).isFalse());
    try std.testing.expect(logical.isNa() and !logical.isTrue() and !logical.isFalse());
    const other: Logical = @enumFromInt(7);
    try std.testing.expect(other.isTrue());
}
