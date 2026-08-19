//! Last-resort handling for Zig panics reached from R.
//!
//! The default Zig handler terminates the process. RZig instead reports the
//! safety failure through R and raises an R error, allowing the surrounding R
//! evaluation context to recover. This path is allocation-free and deliberately
//! minimal because program state may already be compromised.

const std = @import("std");
const c = @import("c/abi.zig");

const MESSAGE_CAPACITY = 1024;

/// Zig 0.16 panic namespace installed by the RZig root module.
pub const Panic = std.debug.FullPanic(report);

fn report(message: []const u8, first_trace_addr: ?usize) noreturn {
    @branchHint(.cold);

    var storage: [MESSAGE_CAPACITY]u8 = undefined;
    const rendered: [:0]const u8 = if (first_trace_addr) |address|
        std.fmt.bufPrintZ(
            &storage,
            "rzig: internal Zig safety failure: {s}\ntrace origin: 0x{x}",
            .{ message, address },
        ) catch "rzig: internal Zig safety failure"
    else
        std.fmt.bufPrintZ(
            &storage,
            "rzig: internal Zig safety failure: {s}",
            .{message},
        ) catch "rzig: internal Zig safety failure";

    c.REprintf("%s\n", rendered.ptr);
    c.Rf_error("%s", rendered.ptr);
}
