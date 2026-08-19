//! Panic handler. The default Zig handler calls abort(), which kills the R
//! session and violates CRAN policy.
//!
//! This is a best-effort last resort: by the time it runs, a safety check has
//! already failed, so program state is suspect. Calling Rf_error from here is
//! technically calling a longjmp from a corrupt state - but the alternative is
//! taking the user's whole session and everything unsaved in it.
//!
//! VERSION SENSITIVE: the panic interface changed in 0.15 (std.debug.FullPanic).
//! Check the installed standard library source when updating Zig.

const std = @import("std");
const c = @import("c/abi.zig");

pub fn rzigPanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;
    var buf: [512]u8 = undefined;
    const s = std.fmt.bufPrintZ(
        &buf,
        "rzig: internal error (Zig panic): {s}\nThis is a bug in the package, please report it.",
        .{msg},
    ) catch "rzig: internal error (Zig panic)";
    c.REprintf("%s\n", s.ptr);
    c.Rf_error("%s", s.ptr);
}

// TODO: wire this up in the form the pinned Zig version expects, e.g.
//   pub const panic = std.debug.FullPanic(rzigPanic);
// in the root module. Verify against the installed compiler, do not guess.
