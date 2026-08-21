//! User interrupt handling. R_CheckUserInterrupt longjmps, so it is never
//! called without an R_ToplevelExec guard.

const c = @import("c/abi.zig");
const es = @import("error_state.zig");

fn probe(_: ?*anyopaque) callconv(.c) void {
    c.R_CheckUserInterrupt();
}

/// Returns an error if the user pressed Ctrl-C. R_ToplevelExec catches the
/// longjmp, so control returns here normally and the Zig stack unwinds through
/// ordinary error propagation. The outer boundary later re-signals a genuine
/// R interrupt condition after all Zig-owned resources have been released.
///
/// Costs a few hundred nanoseconds. Call every ~1e5 iterations of a long loop,
/// not every iteration.
pub fn checkInterrupt() es.Error!void {
    if (c.R_ToplevelExec(probe, null) == c.FALSE) {
        return request();
    }
}

/// Mark an interrupt for delivery by the outer boundary.
///
/// This is exposed only through `rzig.internal` so integration tests can
/// exercise delivery without sending an operating-system signal.
pub fn request() es.Error {
    return es.interrupt();
}
