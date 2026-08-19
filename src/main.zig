//! Minimal library entry point used by the R package fixture.
//!
//! The C stub in an R package calls this symbol from `R_init_<package>`.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("c/abi.zig");
const panic_handler = @import("panic.zig");

/// Route package panics through R while retaining Zig's test-runner behavior.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    panic_handler.Panic;

/// Hand control to the generated R routine registrar.
export fn rzig_init(dll: *c.DllInfo) void {
    if (builtin.is_test) return;
    _ = c.R_registerRoutines(dll, null, null, null, null);
    _ = c.R_useDynamicSymbols(dll, c.FALSE);
    _ = c.R_forceSymbols(dll, c.TRUE);
}

test {
    _ = @import("alloc.zig");
    _ = @import("boundary.zig");
    _ = @import("c/check.zig");
    _ = @import("error_state.zig");
    _ = @import("panic.zig");
    _ = @import("protect.zig");
    _ = @import("sexp.zig");
}
