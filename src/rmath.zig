//! Guarded access to a small, deterministic Rmath surface.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");

/// Normal-distribution functions implemented by the linked R runtime.
pub const Rmath = struct {
    /// Evaluate the normal cumulative distribution function.
    pub fn normalCdf(
        value: f64,
        mean: f64,
        standard_deviation: f64,
        lower_tail: bool,
        log_probability: bool,
    ) es.Error!f64 {
        if (std.math.isNan(value)) return es.raise("normal CDF value cannot be NaN", .{});
        try validateLocationScale(mean, standard_deviation, false);
        var state = NormalCdfState{
            .value = value,
            .mean = mean,
            .standard_deviation = standard_deviation,
            .lower_tail = lower_tail,
            .log_probability = log_probability,
        };
        if (c.R_ToplevelExec(NormalCdfState.run, &state) == c.FALSE) {
            return es.raise("normal CDF evaluation did not return normally", .{});
        }
        return state.result;
    }

    /// Evaluate the normal quantile function.
    pub fn normalQuantile(
        probability: f64,
        mean: f64,
        standard_deviation: f64,
        lower_tail: bool,
        log_probability: bool,
    ) es.Error!f64 {
        if (std.math.isNan(probability)) {
            return es.raise("normal quantile probability cannot be NaN", .{});
        }
        if (log_probability) {
            if (probability > 0.0) {
                return es.raise("log probability must be less than or equal to zero; got {d}", .{probability});
            }
        } else if (probability < 0.0 or probability > 1.0) {
            return es.raise("probability must be between zero and one; got {d}", .{probability});
        }
        try validateLocationScale(mean, standard_deviation, true);
        var state = NormalQuantileState{
            .probability = probability,
            .mean = mean,
            .standard_deviation = standard_deviation,
            .lower_tail = lower_tail,
            .log_probability = log_probability,
        };
        if (c.R_ToplevelExec(NormalQuantileState.run, &state) == c.FALSE) {
            return es.raise("normal quantile evaluation did not return normally", .{});
        }
        return state.result;
    }
};

const NormalCdfState = struct {
    value: f64,
    mean: f64,
    standard_deviation: f64,
    lower_tail: bool,
    log_probability: bool,
    result: f64 = 0.0,

    fn run(data: ?*anyopaque) callconv(.c) void {
        const self: *NormalCdfState = @ptrCast(@alignCast(data.?));
        self.result = c.Rf_pnorm5(
            self.value,
            self.mean,
            self.standard_deviation,
            @intFromBool(self.lower_tail),
            @intFromBool(self.log_probability),
        );
    }
};

const NormalQuantileState = struct {
    probability: f64,
    mean: f64,
    standard_deviation: f64,
    lower_tail: bool,
    log_probability: bool,
    result: f64 = 0.0,

    fn run(data: ?*anyopaque) callconv(.c) void {
        const self: *NormalQuantileState = @ptrCast(@alignCast(data.?));
        self.result = c.Rf_qnorm5(
            self.probability,
            self.mean,
            self.standard_deviation,
            @intFromBool(self.lower_tail),
            @intFromBool(self.log_probability),
        );
    }
};

fn validateLocationScale(mean: f64, standard_deviation: f64, allow_zero: bool) es.Error!void {
    if (!std.math.isFinite(mean)) return es.raise("normal mean must be finite; got {d}", .{mean});
    if (!std.math.isFinite(standard_deviation) or
        standard_deviation < 0.0 or (!allow_zero and standard_deviation == 0.0))
    {
        const relation = if (allow_zero) "non-negative" else "positive";
        return es.raise(
            "normal standard deviation must be finite and {s}; got {d}",
            .{ relation, standard_deviation },
        );
    }
}
