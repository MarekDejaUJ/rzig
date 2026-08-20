const rzig = @import("rzig");

const State = struct {
    failed: bool,
};

fn work(state: *State, index: usize) rzig.Error!void {
    _ = state;
    _ = index;
}

comptime {
    rzig.internal.parallel.validateWorker(*State, work);
}
