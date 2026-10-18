//! Guarded access to the distributions of R's Rmath library.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const distribution_api = @This();

/// Distribution functions implemented by the linked R runtime.
pub const Rmath = struct {
    /// The parameters of a distribution, named as in R; defaults are R's.
    pub const Params = distribution_api.Params;

    /// The density of `distribution` at `x` (`dnorm`, `dgamma`, ...), or
    /// its logarithm with `.{ .log = true }`. Invalid parameters give NaN, as
    /// in R.
    pub fn density(
        comptime distribution: Distribution,
        x: f64,
        params: distribution_api.Params(distribution),
        options: DensityOptions,
    ) es.Error!f64 {
        return distribution_api.densityOf(distribution, x, params, options);
    }

    /// The distribution function `P[X <= x]` (`pnorm`, `pgamma`, ...), the
    /// upper tail with `.{ .lower_tail = false }`, logarithms with
    /// `.{ .log = true }`.
    pub fn cdf(
        comptime distribution: Distribution,
        x: f64,
        params: distribution_api.Params(distribution),
        options: TailOptions,
    ) es.Error!f64 {
        return distribution_api.cdfOf(distribution, x, params, options);
    }

    /// The quantile function (`qnorm`, `qgamma`, ...) at probability `p`.
    pub fn quantile(
        comptime distribution: Distribution,
        p: f64,
        params: distribution_api.Params(distribution),
        options: TailOptions,
    ) es.Error!f64 {
        return distribution_api.quantileOf(distribution, p, params, options);
    }

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

/// The distributions of R's Rmath library.
pub const Distribution = enum {
    normal,
    uniform,
    gamma,
    beta,
    binomial,
    poisson,
    exponential,
    t,
    chisq,
    f,
    lognormal,
    weibull,
    logistic,
    cauchy,
    geometric,
    hypergeometric,
    negative_binomial,
};

/// The parameters of a distribution, named as in R; defaults are R's.
pub fn Params(comptime distribution: Distribution) type {
    return switch (distribution) {
        .normal => struct { mean: f64 = 0, sd: f64 = 1 },
        .uniform => struct { min: f64 = 0, max: f64 = 1 },
        .gamma => struct { shape: f64, scale: f64 = 1 },
        .beta => struct { shape1: f64, shape2: f64 },
        .binomial => struct { size: f64, prob: f64 },
        .poisson => struct { lambda: f64 },
        .exponential => struct { rate: f64 = 1 },
        .t => struct { df: f64 },
        .chisq => struct { df: f64 },
        .f => struct { df1: f64, df2: f64 },
        .lognormal => struct { meanlog: f64 = 0, sdlog: f64 = 1 },
        .weibull => struct { shape: f64, scale: f64 = 1 },
        .logistic => struct { location: f64 = 0, scale: f64 = 1 },
        .cauchy => struct { location: f64 = 0, scale: f64 = 1 },
        .geometric => struct { prob: f64 },
        .hypergeometric => struct { m: f64, n: f64, k: f64 },
        .negative_binomial => struct { size: f64, prob: f64 },
    };
}

/// Options of a density.
pub const DensityOptions = struct {
    /// Return the logarithm of the density.
    log: bool = false,
};

/// Options of a distribution function or a quantile function.
pub const TailOptions = struct {
    /// `P[X <= x]` when true, `P[X > x]` when false.
    lower_tail: bool = true,
    /// Probabilities are logarithms.
    log: bool = false,
};

pub fn densityOf(comptime distribution: Distribution, x: f64, params: Params(distribution), options: DensityOptions) es.Error!f64 {
    const log: c_int = @intFromBool(options.log);
    return switch (distribution) {
        .normal => guarded(c.Rf_dnorm4, .{ x, params.mean, params.sd, log }),
        .uniform => guarded(c.Rf_dunif, .{ x, params.min, params.max, log }),
        .gamma => guarded(c.Rf_dgamma, .{ x, params.shape, params.scale, log }),
        .beta => guarded(c.Rf_dbeta, .{ x, params.shape1, params.shape2, log }),
        .binomial => guarded(c.Rf_dbinom, .{ x, params.size, params.prob, log }),
        .poisson => guarded(c.Rf_dpois, .{ x, params.lambda, log }),
        .exponential => guarded(c.Rf_dexp, .{ x, 1.0 / params.rate, log }),
        .t => guarded(c.Rf_dt, .{ x, params.df, log }),
        .chisq => guarded(c.Rf_dchisq, .{ x, params.df, log }),
        .f => guarded(c.Rf_df, .{ x, params.df1, params.df2, log }),
        .lognormal => guarded(c.Rf_dlnorm, .{ x, params.meanlog, params.sdlog, log }),
        .weibull => guarded(c.Rf_dweibull, .{ x, params.shape, params.scale, log }),
        .logistic => guarded(c.Rf_dlogis, .{ x, params.location, params.scale, log }),
        .cauchy => guarded(c.Rf_dcauchy, .{ x, params.location, params.scale, log }),
        .geometric => guarded(c.Rf_dgeom, .{ x, params.prob, log }),
        .hypergeometric => guarded(c.Rf_dhyper, .{ x, params.m, params.n, params.k, log }),
        .negative_binomial => guarded(c.Rf_dnbinom, .{ x, params.size, params.prob, log }),
    };
}

pub fn cdfOf(comptime distribution: Distribution, x: f64, params: Params(distribution), options: TailOptions) es.Error!f64 {
    const lower: c_int = @intFromBool(options.lower_tail);
    const log: c_int = @intFromBool(options.log);
    return switch (distribution) {
        .normal => guarded(c.Rf_pnorm5, .{ x, params.mean, params.sd, lower, log }),
        .uniform => guarded(c.Rf_punif, .{ x, params.min, params.max, lower, log }),
        .gamma => guarded(c.Rf_pgamma, .{ x, params.shape, params.scale, lower, log }),
        .beta => guarded(c.Rf_pbeta, .{ x, params.shape1, params.shape2, lower, log }),
        .binomial => guarded(c.Rf_pbinom, .{ x, params.size, params.prob, lower, log }),
        .poisson => guarded(c.Rf_ppois, .{ x, params.lambda, lower, log }),
        .exponential => guarded(c.Rf_pexp, .{ x, 1.0 / params.rate, lower, log }),
        .t => guarded(c.Rf_pt, .{ x, params.df, lower, log }),
        .chisq => guarded(c.Rf_pchisq, .{ x, params.df, lower, log }),
        .f => guarded(c.Rf_pf, .{ x, params.df1, params.df2, lower, log }),
        .lognormal => guarded(c.Rf_plnorm, .{ x, params.meanlog, params.sdlog, lower, log }),
        .weibull => guarded(c.Rf_pweibull, .{ x, params.shape, params.scale, lower, log }),
        .logistic => guarded(c.Rf_plogis, .{ x, params.location, params.scale, lower, log }),
        .cauchy => guarded(c.Rf_pcauchy, .{ x, params.location, params.scale, lower, log }),
        .geometric => guarded(c.Rf_pgeom, .{ x, params.prob, lower, log }),
        .hypergeometric => guarded(c.Rf_phyper, .{ x, params.m, params.n, params.k, lower, log }),
        .negative_binomial => guarded(c.Rf_pnbinom, .{ x, params.size, params.prob, lower, log }),
    };
}

pub fn quantileOf(comptime distribution: Distribution, x: f64, params: Params(distribution), options: TailOptions) es.Error!f64 {
    const lower: c_int = @intFromBool(options.lower_tail);
    const log: c_int = @intFromBool(options.log);
    return switch (distribution) {
        .normal => guarded(c.Rf_qnorm5, .{ x, params.mean, params.sd, lower, log }),
        .uniform => guarded(c.Rf_qunif, .{ x, params.min, params.max, lower, log }),
        .gamma => guarded(c.Rf_qgamma, .{ x, params.shape, params.scale, lower, log }),
        .beta => guarded(c.Rf_qbeta, .{ x, params.shape1, params.shape2, lower, log }),
        .binomial => guarded(c.Rf_qbinom, .{ x, params.size, params.prob, lower, log }),
        .poisson => guarded(c.Rf_qpois, .{ x, params.lambda, lower, log }),
        .exponential => guarded(c.Rf_qexp, .{ x, 1.0 / params.rate, lower, log }),
        .t => guarded(c.Rf_qt, .{ x, params.df, lower, log }),
        .chisq => guarded(c.Rf_qchisq, .{ x, params.df, lower, log }),
        .f => guarded(c.Rf_qf, .{ x, params.df1, params.df2, lower, log }),
        .lognormal => guarded(c.Rf_qlnorm, .{ x, params.meanlog, params.sdlog, lower, log }),
        .weibull => guarded(c.Rf_qweibull, .{ x, params.shape, params.scale, lower, log }),
        .logistic => guarded(c.Rf_qlogis, .{ x, params.location, params.scale, lower, log }),
        .cauchy => guarded(c.Rf_qcauchy, .{ x, params.location, params.scale, lower, log }),
        .geometric => guarded(c.Rf_qgeom, .{ x, params.prob, lower, log }),
        .hypergeometric => guarded(c.Rf_qhyper, .{ x, params.m, params.n, params.k, lower, log }),
        .negative_binomial => guarded(c.Rf_qnbinom, .{ x, params.size, params.prob, lower, log }),
    };
}

/// One draw from R's generator for `distribution`; R's random stream must be
/// active (see `rzig.Rng`).
pub fn drawOf(comptime distribution: Distribution, params: Params(distribution)) f64 {
    return switch (distribution) {
        .normal => c.Rf_rnorm(params.mean, params.sd),
        .uniform => c.Rf_runif(params.min, params.max),
        .gamma => c.Rf_rgamma(params.shape, params.scale),
        .beta => c.Rf_rbeta(params.shape1, params.shape2),
        .binomial => c.Rf_rbinom(params.size, params.prob),
        .poisson => c.Rf_rpois(params.lambda),
        .exponential => c.Rf_rexp(1.0 / params.rate),
        .t => c.Rf_rt(params.df),
        .chisq => c.Rf_rchisq(params.df),
        .f => c.Rf_rf(params.df1, params.df2),
        .lognormal => c.Rf_rlnorm(params.meanlog, params.sdlog),
        .weibull => c.Rf_rweibull(params.shape, params.scale),
        .logistic => c.Rf_rlogis(params.location, params.scale),
        .cauchy => c.Rf_rcauchy(params.location, params.scale),
        .geometric => c.Rf_rgeom(params.prob),
        .hypergeometric => c.Rf_rhyper(params.m, params.n, params.k),
        .negative_binomial => c.Rf_rnbinom(params.size, params.prob),
    };
}

/// Run an Rmath function where an R warning turned into an error by
/// `options(warn = 2)` cannot jump out of Zig code.
fn guarded(comptime function: anytype, args: anytype) es.Error!f64 {
    const State = struct {
        args: @TypeOf(args),
        result: f64 = 0,

        fn run(data: ?*anyopaque) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            self.result = @call(.auto, function, self.args);
        }
    };
    var state = State{ .args = args };
    if (c.R_ToplevelExec(State.run, &state) == c.FALSE) {
        return es.raise("rzig: an R distribution function signalled an error (options(warn = 2) turns its warnings into errors)", .{});
    }
    return state.result;
}
