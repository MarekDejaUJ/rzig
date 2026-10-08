const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

/// Compute x + scale * y without changing either R input.
/// @param x The numeric vector to duplicate and update.
/// @param y A borrowed, read-only numeric vector.
/// @param scale The multiplier applied to y.
/// @return A new numeric vector containing the result.
/// @export
pub fn axpy(
    x: rzig.Mut([]f64),
    y: []const f64,
    scale: f64,
) rzig.Error!void {
    if (x.data.len != y.len) {
        return rzig.raise(
            "x and y must have equal lengths; got {d} and {d}",
            .{ x.data.len, y.len },
        );
    }

    for (x.data, y, 0..) |*result, value, index| {
        if (index % 100_000 == 0) try rzig.checkInterrupt();
        result.* += scale * value;
    }
}

comptime {
    rzig.registerModule(@This());
}
