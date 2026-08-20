const rzig = @import("rzig");

const State = struct {
    context: *rzig.Ctx,
};

fn work(state: *State, index: usize) void {
    _ = state;
    _ = index;
}

comptime {
    rzig.internal.parallel.validateWorker(*State, work);
}
