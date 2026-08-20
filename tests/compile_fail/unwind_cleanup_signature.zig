const rzig = @import("rzig");

const State = struct {};

fn body(state: *State) rzig.internal.c.SEXP {
    _ = state;
    return undefined;
}

fn cleanup(state: *State) void {
    _ = state;
}

comptime {
    rzig.internal.unwind.validateCallbacks(*State, body, cleanup);
}
