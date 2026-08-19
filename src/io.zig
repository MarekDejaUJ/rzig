//! Output routing. Writing to stdout/stderr directly violates CRAN policy and
//! breaks Rgui, RStudio and sink().

const std = @import("std");
const c = @import("c/abi.zig");

var scratch: [4096]u8 = undefined;

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrintZ(&scratch, fmt, args) catch {
        c.Rprintf("%s", "<rzig: message too long>");
        return;
    };
    // "%s" rather than passing s as the format string: user data must never be
    // interpreted as a printf format.
    c.Rprintf("%s", s.ptr);
}

pub fn eprintf(comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrintZ(&scratch, fmt, args) catch {
        c.REprintf("%s", "<rzig: message too long>");
        return;
    };
    c.REprintf("%s", s.ptr);
}
