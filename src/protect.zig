//! Balanced protection stack. Prefer this over bare Rf_protect/Rf_unprotect.
//!
//! R restores `R_PPStackTop` when an error longjmps, so skipped `unwindAll`
//! calls do not leak R objects. That does not rescue Zig-owned resources, and a
//! normally returning scope must still be balanced. The counter and assertions
//! below make that ownership visible in safety-enabled builds.

const std = @import("std");
const c = @import("c/abi.zig");

/// Counts R objects protected by the current wrapper frame.
pub const Stack = struct {
    count: usize = 0,

    /// Create an empty protection stack.
    pub fn init() Stack {
        return .{};
    }

    /// Protect `s` and return it, so call sites read as
    ///   const v = stack.push(c.Rf_allocVector(c.REALSXP, n));
    /// which makes "allocate then immediately protect" the path of least effort.
    pub fn push(self: *Stack, s: c.SEXP) c.SEXP {
        std.debug.assert(self.count < std.math.maxInt(c_int));
        const p = c.Rf_protect(s);
        self.notePush();
        return p;
    }

    /// Release every protection owned by this stack.
    pub fn unwindAll(self: *Stack) void {
        if (self.count == 0) return;
        const count: c_int = @intCast(self.count);
        c.Rf_unprotect(count);
        self.notePop(self.count);
        std.debug.assert(self.count == 0);
    }

    /// Release the most recent `k` protections. Rarely needed; prefer unwindAll
    /// at the boundary.
    pub fn pop(self: *Stack, k: usize) void {
        std.debug.assert(k <= self.count);
        std.debug.assert(k <= std.math.maxInt(c_int));
        if (k == 0) return;
        c.Rf_unprotect(@intCast(k));
        self.notePop(k);
    }

    /// Assert that normal control flow released every owned protection.
    pub fn deinit(self: *const Stack) void {
        std.debug.assert(self.count == 0);
    }

    fn notePush(self: *Stack) void {
        self.count += 1;
    }

    fn notePop(self: *Stack, k: usize) void {
        std.debug.assert(k <= self.count);
        self.count -= k;
    }
};

test "counter bookkeeping returns to balance" {
    var stack = Stack.init();
    stack.notePush();
    stack.notePush();
    stack.notePop(1);
    try std.testing.expectEqual(@as(usize, 1), stack.count);
    stack.notePop(1);
    stack.deinit();
}
