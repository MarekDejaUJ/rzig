const boundary = @import("boundary");

fn iterationCount() usize {
    return 0;
}

comptime {
    boundary.validateSignature(iterationCount, "iteration_count");
}
