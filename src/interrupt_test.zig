//! Interrupt trampoline tests with an in-process stand-in for R.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const interrupt = @import("interrupt.zig");

var allow_callback = true;
var probe_count: usize = 0;

export fn R_ToplevelExec(
    callback: *const fn (?*anyopaque) callconv(.c) void,
    data: ?*anyopaque,
) c.Rboolean {
    if (!allow_callback) return c.FALSE;
    callback(data);
    return c.TRUE;
}

export fn R_CheckUserInterrupt() void {
    probe_count += 1;
}

test "checkInterrupt probes through R_ToplevelExec" {
    es.reset();
    allow_callback = true;
    probe_count = 0;
    try interrupt.checkInterrupt();
    try std.testing.expectEqual(@as(usize, 1), probe_count);
}

test "checkInterrupt converts a caught interrupt into an explicit error" {
    es.reset();
    allow_callback = false;
    probe_count = 0;
    try std.testing.expectError(es.Error.RZigError, interrupt.checkInterrupt());
    try std.testing.expectEqualStrings("interrupted by user", es.take());
    try std.testing.expectEqual(@as(usize, 0), probe_count);
}
