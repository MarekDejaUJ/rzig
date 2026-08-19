//! NA predicates. R's NA value is distinct from an ordinary NaN.
//!
//! R's NA_REAL is one specific NaN payload (a quiet NaN with low word 1954,
//! the year of R Ihaka's birth). A plain isNan check conflates NA with a
//! genuine NaN produced by 0/0, which silently changes statistical results.

const std = @import("std");
const c = @import("c/abi.zig");

/// R exposes NA_REAL as a global; declare it rather than reconstructing the
/// bit pattern, so we track R's definition exactly.
pub extern var R_NaReal: f64;
pub extern var R_NaN: f64;
pub extern fn R_IsNA(x: f64) c_int;
pub extern fn R_IsNaN(x: f64) c_int;

pub inline fn isNaReal(x: f64) bool {
    return R_IsNA(x) != 0;
}

/// True for a genuine NaN that is not R's NA.
pub inline fn isNaNNotNa(x: f64) bool {
    return R_IsNaN(x) != 0;
}

pub inline fn isNaInt(x: c_int) bool {
    return x == c.NA_INTEGER;
}

pub inline fn isNaLogical(x: c_int) bool {
    return x == c.NA_LOGICAL;
}

// The NA_real_/NaN distinction requires R symbols at link time and is tested
// through the fixture package rather than `zig build test`.
