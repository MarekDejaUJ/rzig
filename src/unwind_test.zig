//! Compile-time tests for typed R unwind callbacks.

const std = @import("std");
const c = @import("c/abi.zig");
const unwind = @import("unwind.zig");

const State = struct {
    cleaned: bool = false,
};

fn body(state: *State) c.SEXP {
    _ = state;
    return undefined;
}

fn cleanup(state: *State, jumped: bool) void {
    state.cleaned = true;
    _ = jumped;
}

test "unwind protection accepts typed body and cleanup callbacks" {
    comptime unwind.validateCallbacks(*State, body, cleanup);
    std.testing.refAllDecls(unwind);
}
