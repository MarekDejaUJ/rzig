//! RZig public API. Nothing but re-exports lives here.

const std = @import("std");

/// Per-call arena for Zig-owned scratch and result memory.
pub const Ctx = @import("alloc.zig").Ctx;
/// Numeric return wrapper with arena-backed names, dimensions, and classes.
pub const Attributed = @import("attributes.zig").Attributed;
/// Recoverable error set used by exported functions.
pub const Error = @import("error_state.zig").Error;
/// Record a recoverable R error without non-local control flow.
pub const raise = @import("error_state.zig").raise;
/// Queue a warning for safe delivery after Zig cleanup.
pub const warn = @import("error_state.zig").warn;
/// Check for Ctrl-C without allowing R's longjmp to cross Zig frames.
pub const checkInterrupt = @import("interrupt.zig").checkInterrupt;
/// Missing-value predicates for R scalar representations.
pub const NA = @import("na.zig");
/// Opaque borrowed R value escape hatch.
pub const Sexp = @import("sexp.zig").Sexp;
/// Arena-backed builder materialized as a named R list at the boundary.
pub const List = @import("list.zig").List;
/// Borrowed column-major view of an R numeric matrix.
pub const Matrix = @import("matrix.zig").Matrix;
/// Opt-in mutable input that duplicates an R vector before exposing writes.
pub const Mut = @import("convert.zig").Mut;
/// Generate native wrappers and register every manifest export.
pub const registerModule = @import("register.zig").registerModule;
/// Last-resort panic handler for a Zig-backed R shared library.
pub const Panic = @import("panic.zig").Panic;

/// Internal surface. Not covered by semver. Use at your own risk.
pub const internal = struct {
    pub const boundary = @import("boundary.zig");
    pub const convert = @import("convert.zig");
    pub const protect = @import("protect.zig");
    pub const c = @import("c/abi.zig");
};

test {
    std.testing.refAllDecls(@This());
}
