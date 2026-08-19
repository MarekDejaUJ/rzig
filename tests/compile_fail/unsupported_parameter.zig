const boundary = @import("boundary");

fn covariance(values: []const f32) void {
    _ = values;
}

comptime {
    boundary.validateSignature(covariance, "covariance");
}
