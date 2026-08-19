//! Minimal library entry point used by the R package fixture.
//!
//! The C stub in an R package calls this symbol from `R_init_<package>`.

const builtin = @import("builtin");
const c = @import("c/abi.zig");

/// Hand control to the generated R routine registrar.
export fn rzig_init(dll: *c.DllInfo) void {
    if (builtin.is_test) return;
    _ = c.R_registerRoutines(dll, null, null, null, null);
    _ = c.R_useDynamicSymbols(dll, c.FALSE);
    _ = c.R_forceSymbols(dll, c.TRUE);
}
