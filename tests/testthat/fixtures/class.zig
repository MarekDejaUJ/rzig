const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

/// A counter that adds its step.
///
/// The count starts at zero.
/// @class
pub const Counter = struct {
    count: i32 = 0,
    step: i32,

    /// Create a counter.
    /// @param step The amount added by each step.
    /// @default step 1L
    pub fn init(step: i32) Counter {
        return .{ .step = step };
    }

    /// Add the step `times` times and return the count.
    pub fn add(self: *Counter, times: i32) rzig.Error!i32 {
        const amount = std.math.mul(i32, self.step, times) catch return rzig.raise("overflow", .{});
        self.count = std.math.add(i32, self.count, amount) catch return rzig.raise("overflow", .{});
        return self.count;
    }

    /// The current count.
    pub fn value(self: *const Counter) i32 {
        return self.count;
    }

    /// The count and the step, as a list.
    pub fn summary(self: Counter, ctx: *rzig.Ctx) rzig.Error!rzig.List {
        var list = rzig.List.init(ctx);
        try list.put("count", self.count);
        try list.put("step", self.step);
        return list;
    }

    pub fn deinit(self: *Counter) void {
        _ = self;
    }

    const Inner = struct {
        pub fn hidden(self: *Inner) void {
            _ = self;
        }
    };
};

/// @export
pub fn plain(x: f64) f64 {
    return x;
}

comptime {
    rzig.registerModule(@This());
}
