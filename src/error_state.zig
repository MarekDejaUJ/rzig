//! Error message slot and warning queue.
//!
//! A fixed buffer, deliberately: allocating a message while handling an error is
//! how error paths turn into crash paths. Overlong messages truncate with an
//! ellipsis rather than being dropped.

const std = @import("std");

pub const Error = error{RZigError};

const MSG_CAP = 1024;

threadlocal var buf: [MSG_CAP]u8 = undefined;
threadlocal var len: usize = 0;

/// Record a message and return the single RZig error value.
///
/// One error value on purpose: R errors are strings, and a rich Zig
/// error set would only tempt callers into a second error exit.
pub fn raise(comptime fmt: []const u8, args: anytype) Error {
    // Leave room for the trailing sentinel and the ellipsis.
    const written = std.fmt.bufPrint(buf[0 .. MSG_CAP - 5], fmt, args) catch blk: {
        @memcpy(buf[MSG_CAP - 9 .. MSG_CAP - 5], "...");
        break :blk buf[0 .. MSG_CAP - 5];
    };
    len = written.len;
    buf[len] = 0;
    return Error.RZigError;
}

/// Take the current message as a nul-terminated slice and reset the slot.
/// Called by the boundary, and by nobody else.
pub fn take() [:0]const u8 {
    const out = buf[0..len :0];
    len = 0;
    return out;
}

/// Rf_warning can longjmp under options(warn = 2), so warnings must be queued
/// and emitted only at the outer boundary.
pub fn warn(comptime fmt: []const u8, args: anytype) void {
    _ = fmt;
    _ = args;
    @compileError("rzig: warning delivery is not implemented yet");
}

test "message truncates rather than failing" {
    const long = "x" ** 4096;
    _ = raise("{s}", .{long});
    const m = take();
    try std.testing.expect(m.len < MSG_CAP);
}
