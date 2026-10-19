const rzig = @import("rzig");

const State = struct {
    progress: *rzig.Progress,
};

fn work(state: *State, index: usize) void {
    _ = state;
    _ = index;
}

comptime {
    rzig.internal.parallel.validateWorker(*State, work);
}
