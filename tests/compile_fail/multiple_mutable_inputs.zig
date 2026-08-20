const boundary = @import("boundary");

fn Mut(comptime T: type) type {
    return struct {
        pub const rzig_mut_inner = T;
        data: T,
    };
}

fn ambiguous(first: Mut([]f64), second: Mut([]f64)) void {
    _ = first;
    _ = second;
}

comptime {
    boundary.validateSignature(ambiguous, "ambiguous");
}
