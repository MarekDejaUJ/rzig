//! RZig public API. Nothing but re-exports lives here.

const std = @import("std");

pub const Ctx = @import("alloc.zig").Ctx;
pub const Error = @import("error_state.zig").Error;
pub const raise = @import("error_state.zig").raise;
pub const warn = @import("error_state.zig").warn;
pub const NA = @import("na.zig");
pub const Sexp = @import("sexp.zig").Sexp;
pub const List = @import("list.zig").List;
pub const Mut = @import("convert.zig").Mut;
pub const printf = @import("io.zig").printf;
pub const eprintf = @import("io.zig").eprintf;
pub const checkInterrupt = @import("interrupt.zig").checkInterrupt;
pub const registerModule = @import("register.zig").registerModule;

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
