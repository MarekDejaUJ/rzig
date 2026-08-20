//! User interrupt handling. R_CheckUserInterrupt longjmps, so it is never
//! called without an R_ToplevelExec guard.

const c = @import("c/abi.zig");
const es = @import("error_state.zig");

fn probe(_: ?*anyopaque) callconv(.c) void {
    c.R_CheckUserInterrupt();
}

/// Returns an error if the user pressed Ctrl-C. R_ToplevelExec catches the
/// longjmp, so control returns here normally and the Zig stack unwinds through
/// ordinary error propagation.
///
/// Costs a few hundred nanoseconds. Call every ~1e5 iterations of a long loop,
/// not every iteration.
pub fn checkInterrupt() es.Error!void {
    if (c.R_ToplevelExec(probe, null) == c.FALSE) {
        return es.raise("interrupted by user", .{});
    }
}
