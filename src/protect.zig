//! Balanced protection stack. Prefer this over bare Rf_protect/Rf_unprotect.
//!
//! R restores R_PPStackTop when an error unwinds, so an imbalance at
//! error time is not a leak. We still assert balance in debug builds because an
//! imbalance is a symptom of confused ownership, and rchk will flag it.

const std = @import("std");
const c = @import("c/abi.zig");

pub const Stack = struct {
    n: c_int = 0,

    pub fn init() Stack {
        return .{};
    }

    /// Protect `s` and return it, so call sites read as
    ///   const v = stack.push(c.Rf_allocVector(c.REALSXP, n));
    /// which makes "allocate then immediately protect" the path of least effort.
    pub fn push(self: *Stack, s: c.SEXP) c.SEXP {
        const p = c.Rf_protect(s);
        self.n += 1;
        return p;
    }

    pub fn unwindAll(self: *Stack) void {
        if (self.n > 0) c.Rf_unprotect(self.n);
        self.n = 0;
    }

    /// Release the most recent `k` protections. Rarely needed; prefer unwindAll
    /// at the boundary.
    pub fn pop(self: *Stack, k: c_int) void {
        std.debug.assert(k <= self.n);
        c.Rf_unprotect(k);
        self.n -= k;
    }
};
