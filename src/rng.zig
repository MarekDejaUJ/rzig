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

/// Random streams for worker threads, seeded from R's stream (see
/// `ctx.rngStreams()`). Index `i` always gets the same stream for the same
/// seed, so results follow `set.seed()` and do not depend on the number of
/// threads. The streams use Zig's Xoshiro256 generator, not R's generators.
pub const Streams = struct {
    seed: u64,

    /// The stream of `index`.
    pub fn stream(self: Streams, index: usize) Stream {
        const key: u64 = @intCast(index);
        return .{ .prng = std.Random.Xoshiro256.init(std.hash.Wyhash.hash(self.seed, std.mem.asBytes(&key))) };
    }
};

/// One random stream; plain data that a worker may own.
pub const Stream = struct {
    prng: std.Random.Xoshiro256,

    /// Zig's random interface over the stream.
    pub fn random(self: *Stream) std.Random {
        return self.prng.random();
    }

    /// A uniform draw from the open interval (0, 1).
    pub fn uniform(self: *Stream) f64 {
        while (true) {
            const value = self.prng.random().float(f64);
            if (value > 0) return value;
        }
    }

    /// A standard normal draw.
    pub fn normal(self: *Stream) f64 {
        return self.prng.random().floatNorm(f64);
    }

    /// A standard exponential draw.
    pub fn exponential(self: *Stream) f64 {
        return self.prng.random().floatExp(f64);
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
