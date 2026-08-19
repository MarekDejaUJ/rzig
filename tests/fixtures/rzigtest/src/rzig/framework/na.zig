//! NA predicates. R's NA value is distinct from an ordinary NaN.
//!
//! R's NA_REAL is one specific NaN payload (a quiet NaN with low word 1954,
//! the year of R Ihaka's birth). A plain isNan check conflates NA with a
//! genuine NaN produced by 0/0, which silently changes statistical results.

const c = @import("c/abi.zig");

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
