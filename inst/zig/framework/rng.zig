//! Opt-in access to R's random-number stream.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const rmath = @import("rmath.zig");

/// Calling-thread capability for draws controlled by R's `set.seed()`.
///
/// Obtain this value with `try ctx.rng()`. It is borrowed for the duration of
/// one exported call and must not be retained or sent to a worker thread.
pub const Rng = struct {
    active: *const bool,

    /// Draw one value uniformly from the open interval `(0, 1)`.
    pub fn uniform(self: Rng) f64 {
        self.assertActive();
        return c.unif_rand();
    }

    /// Draw one value from the standard normal distribution.
    pub fn normal(self: Rng) f64 {
        self.assertActive();
        return c.norm_rand();
    }

    /// Draw one value from the standard exponential distribution.
    pub fn exponential(self: Rng) f64 {
        self.assertActive();
        return c.exp_rand();
    }

    /// Draw one value from `distribution` with R's generator for it (`rgamma`,
    /// `rbinom`, ...), so the draws match R's for the same seed.
    pub fn draw(self: Rng, comptime distribution: rmath.Distribution, params: rmath.Params(distribution)) f64 {
        self.assertActive();
        return rmath.drawOf(distribution, params);
    }

    fn assertActive(self: Rng) void {
        std.debug.assert(self.active.*);
    }
};

const BeginState = struct {
    active: *bool,

    fn run(data: ?*anyopaque) callconv(.c) void {
        const self: *BeginState = @ptrCast(@alignCast(data.?));
        c.GetRNGstate();
        self.active.* = true;
    }
};

/// Enter R's RNG state once for the current boundary invocation.
pub fn begin(active: *bool) es.Error!Rng {
    if (!active.*) {
        var state = BeginState{ .active = active };
        if (c.R_ToplevelExec(BeginState.run, &state) == c.FALSE) {
            return es.raise("unable to initialize R's random-number generator", .{});
        }
    }
    return .{ .active = active };
}

/// Save an active RNG state. Called only by the outer boundary cleanup.
pub fn finish(active: bool) void {
    if (active) c.PutRNGstate();
}
