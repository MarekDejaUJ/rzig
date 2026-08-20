const boundary = @import("boundary");

fn Mut(comptime T: type) type {
    return struct {
        pub const rzig_mut_inner = T;
        data: T,
    };
}

fn ambiguous_result(values: Mut([]f64)) f64 {
    _ = values;
    return 0;
}

comptime {
    boundary.validateSignature(ambiguous_result, "ambiguous_result");
}
