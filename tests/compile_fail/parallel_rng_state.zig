const rzig = @import("rzig");

const State = struct {
    random: rzig.Rng,
};

fn work(state: *State, index: usize) void {
    _ = state;
    _ = index;
}

comptime {
    rzig.internal.parallel.validateWorker(*State, work);
}
