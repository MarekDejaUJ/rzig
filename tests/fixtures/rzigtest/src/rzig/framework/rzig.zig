//! Fixture-facing view of the production RZig modules.

/// Per-call arena context.
pub const Ctx = @import("alloc.zig").Ctx;
/// Recoverable error set used at the R boundary.
pub const Error = @import("error_state.zig").Error;
/// Record a recoverable R error without non-local control flow.
pub const raise = @import("error_state.zig").raise;
/// Opaque borrowed R value.
pub const Sexp = @import("sexp.zig").Sexp;
/// Missing-value predicates.
pub const NA = @import("na.zig");
/// Last-resort panic handler used by the fixture root module.
pub const Panic = @import("panic.zig").Panic;

/// Framework internals needed by hand-written integration wrappers.
pub const internal = struct {
    pub const boundary = @import("boundary.zig");
    pub const c = @import("c/abi.zig");
};
