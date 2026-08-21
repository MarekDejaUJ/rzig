//! RNG and Rmath tests with in-process stand-ins for R.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const rng = @import("rng.zig");
const Rmath = @import("rmath.zig").Rmath;

var allow_callback = true;
var get_count: usize = 0;
var put_count: usize = 0;
var uniform_count: usize = 0;
var normal_count: usize = 0;
var exponential_count: usize = 0;
var pnorm_count: usize = 0;
var qnorm_count: usize = 0;

export fn R_ToplevelExec(
    callback: *const fn (?*anyopaque) callconv(.c) void,
    data: ?*anyopaque,
) c.Rboolean {
    if (!allow_callback) return c.FALSE;
    callback(data);
    return c.TRUE;
}

export fn GetRNGstate() void {
    get_count += 1;
}

export fn PutRNGstate() void {
    put_count += 1;
}

export fn unif_rand() f64 {
    uniform_count += 1;
    return 0.25;
}

export fn norm_rand() f64 {
    normal_count += 1;
    return -0.5;
}

export fn exp_rand() f64 {
    exponential_count += 1;
    return 1.5;
}

export fn Rf_pnorm5(
    value: f64,
    mean: f64,
    standard_deviation: f64,
    lower_tail: c_int,
    log_probability: c_int,
) f64 {
    pnorm_count += 1;
    return value + mean + standard_deviation +
        @as(f64, @floatFromInt(lower_tail + log_probability));
}

export fn Rf_qnorm5(
    probability: f64,
    mean: f64,
    standard_deviation: f64,
    lower_tail: c_int,
    log_probability: c_int,
) f64 {
    qnorm_count += 1;
    return probability + mean + standard_deviation +
        @as(f64, @floatFromInt(lower_tail + log_probability));
}

fn resetMocks() void {
    es.reset();
    allow_callback = true;
    get_count = 0;
    put_count = 0;
    uniform_count = 0;
    normal_count = 0;
    exponential_count = 0;
    pnorm_count = 0;
    qnorm_count = 0;
}

test "RNG state enters once and provides R-controlled draws" {
    resetMocks();
    var active = false;
    const first = try rng.begin(&active);
    const second = try rng.begin(&active);

    try std.testing.expect(active);
    try std.testing.expectEqual(@as(usize, 1), get_count);
    try std.testing.expectEqual(@as(f64, 0.25), first.uniform());
    try std.testing.expectEqual(@as(f64, -0.5), second.normal());
    try std.testing.expectEqual(@as(f64, 1.5), first.exponential());
    try std.testing.expectEqual(@as(usize, 1), uniform_count);
    try std.testing.expectEqual(@as(usize, 1), normal_count);
    try std.testing.expectEqual(@as(usize, 1), exponential_count);

    rng.finish(active);
    try std.testing.expectEqual(@as(usize, 1), put_count);
}

test "RNG initialization failure stays in explicit error flow" {
    resetMocks();
    allow_callback = false;
    var active = false;

    try std.testing.expectError(es.Error.RZigError, rng.begin(&active));
    try std.testing.expect(!active);
    try std.testing.expectEqualStrings(
        "unable to initialize R's random-number generator",
        es.take(),
    );
    rng.finish(active);
    try std.testing.expectEqual(@as(usize, 0), put_count);
}

test "normal Rmath calls use guarded callbacks" {
    resetMocks();
    const cdf = try Rmath.normalCdf(0.5, 1.0, 2.0, true, false);
    const quantile = try Rmath.normalQuantile(-0.25, -1.0, 3.0, false, true);

    try std.testing.expectEqual(@as(f64, 4.5), cdf);
    try std.testing.expectEqual(@as(f64, 2.75), quantile);
    try std.testing.expectEqual(@as(usize, 1), pnorm_count);
    try std.testing.expectEqual(@as(usize, 1), qnorm_count);
}

test "normal Rmath validates inputs before entering R" {
    resetMocks();
    try std.testing.expectError(
        es.Error.RZigError,
        Rmath.normalQuantile(1.1, 0.0, 1.0, true, false),
    );
    try std.testing.expectEqualStrings(
        "probability must be between zero and one; got 1.1",
        es.take(),
    );
    try std.testing.expectError(
        es.Error.RZigError,
        Rmath.normalCdf(0.0, 0.0, 0.0, true, false),
    );
    try std.testing.expectEqualStrings(
        "normal standard deviation must be finite and positive; got 0",
        es.take(),
    );
    try std.testing.expectEqual(@as(usize, 0), pnorm_count);
    try std.testing.expectEqual(@as(usize, 0), qnorm_count);
}

test "caught Rmath non-local exits become explicit errors" {
    resetMocks();
    allow_callback = false;
    try std.testing.expectError(
        es.Error.RZigError,
        Rmath.normalCdf(0.0, 0.0, 1.0, true, false),
    );
    try std.testing.expectEqualStrings("normal CDF evaluation did not return normally", es.take());
}
