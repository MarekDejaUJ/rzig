//! Non-allocating, read-only access to borrowed R objects.
//!
//! These helpers validate types and bounds before calling R's accessors. A
//! mismatch is returned as `null`; conversion code turns it into a user-facing
//! error without allowing R to longjmp through a Zig frame.

const std = @import("std");
const c = @import("c/abi.zig");

const OpaqueSexp = opaque {};

/// Opaque borrowed R value. It is valid only for the duration of its `.Call`.
pub const Sexp = *OpaqueSexp;

/// Wrap an internal C SEXP without changing ownership or protection.
pub fn fromRaw(value: c.SEXP) Sexp {
    return @ptrCast(value);
}

/// Recover the internal C SEXP without changing ownership or protection.
pub fn toRaw(value: Sexp) c.SEXP {
    return @ptrCast(value);
}

/// Return the R storage type of a borrowed value.
pub fn typeOf(value: Sexp) c.SEXPTYPE {
    return @intCast(c.TYPEOF(toRaw(value)));
}

/// Return a long-vector-safe length, or `null` if R reports an invalid value.
pub fn xlength(value: Sexp) ?usize {
    return checkedLength(c.Rf_xlength(toRaw(value)));
}

/// Borrow a read-only double slice, or `null` when `value` is not a REALSXP.
pub fn realRo(value: Sexp) ?[]const f64 {
    if (typeOf(value) != c.REALSXP) return null;
    const len = xlength(value) orelse return null;
    return c.REAL_RO(toRaw(value))[0..len];
}

/// Borrow a read-only integer slice, or `null` when `value` is not an INTSXP.
pub fn intRo(value: Sexp) ?[]const c_int {
    if (typeOf(value) != c.INTSXP) return null;
    const len = xlength(value) orelse return null;
    return c.INTEGER_RO(toRaw(value))[0..len];
}

/// Read a CHARSXP, returning `null` for a wrong type or out-of-bounds index.
pub fn stringElt(value: Sexp, index: usize) ?Sexp {
    if (typeOf(value) != c.STRSXP) return null;
    const len = xlength(value) orelse return null;
    if (index >= len) return null;
    return fromRaw(c.STRING_ELT(toRaw(value), @intCast(index)));
}

/// Test whether a borrowed value is R's null singleton.
pub fn isNull(value: Sexp) bool {
    return c.Rf_isNull(toRaw(value)) != c.FALSE;
}

fn checkedLength(value: c.R_xlen_t) ?usize {
    if (value < 0) return null;
    return @intCast(value);
}

test "length conversion rejects negative values" {
    try std.testing.expectEqual(@as(?usize, null), checkedLength(-1));
    try std.testing.expectEqual(@as(?usize, 0), checkedLength(0));
    try std.testing.expectEqual(@as(?usize, 42), checkedLength(42));
}

test "read accessors preserve const borrows" {
    try std.testing.expect(@TypeOf(realRo) == fn (Sexp) ?[]const f64);
    try std.testing.expect(@TypeOf(intRo) == fn (Sexp) ?[]const c_int);
    try std.testing.expect(@TypeOf(stringElt) == fn (Sexp, usize) ?Sexp);
}
