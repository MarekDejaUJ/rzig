const boundary = @import("boundary");

fn generic(value: anytype) void {
    _ = value;
}

comptime {
    boundary.validateSignature(generic, "generic");
}
