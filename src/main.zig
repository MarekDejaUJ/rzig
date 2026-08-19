//! Minimal library entry point used by the R package fixture.
//!
//! The C stub in an R package calls this symbol from `R_init_<package>`.

const std = @import("std");
const builtin = @import("builtin");
const panic_handler = @import("panic.zig");
const register = @import("register.zig");

/// Route package panics through R while retaining Zig's test-runner behavior.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    panic_handler.Panic;

comptime {
    register.registerModule(@This());
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
