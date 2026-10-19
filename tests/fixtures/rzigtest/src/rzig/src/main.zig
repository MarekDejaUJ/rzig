const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

/// Route ReleaseSafe failures through R while retaining the Zig test runner.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

var unwind_cleanup_count_value: i32 = 0;

const UnwindProbe = struct {
    memory: []u8,
    cleaned: bool = false,
    jumped: bool = false,

    fn returnNil(state: *UnwindProbe) rzig.internal.c.SEXP {
        _ = state;
        return rzig.internal.c.R_NilValue;
    }

    fn stopInR(state: *UnwindProbe) rzig.internal.c.SEXP {
        _ = state;
        const c = rzig.internal.c;
        const stop_symbol = c.Rf_install("stop");
        var stack = rzig.internal.protect.Stack.init();
        const call = stack.push(c.Rf_lang1(stop_symbol));
        const result = c.Rf_eval(call, c.R_BaseEnv);
        stack.unwindAll();
        stack.deinit();
        return result;
    }

    fn cleanup(state: *UnwindProbe, jumped: bool) void {
        std.heap.c_allocator.free(state.memory);
        state.cleaned = true;
        state.jumped = jumped;
        unwind_cleanup_count_value +|= 1;
    }
};

fn newUnwindProbe() rzig.Error!UnwindProbe {
    const memory = std.heap.c_allocator.alloc(u8, 4096) catch
        return rzig.raise("unable to allocate unwind test resource", .{});
    return .{ .memory = memory };
}

/// Add one to every value in a numeric vector.
/// @export
pub fn add_one(ctx: *rzig.Ctx, values: []const f64) rzig.Error![]f64 {
    const result = try ctx.alloc(f64, values.len);
    for (values, result) |value, *slot| slot.* = value + 1.0;
    return result;
}

/// Return a scalar double unchanged.
/// @export
pub fn echo_f64(value: f64) f64 {
    return value;
}

/// Return a scalar integer unchanged.
/// @export
pub fn echo_i32(value: i32) i32 {
    return value;
}

/// Return a scalar logical unchanged.
/// @export
pub fn echo_bool(value: bool) bool {
    return value;
}

/// Convert a non-negative Zig-sized integer to an R integer.
/// @export
pub fn echo_usize(value: usize) i32 {
    return @intCast(value);
}

/// Return an optional scalar double unchanged.
/// @export
pub fn echo_optional(value: ?f64) ?f64 {
    return value;
}

/// Return a borrowed numeric vector for copying to R.
/// @export
pub fn echo_reals(values: []const f64) []const f64 {
    return values;
}

/// Return a borrowed integer vector for copying to R.
/// @export
pub fn echo_integers(values: []const i32) []const i32 {
    return values;
}

/// Return an arena-backed logical vector for copying to R.
/// @export
pub fn echo_logicals(values: []const bool) []const bool {
    return values;
}

/// Count values in an integer vector.
/// @export
pub fn integer_length(values: []const i32) rzig.Error!i32 {
    if (values.len > std.math.maxInt(i32)) {
        return rzig.raise("integer vector is too long", .{});
    }
    return @intCast(values.len);
}

/// Count true values in a logical vector.
/// @export
pub fn logical_count(values: []const bool) rzig.Error!i32 {
    var count: usize = 0;
    for (values) |value| count += @intFromBool(value);
    if (count > std.math.maxInt(i32)) return rzig.raise("logical vector is too long", .{});
    return @intCast(count);
}

/// Return one UTF-8 string unchanged.
/// @export
pub fn echo_string(value: []const u8) []const u8 {
    return value;
}

/// Return an arena-backed UTF-8 character vector for copying to R.
/// @export
pub fn echo_strings(values: []const []const u8) []const []const u8 {
    return values;
}

/// Count strings in a character vector.
/// @export
pub fn string_count(values: []const []const u8) rzig.Error!i32 {
    if (values.len > std.math.maxInt(i32)) return rzig.raise("string vector is too long", .{});
    return @intCast(values.len);
}

/// Return an arbitrary borrowed R value unchanged.
/// @export
pub fn identity_sexp(value: rzig.Sexp) rzig.Sexp {
    return value;
}

/// Add two numeric vectors elementwise.
/// @export
pub fn add_vectors(ctx: *rzig.Ctx, a: []const f64, b: []const f64) rzig.Error![]f64 {
    if (a.len != b.len) return rzig.raise("lengths differ: {d} vs {d}", .{ a.len, b.len });
    const result = try ctx.alloc(f64, a.len);
    for (a, b, result) |left, right, *slot| slot.* = left + right;
    return result;
}

/// Return a named list containing a vector and its length.
/// @export
pub fn named_summary(ctx: *rzig.Ctx, values: []const f64) rzig.Error!rzig.List {
    if (values.len > std.math.maxInt(i32)) return rzig.raise("numeric vector is too long", .{});
    var result = rzig.List.init(ctx);
    try result.put("values", values);
    try result.put("count", @as(i32, @intCast(values.len)));
    return result;
}

/// Return every supported vector kind inside a named R list.
/// @export
pub fn vector_summary(
    ctx: *rzig.Ctx,
    integers: []const i32,
    logicals: []const bool,
    strings: []const []const u8,
) rzig.Error!rzig.List {
    var result = rzig.List.init(ctx);
    try result.put("integers", integers);
    try result.put("logicals", logicals);
    try result.put("strings", strings);
    return result;
}

/// Attach matrix dimensions to a logical vector.
/// @export
pub fn reshape_logicals(
    ctx: *rzig.Ctx,
    values: []const bool,
    nrow: usize,
) rzig.Error!rzig.Attributed([]const bool) {
    const ncol = if (nrow == 0) blk: {
        if (values.len != 0) return rzig.raise("zero rows require an empty vector", .{});
        break :blk @as(usize, 0);
    } else blk: {
        if (values.len % nrow != 0) {
            return rzig.raise("length {d} is not divisible by {d} rows", .{ values.len, nrow });
        }
        break :blk values.len / nrow;
    };
    if (nrow > std.math.maxInt(i32) or ncol > std.math.maxInt(i32)) {
        return rzig.raise("matrix dimensions exceed R's integer limit", .{});
    }

    const dimensions = [_]i32{ @intCast(nrow), @intCast(ncol) };
    var result = rzig.Attributed([]const bool).init(ctx, values);
    try result.setDim(&dimensions);
    return result;
}

/// Scale a duplicated numeric vector without mutating the caller's input.
/// @export
pub fn scale_in_place(values: rzig.Mut([]f64), factor: f64) void {
    for (values.data) |*value| value.* *= factor;
}

/// Attach names and a class to a numeric vector.
/// @export
pub fn decorate_values(
    ctx: *rzig.Ctx,
    values: []const f64,
    labels: []const []const u8,
) rzig.Error!rzig.Attributed([]const f64) {
    var result = rzig.Attributed([]const f64).init(ctx, values);
    try result.setNames(labels);
    try result.setClass("rzig_values");
    return result;
}

/// Give a numeric vector two-dimensional matrix dimensions.
/// @export
pub fn reshape_values(
    ctx: *rzig.Ctx,
    values: []const f64,
    nrow: usize,
) rzig.Error!rzig.Attributed([]const f64) {
    const ncol = if (nrow == 0) blk: {
        if (values.len != 0) return rzig.raise("zero rows require an empty vector", .{});
        break :blk @as(usize, 0);
    } else blk: {
        if (values.len % nrow != 0) {
            return rzig.raise("length {d} is not divisible by {d} rows", .{ values.len, nrow });
        }
        break :blk values.len / nrow;
    };
    if (nrow > std.math.maxInt(i32) or ncol > std.math.maxInt(i32)) {
        return rzig.raise("matrix dimensions exceed R's integer limit", .{});
    }

    const dimensions = [_]i32{ @intCast(nrow), @intCast(ncol) };
    var result = rzig.Attributed([]const f64).init(ctx, values);
    try result.setDim(&dimensions);
    return result;
}

/// Sum the diagonal of a borrowed numeric matrix.
/// @export
pub fn matrix_trace(values: rzig.Matrix) rzig.Error!f64 {
    if (values.nrow != values.ncol) {
        return rzig.raise("matrix must be square; got {d} x {d}", .{ values.nrow, values.ncol });
    }
    var result: f64 = 0;
    for (0..values.nrow) |index| result += values.data[index + index * values.nrow];
    return result;
}

/// Draw uniforms from R's random-number stream.
/// @export
pub fn draw_uniforms(ctx: *rzig.Ctx, count: usize) rzig.Error![]f64 {
    const random = try ctx.rng();
    const result = try ctx.alloc(f64, count);
    for (result) |*value| value.* = random.uniform();
    return result;
}

/// Draw standard normals from R's random-number stream.
/// @export
pub fn draw_normals(ctx: *rzig.Ctx, count: usize) rzig.Error![]f64 {
    const random = try ctx.rng();
    const result = try ctx.alloc(f64, count);
    for (result) |*value| value.* = random.normal();
    return result;
}

/// Draw once, then fail so boundary cleanup must save the advanced RNG state.
/// @export
pub fn draw_then_error(ctx: *rzig.Ctx) rzig.Error!void {
    const random = try ctx.rng();
    _ = random.uniform();
    return rzig.raise("intentional error after an R RNG draw", .{});
}

/// Evaluate Rmath's normal cumulative distribution function.
/// @export
pub fn normal_cdf(value: f64) rzig.Error!f64 {
    return rzig.Rmath.normalCdf(value, 0.0, 1.0, true, false);
}

/// Evaluate Rmath's normal quantile function.
/// @export
pub fn normal_quantile(probability: f64) rzig.Error!f64 {
    return rzig.Rmath.normalQuantile(probability, 0.0, 1.0, true, false);
}

/// Count iterations while periodically checking for Ctrl-C.
/// @export
pub fn interruptible_count(iterations: usize) rzig.Error!i32 {
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        if (index % 100_000 == 0) try rzig.checkInterrupt();
    }
    return @intCast(index);
}

/// Allocate a resource, then request fixture-only interrupt delivery.
/// @export
pub fn simulate_interrupt(ctx: *rzig.Ctx) rzig.Error!void {
    const memory = try ctx.alloc(u8, 1024 * 1024);
    memory[0] = 1;
    memory[memory.len - 1] = 1;
    return rzig.internal.interrupt.request();
}

/// Describe an R value by its kind, length, first class, number of names and S4 flag.
/// @export
pub fn sexp_describe(ctx: *rzig.Ctx, value: rzig.Sexp) rzig.Error![]const u8 {
    const classes = try value.classes(ctx);
    const names = try value.names(ctx);
    return std.fmt.allocPrint(ctx.allocator(), "{s}[{d}] class={s} names={d} s4={}", .{
        @tagName(value.kind()),
        value.length(),
        if (classes.len > 0) classes[0] else "-",
        if (names) |present| present.len else 0,
        value.isS4(),
    }) catch rzig.raise("out of memory describing a value", .{});
}

/// Sum the numeric list entry called `name`, read through rzig.Sexp.
/// @export
pub fn sexp_sum_entry(ctx: *rzig.Ctx, value: rzig.Sexp, name: []const u8) rzig.Error!f64 {
    const entry = (try value.field(name)) orelse return rzig.raise("no entry `{s}`", .{name});
    var total: f64 = 0;
    for (try entry.get([]const f64, ctx)) |number| total += number;
    return total;
}

/// The length of attribute `name` (an S4 slot is an attribute), or -1.
/// @export
pub fn sexp_attribute_length(value: rzig.Sexp, name: []const u8) rzig.Error!i32 {
    const attribute = (try value.attribute(name)) orelse return -1;
    return @intCast(attribute.length());
}

/// The kinds of the elements of a list.
/// @export
pub fn sexp_element_kinds(ctx: *rzig.Ctx, value: rzig.Sexp) rzig.Error![]const []const u8 {
    const result = try ctx.alloc([]const u8, value.length());
    for (result, 0..) |*slot, index| {
        slot.* = if (value.element(index)) |entry| @tagName(entry.kind()) else "none";
    }
    return result;
}

const Rosenbrock = struct {
    pub fn value(self: *const Rosenbrock, x: []const f64) f64 {
        _ = self;
        const a = x[1] - x[0] * x[0];
        const b = 1 - x[0];
        return 100 * (a * a) + b * b;
    }
};

const RosenbrockWithGradient = struct {
    pub fn value(self: *const RosenbrockWithGradient, x: []const f64) f64 {
        _ = self;
        const a = x[1] - x[0] * x[0];
        const b = 1 - x[0];
        return 100 * (a * a) + b * b;
    }

    pub fn gradient(self: *const RosenbrockWithGradient, x: []const f64, g: []f64) void {
        _ = self;
        g[0] = -400 * x[0] * (x[1] - x[0] * x[0]) - 2 * (1 - x[0]);
        g[1] = 200 * (x[1] - x[0] * x[0]);
    }
};

const FailingObjective = struct {
    pub fn value(self: *const FailingObjective, x: []const f64) rzig.Error!f64 {
        _ = self;
        if (x[0] > 0.5) return rzig.raise("the objective failed at x = {d}", .{x[0]});
        return (x[0] - 2) * (x[0] - 2);
    }
};

const OptimResult = struct {
    par: []f64,
    value: f64,
    fn_count: i32,
    gr_count: i32,
    convergence: i32,
};

fn minimizeBy(ctx: *rzig.Ctx, method: []const u8, problem: anytype, x: []f64, options: rzig.Optimize.Options) rzig.Error!rzig.Optimize.Result {
    if (std.mem.eql(u8, method, "BFGS")) return rzig.Optimize.minimize(ctx, .bfgs, problem, x, options);
    if (std.mem.eql(u8, method, "Nelder-Mead")) return rzig.Optimize.minimize(ctx, .nelder_mead, problem, x, options);
    if (std.mem.eql(u8, method, "CG")) return rzig.Optimize.minimize(ctx, .conjugate_gradient, problem, x, options);
    if (std.mem.eql(u8, method, "L-BFGS-B")) return rzig.Optimize.minimize(ctx, .lbfgsb, problem, x, options);
    return rzig.raise("unknown method {s}", .{method});
}

/// Minimize the Rosenbrock function with an optim() method.
/// @export
pub fn optim_rosenbrock(
    ctx: *rzig.Ctx,
    method: []const u8,
    start: []const f64,
    with_gradient: bool,
    lower: ?[]const f64,
    upper: ?[]const f64,
) rzig.Error!rzig.Record(OptimResult) {
    const x = try ctx.dupe(f64, start);
    const options = rzig.Optimize.Options{ .lower = lower, .upper = upper };
    const result = if (with_gradient)
        try minimizeBy(ctx, method, &RosenbrockWithGradient{}, x, options)
    else
        try minimizeBy(ctx, method, &Rosenbrock{}, x, options);
    return .{ .value = .{
        .par = x,
        .value = result.value,
        .fn_count = result.value_count,
        .gr_count = result.gradient_count,
        .convergence = result.code,
    } };
}

/// Minimize an objective that fails for x > 0.5.
/// @export
pub fn optim_failing(ctx: *rzig.Ctx, start: f64) rzig.Error!f64 {
    const x = try ctx.dupe(f64, &.{start});
    const result = try rzig.Optimize.minimize(ctx, .bfgs, &FailingObjective{}, x, .{});
    return result.value;
}

const Gaussian = struct {
    mean: f64,
    sd: f64,

    pub fn value(self: *const Gaussian, x: f64) f64 {
        const z = (x - self.mean) / self.sd;
        return @exp(-0.5 * z * z) / (self.sd * @sqrt(2 * std.math.pi));
    }
};

const Inverse = struct {
    pub fn value(self: *const Inverse, x: f64) f64 {
        _ = self;
        return 1 / x;
    }
};

const IntegrateResult = struct {
    value: f64,
    abs_error: f64,
    evaluations: i32,
};

/// Integrate a normal density from `lower` to `upper`.
/// @export
pub fn integrate_gaussian(ctx: *rzig.Ctx, mean: f64, sd: f64, lower: f64, upper: f64) rzig.Error!rzig.Record(IntegrateResult) {
    const result = try rzig.Integrate.integrate(ctx, &Gaussian{ .mean = mean, .sd = sd }, lower, upper, .{});
    return .{ .value = .{ .value = result.value, .abs_error = result.abs_error, .evaluations = result.evaluations } };
}

/// Integrate 1 / x, which diverges at 0.
/// @export
pub fn integrate_inverse(ctx: *rzig.Ctx, lower: f64, upper: f64) rzig.Error!f64 {
    return (try rzig.Integrate.integrate(ctx, &Inverse{}, lower, upper, .{})).value;
}

/// Call `f` with `x` and return its numeric result.
/// @export
pub fn call_numeric(ctx: *rzig.Ctx, f: rzig.Function, x: []const f64) rzig.Error![]const f64 {
    return f.call(ctx, []const f64, .{x});
}

/// Call `f` with named arguments `x` and `na.rm`.
/// @export
pub fn call_named(ctx: *rzig.Ctx, f: rzig.Function, x: []const f64) rzig.Error!f64 {
    return f.call(ctx, f64, .{ .x = x, .@"na.rm" = true });
}

/// Call `f` with literal arguments and return its result as it is.
/// @export
pub fn call_literals(ctx: *rzig.Ctx, f: rzig.Function) rzig.Error!rzig.Sexp {
    return f.call(ctx, rzig.Sexp, .{ 2, 2.5, "text", true });
}

/// Call `f` with an R object, which reaches `f` unevaluated.
/// @export
pub fn call_with_object(ctx: *rzig.Ctx, f: rzig.Function, object: rzig.Sexp) rzig.Error!rzig.Sexp {
    return f.call(ctx, rzig.Sexp, .{object});
}

/// Call `outer` with the function `inner` as its argument.
/// @export
pub fn call_with_function(ctx: *rzig.Ctx, outer: rzig.Function, inner: rzig.Function) rzig.Error!f64 {
    return outer.call(ctx, f64, .{inner});
}

/// Call `f` when it is given; -1 for NULL.
/// @export
pub fn call_optional(ctx: *rzig.Ctx, f: ?rzig.Function) rzig.Error!f64 {
    const function = f orelse return -1;
    return function.call(ctx, f64, .{});
}

var cleanups: f64 = 0;

/// Call `f` for its effect; a deferred statement counts the calls that ended.
/// @export
pub fn call_with_cleanup(ctx: *rzig.Ctx, f: rzig.Function) rzig.Error!f64 {
    defer cleanups += 1;
    try f.call(ctx, void, .{});
    return 1;
}

/// The number of calls of `call_with_cleanup` that ended.
/// @export
pub fn call_cleanups() f64 {
    return cleanups;
}

/// Call `f`; `fallback` when `f` fails.
/// @export
pub fn call_or_default(ctx: *rzig.Ctx, f: rzig.Function, fallback: f64) f64 {
    return f.call(ctx, f64, .{}) catch fallback;
}

/// Call `f`; a failure of `f` is replaced by another error.
/// @export
pub fn call_or_raise(ctx: *rzig.Ctx, f: rzig.Function) rzig.Error!f64 {
    return f.call(ctx, f64, .{}) catch rzig.raise("replaced the error of f", .{});
}

/// Queue a warning, call `f`, and queue another warning.
/// @export
pub fn warn_then_call(ctx: *rzig.Ctx, f: rzig.Function) rzig.Error!void {
    rzig.warn("queued before the call", .{});
    try f.call(ctx, void, .{});
    rzig.warn("queued after the call", .{});
}

/// Draw from R's stream, call `f`, which draws as well, and draw again.
/// @export
pub fn rng_around_call(ctx: *rzig.Ctx, f: rzig.Function) rzig.Error![]f64 {
    const generator = try ctx.rng();
    const output = try ctx.alloc(f64, 3);
    output[0] = generator.uniform();
    output[1] = try f.call(ctx, f64, .{});
    output[2] = generator.uniform();
    return output;
}

const RObjective = struct {
    ctx: *rzig.Ctx,
    objective: rzig.Function,

    pub fn value(self: *const RObjective, x: []const f64) rzig.Error!f64 {
        return self.objective.call(self.ctx, f64, .{x});
    }
};

const RObjectiveWithGradient = struct {
    ctx: *rzig.Ctx,
    objective: rzig.Function,
    derivative: rzig.Function,

    pub fn value(self: *const RObjectiveWithGradient, x: []const f64) rzig.Error!f64 {
        return self.objective.call(self.ctx, f64, .{x});
    }

    pub fn gradient(self: *const RObjectiveWithGradient, x: []const f64, g: []f64) rzig.Error!void {
        const result = try self.derivative.call(self.ctx, []const f64, .{x});
        if (result.len != g.len) return rzig.raise("the gradient has {d} values for {d} parameters", .{ result.len, g.len });
        @memcpy(g, result);
    }
};

/// Minimize the R function `f` (with the R gradient `gr`, or NULL) by an optim() method.
/// @export
pub fn optim_r(
    ctx: *rzig.Ctx,
    f: rzig.Function,
    gr: ?rzig.Function,
    start: []const f64,
    method: []const u8,
) rzig.Error!rzig.Record(OptimResult) {
    const x = try ctx.dupe(f64, start);
    const result = if (gr) |derivative|
        try minimizeBy(ctx, method, &RObjectiveWithGradient{ .ctx = ctx, .objective = f, .derivative = derivative }, x, .{})
    else
        try minimizeBy(ctx, method, &RObjective{ .ctx = ctx, .objective = f }, x, .{});
    return .{ .value = .{
        .par = x,
        .value = result.value,
        .fn_count = result.value_count,
        .gr_count = result.gradient_count,
        .convergence = result.code,
    } };
}

const RIntegrand = struct {
    ctx: *rzig.Ctx,
    integrand: rzig.Function,

    pub fn value(self: *const RIntegrand, x: f64) rzig.Error!f64 {
        return self.integrand.call(self.ctx, f64, .{x});
    }
};

/// Integrate the R function `f` from `lower` to `upper`.
/// @export
pub fn integrate_r(ctx: *rzig.Ctx, f: rzig.Function, lower: f64, upper: f64) rzig.Error!f64 {
    return (try rzig.Integrate.integrate(ctx, &RIntegrand{ .ctx = ctx, .integrand = f }, lower, upper, .{})).value;
}

/// The sum of each column of a sparse matrix.
/// @export
pub fn csc_column_sums(ctx: *rzig.Ctx, values: rzig.CscMatrix) rzig.Error![]f64 {
    const sums = try ctx.alloc(f64, values.ncol);
    for (sums, 0..) |*sum, column| {
        sum.* = 0;
        for (values.column(column).values) |value| sum.* += value;
    }
    return sums;
}

/// The product of a sparse matrix and a vector.
/// @export
pub fn csc_times_vector(ctx: *rzig.Ctx, values: rzig.CscMatrix, x: []const f64) rzig.Error![]f64 {
    if (x.len != values.ncol) return rzig.raise("x has {d} values for {d} columns", .{ x.len, values.ncol });
    const y = try ctx.alloc(f64, values.nrow);
    @memset(y, 0);
    for (0..values.ncol) |column| {
        const entries = values.column(column);
        for (entries.rows, entries.values) |row, value| y[@intCast(row)] += value * x[column];
    }
    return y;
}

fn distributionParams(comptime distribution: rzig.Distribution, values: []const f64) rzig.Rmath.Params(distribution) {
    const Params = rzig.Rmath.Params(distribution);
    var params: Params = undefined;
    inline for (comptime rzig.internal.compat.fieldNames(@typeInfo(Params).@"struct"), 0..) |field, index| {
        @field(params, field) = values[index];
    }
    return params;
}

/// Evaluate the density ("d"), distribution function ("p") or quantile ("q")
/// of the distribution named `name` with the parameters `values`.
/// @export
pub fn rmath_eval(kind: []const u8, name: []const u8, x: f64, values: []const f64, lower: bool, log: bool) rzig.Error!f64 {
    inline for (comptime std.enums.values(rzig.Distribution)) |distribution| {
        if (std.mem.eql(u8, name, @tagName(distribution))) {
            const params = distributionParams(distribution, values);
            if (std.mem.eql(u8, kind, "d")) return rzig.Rmath.density(distribution, x, params, .{ .log = log });
            if (std.mem.eql(u8, kind, "p")) return rzig.Rmath.cdf(distribution, x, params, .{ .lower_tail = lower, .log = log });
            if (std.mem.eql(u8, kind, "q")) return rzig.Rmath.quantile(distribution, x, params, .{ .lower_tail = lower, .log = log });
            return rzig.raise("kind must be d, p or q; got {s}", .{kind});
        }
    }
    return rzig.raise("unknown distribution {s}", .{name});
}

/// Draw `count` values from the distribution named `name` with R's generator.
/// @export
pub fn rmath_draws(ctx: *rzig.Ctx, name: []const u8, count: usize, values: []const f64) rzig.Error![]f64 {
    const rng = try ctx.rng();
    const result = try ctx.alloc(f64, count);
    inline for (comptime std.enums.values(rzig.Distribution)) |distribution| {
        if (std.mem.eql(u8, name, @tagName(distribution))) {
            const params = distributionParams(distribution, values);
            for (result) |*slot| slot.* = rng.draw(distribution, params);
            return result;
        }
    }
    return rzig.raise("unknown distribution {s}", .{name});
}

var counters_released: i32 = 0;

const Counter = struct {
    count: i32,
    step: i32,

    pub fn deinit(self: *Counter) void {
        _ = self;
        counters_released += 1;
    }
};

const Other = struct {
    value: f64,
};

/// A counter that keeps its count between calls.
/// @export
pub fn counter_new(ctx: *rzig.Ctx, step: i32) rzig.Error!rzig.External(Counter) {
    return rzig.External(Counter).create(ctx, .{ .count = 0, .step = step });
}

/// Add the step of a counter to its count and return the count.
/// @export
pub fn counter_add(counter: rzig.External(Counter)) rzig.Error!i32 {
    counter.ptr.count = std.math.add(i32, counter.ptr.count, counter.ptr.step) catch
        return rzig.raise("counter overflow", .{});
    return counter.ptr.count;
}

/// Return the counter it receives.
/// @export
pub fn counter_same(counter: rzig.External(Counter)) rzig.External(Counter) {
    return counter;
}

/// The number of counters whose deinit has run.
/// @export
pub fn counters_released_count() i32 {
    return counters_released;
}

/// Create a counter and then fail; the call releases the counter.
/// @export
pub fn counter_fail_after_create(ctx: *rzig.Ctx) rzig.Error!rzig.External(Counter) {
    _ = try rzig.External(Counter).create(ctx, .{ .count = 0, .step = 1 });
    return rzig.raise("failed after creating a counter", .{});
}

/// A value of another type, for type checks.
/// @export
pub fn other_new(ctx: *rzig.Ctx) rzig.Error!rzig.External(Other) {
    return rzig.External(Other).create(ctx, .{ .value = 1.5 });
}

const FitOptions = struct {
    tolerance: f64 = 1e-8,
    @"max.iter": i32 = 100,
    method: []const u8 = "newton",
    weights: ?[]const f64 = null,
};

/// Return the options with their defaults filled in.
/// @export
pub fn record_options(options: rzig.Record(FitOptions)) rzig.Record(FitOptions) {
    return options;
}

const Grouped = struct {
    value: []const f64,
    group: rzig.Factor,
};

const GroupSummary = struct {
    group: []const []const u8,
    mean: []f64,
    n: []i32,
};

/// Mean and count of `value` for each level of `group`; NA groups are skipped.
/// @export
pub fn frame_group_means(ctx: *rzig.Ctx, data: rzig.DataFrame(Grouped)) rzig.Error!rzig.DataFrame(GroupSummary) {
    const levels = data.value.group.levels;
    const mean = try ctx.alloc(f64, levels.len);
    const n = try ctx.alloc(i32, levels.len);
    @memset(mean, 0);
    @memset(n, 0);
    for (data.value.value, data.value.group.codes) |value, code| {
        if (code == rzig.NA.integer) continue;
        const index: usize = @intCast(code - 1);
        mean[index] += value;
        n[index] += 1;
    }
    for (mean, n) |*total, count| total.* = if (count > 0) total.* / @as(f64, @floatFromInt(count)) else rzig.NA.real;
    return .{ .value = .{ .group = levels, .mean = mean, .n = n } };
}

/// Reverse the order of the levels of a factor, keeping each element's level.
/// @export
pub fn factor_reverse_levels(ctx: *rzig.Ctx, values: rzig.Factor) rzig.Error!rzig.Factor {
    const count: i32 = @intCast(values.levels.len);
    const levels = try ctx.alloc([]const u8, values.levels.len);
    for (levels, 0..) |*slot, index| slot.* = values.levels[values.levels.len - 1 - index];
    const codes = try ctx.alloc(i32, values.codes.len);
    for (values.codes, codes) |code, *slot| slot.* = if (code == rzig.NA.integer) code else count + 1 - code;
    return .{ .codes = codes, .levels = levels };
}

/// The number of rows of a data frame and the length of an optional vector.
/// @export
pub fn optional_length(values: ?[]const f64) i32 {
    return if (values) |present| @intCast(present.len) else -1;
}

/// Sum a bit64::integer64 vector, stopping on overflow; NA is skipped.
/// @export
pub fn int64_sum(values: []const i64) rzig.Error!i64 {
    var total: i64 = 0;
    for (values) |value| {
        if (value == rzig.NA.integer64) continue;
        total = std.math.add(i64, total, value) catch return rzig.raise("integer64 overflow", .{});
    }
    return total;
}

/// Double every element of a bit64::integer64 vector.
/// @export
pub fn int64_double(ctx: *rzig.Ctx, values: []const i64) rzig.Error![]i64 {
    const result = try ctx.alloc(i64, values.len);
    for (values, result) |value, *slot| {
        slot.* = if (value == rzig.NA.integer64) value else std.math.mul(i64, value, 2) catch
            return rzig.raise("integer64 overflow", .{});
    }
    return result;
}

/// Return an i64 scalar unchanged, or -1 for NA and NULL.
/// @export
pub fn int64_or_default(value: ?i64) i64 {
    return value orelse -1;
}

/// Return `count` as a double, for counts beyond 2^31 - 1.
/// @export
pub fn long_count(count: i64) f64 {
    return @floatFromInt(count);
}

/// The modulus of each element of a complex vector.
/// @export
pub fn complex_modulus(ctx: *rzig.Ctx, values: []const rzig.Complex) rzig.Error![]f64 {
    const result = try ctx.alloc(f64, values.len);
    for (values, result) |value, *slot| slot.* = std.math.complex.abs(value.toStd());
    return result;
}

/// The complex conjugate of each element.
/// @export
pub fn complex_conjugate(ctx: *rzig.Ctx, values: []const rzig.Complex) rzig.Error![]rzig.Complex {
    const result = try ctx.alloc(rzig.Complex, values.len);
    for (values, result) |value, *slot| slot.* = .{ .re = value.re, .im = -value.im };
    return result;
}

/// Multiply two complex scalars.
/// @export
pub fn complex_product(a: rzig.Complex, b: rzig.Complex) rzig.Complex {
    return rzig.Complex.fromStd(a.toStd().mul(b.toStd()));
}

/// XOR every byte of a raw vector with `key`.
/// @export
pub fn raw_xor(ctx: *rzig.Ctx, bytes: rzig.Raw, key: i32) rzig.Error!rzig.Raw {
    if (key < 0 or key > 255) return rzig.raise("`key` must be from 0 to 255; got {d}", .{key});
    const result = try ctx.alloc(u8, bytes.data.len);
    for (bytes.data, result) |byte, *slot| slot.* = byte ^ @as(u8, @intCast(key));
    return .{ .data = result };
}

/// Count the TRUE, FALSE and NA values of a logical vector.
/// @export
pub fn logical_tally(ctx: *rzig.Ctx, values: []const rzig.Logical) rzig.Error![]i32 {
    const counts = try ctx.alloc(i32, 3);
    @memset(counts, 0);
    for (values) |value| {
        if (value.isNa()) {
            counts[2] += 1;
        } else if (value.isTrue()) {
            counts[0] += 1;
        } else {
            counts[1] += 1;
        }
    }
    return counts;
}

/// Negate a logical vector, keeping NA.
/// @export
pub fn logical_not(ctx: *rzig.Ctx, values: []const rzig.Logical) rzig.Error![]rzig.Logical {
    const result = try ctx.alloc(rzig.Logical, values.len);
    for (values, result) |value, *slot| {
        slot.* = if (value.isNa()) rzig.NA.logical else rzig.Logical.fromBool(!value.isTrue());
    }
    return result;
}

/// Upper-case the ASCII letters of each string, keeping NA.
/// @export
pub fn upper_or_na(ctx: *rzig.Ctx, values: []const ?[]const u8) rzig.Error![]?[]const u8 {
    const result = try ctx.alloc(?[]const u8, values.len);
    for (values, result) |value, *slot| {
        const text = value orelse {
            slot.* = null;
            continue;
        };
        const copy = try ctx.dupe(u8, text);
        for (copy) |*byte| byte.* = std.ascii.toUpper(byte.*);
        slot.* = copy;
    }
    return result;
}

/// Return the label, or "(none)" when it is NA or NULL.
/// @export
pub fn label_or_default(label: ?[]const u8) []const u8 {
    return label orelse "(none)";
}

/// R's missing double.
/// @export
pub fn na_real() f64 {
    return rzig.NA.real;
}

/// R's missing integer.
/// @export
pub fn na_integer() i32 {
    return rzig.NA.integer;
}

/// R's missing logical, as a vector of length 1.
/// @export
pub fn na_logical() []const rzig.Logical {
    return &.{rzig.NA.logical};
}

/// Sum the entries of an integer matrix, column by column.
/// @export
pub fn int_matrix_sum(values: rzig.IntMatrix) rzig.Error!f64 {
    var total: f64 = 0;
    for (0..values.ncol) |column| {
        for (values.column(column)) |value| total += @floatFromInt(value);
    }
    return total;
}

/// Count the TRUE entries in each row of a logical matrix.
/// @export
pub fn bool_matrix_row_counts(ctx: *rzig.Ctx, values: rzig.BoolMatrix) rzig.Error![]i32 {
    const counts = try ctx.alloc(i32, values.nrow);
    @memset(counts, 0);
    for (0..values.nrow) |row| {
        for (0..values.ncol) |column| {
            if (values.at(row, column)) counts[row] += 1;
        }
    }
    return counts;
}

/// Add `step` times the column index to each column of a numeric matrix.
/// @export
pub fn matrix_add_column_index(values: rzig.Mut(rzig.Matrix), step: f64) void {
    for (0..values.data.ncol) |column| {
        for (values.data.column(column)) |*value| value.* += step * @as(f64, @floatFromInt(column));
    }
}

/// Negate the diagonal of an integer matrix in place.
/// @export
pub fn int_matrix_negate_diagonal(values: rzig.Mut(rzig.IntMatrix)) void {
    const count = @min(values.data.nrow, values.data.ncol);
    for (0..count) |index| values.data.set(index, index, -values.data.at(index, index));
}

/// Add `step` to each element of an integer vector in place.
/// @export
pub fn int_add_in_place(values: rzig.Mut([]i32), step: i32) rzig.Error!void {
    for (values.data) |*value| {
        value.* = std.math.add(i32, value.*, step) catch return rzig.raise("integer overflow", .{});
    }
}

/// Return an nrow x ncol matrix of row-major positions with dimnames.
/// @export
pub fn named_matrix(
    ctx: *rzig.Ctx,
    nrow: usize,
    ncol: usize,
    row_names: []const []const u8,
    column_names: []const []const u8,
) rzig.Error!rzig.Attributed([]f64) {
    const values = try ctx.alloc(f64, nrow * ncol);
    for (0..ncol) |column| {
        for (0..nrow) |row| values[column * nrow + row] = @floatFromInt(row * ncol + column + 1);
    }
    var result = rzig.Attributed([]f64).init(ctx, values);
    try result.setMatrix(nrow, ncol);
    try result.setDimnames(if (row_names.len > 0) row_names else null, if (column_names.len > 0) column_names else null);
    return result;
}

/// Print `count` numbered lines to R's output and a summary to its message stream.
/// @export
pub fn console_lines(ctx: *rzig.Ctx, count: usize) rzig.Error!void {
    var line: usize = 1;
    while (line <= count) : (line += 1) try ctx.print("line {d}\n", .{line});
    try ctx.eprint("printed {d} lines\n", .{count});
}

/// Print one line of `width` characters, longer than any fixed buffer.
/// @export
pub fn console_wide(ctx: *rzig.Ctx, width: usize) rzig.Error!void {
    const text = try ctx.alloc(u8, width);
    @memset(text, 'z');
    try ctx.print("{s}\n", .{text});
}

/// Run `total` steps with a progress bar shown when `show` is true.
/// @export
pub fn progress_steps(ctx: *rzig.Ctx, total: usize, show: bool) rzig.Error!i32 {
    var progress = ctx.progress(total, show);
    var step: usize = 0;
    while (step < total) : (step += 1) try progress.add(1);
    try progress.finish();
    return @intCast(step);
}

const Values = struct {
    values: []const f64,

    fn value(state: *const Values, index: usize) f64 {
        return state.values[index];
    }

    fn add(left: f64, right: f64) f64 {
        return left + right;
    }
};

/// Sum a numeric vector on worker threads with parallelReduce.
/// @export
pub fn parallel_sum(ctx: *rzig.Ctx, values: []const f64) rzig.Error!f64 {
    const state = Values{ .values = values };
    return rzig.parallelReduce(ctx, f64, values.len, &state, 0, Values.value, Values.add);
}

const Draws = struct {
    streams: rzig.RngStreams,
    output: []f64,

    fn draw(state: *Draws, index: usize) void {
        var stream = state.streams.stream(index);
        state.output[index] = stream.uniform();
    }
};

/// One uniform draw per index from the random stream of that index.
/// @export
pub fn parallel_uniforms(ctx: *rzig.Ctx, count: usize) rzig.Error![]f64 {
    const output = try ctx.alloc(f64, count);
    var state = Draws{ .streams = try ctx.rngStreams(), .output = output };
    try rzig.parallelFor(ctx, count, &state, Draws.draw);
    return output;
}

const Broken = struct {
    values: []const f64,
    output: []f64,

    fn copy(state: *Broken, index: usize) void {
        // Index `values.len` does not exist: the bounds check fails on a worker.
        const source = if (index == state.output.len / 2) state.values.len else index;
        state.output[index] = state.values[source];
    }
};

/// A parallel loop whose middle index reads past the end of the input.
/// @export
pub fn parallel_out_of_bounds(ctx: *rzig.Ctx, values: []const f64) rzig.Error![]f64 {
    const output = try ctx.alloc(f64, values.len);
    var state = Broken{ .values = values, .output = output };
    try rzig.parallelFor(ctx, values.len, &state, Broken.copy);
    return output;
}

const Counter64 = struct {
    total: std.atomic.Value(u64) = .init(0),

    fn count(state: *Counter64, index: usize) void {
        _ = index;
        _ = state.total.fetchAdd(1, .monotonic);
    }
};

/// Count to `count` on worker threads; long counts are stopped by a user interrupt.
/// @export
pub fn parallel_count(ctx: *rzig.Ctx, count: f64) rzig.Error!f64 {
    var state = Counter64{};
    try rzig.parallelFor(ctx, @intFromFloat(count), &state, Counter64.count);
    return @floatFromInt(state.total.load(.monotonic));
}

/// Report how many worker threads parallelFor uses for `count` indices.
/// @export
pub fn parallel_thread_count(count: usize) rzig.Error!i32 {
    return @intCast(try rzig.parallelThreadCount(count));
}

/// Square a numeric vector using only pure Zig worker threads.
/// @export
pub fn parallel_square(ctx: *rzig.Ctx, values: []const f64) rzig.Error![]f64 {
    const Work = struct {
        input: []const f64,
        output: []f64,

        fn run(work: *@This(), index: usize) void {
            work.output[index] = work.input[index] * work.input[index];
        }
    };

    const result = try ctx.alloc(f64, values.len);
    var work = Work{ .input = values, .output = result };
    try rzig.parallelFor(ctx, values.len, &work, Work.run);
    return result;
}

/// Return the number of resources released by unwind cleanup.
/// @export
pub fn unwind_cleanup_count() i32 {
    return unwind_cleanup_count_value;
}

/// Exercise unwind cleanup after an ordinary R callback return.
/// @export
pub fn unwind_cleanup_normal() rzig.Error!i32 {
    var state = try newUnwindProbe();
    _ = rzig.internal.unwind.protect(&state, UnwindProbe.returnNil, UnwindProbe.cleanup);
    if (!state.cleaned or state.jumped) {
        return rzig.raise("unwind cleanup did not report an ordinary return", .{});
    }
    return unwind_cleanup_count_value;
}

/// Exercise unwind cleanup when evaluation in R raises an error.
/// @export
pub fn unwind_cleanup_error() rzig.Error!void {
    var state = try newUnwindProbe();
    _ = rzig.internal.unwind.protect(&state, UnwindProbe.stopInR, UnwindProbe.cleanup);
    return rzig.raise("R evaluation unexpectedly returned", .{});
}

/// Trigger an intentional ReleaseSafe bounds failure.
/// @export
pub fn panic_bounds(values: []const f64) void {
    const one = [_]u8{0};
    if (one[values.len] == 0) return;
}

/// Allocate scratch memory and then return an intentional error.
/// @export
pub fn allocate_then_error(ctx: *rzig.Ctx) rzig.Error!void {
    const memory = try ctx.alloc(u8, 10 * 1024 * 1024);
    memory[0] = 1;
    memory[memory.len - 1] = 1;
    return rzig.raise("intentional error after allocating 10 MiB", .{});
}

/// Exercise a generated wrapper with no R-visible arguments.
/// @export
pub fn arity_zero() i32 {
    return 0;
}

/// Exercise a generated wrapper with three R-visible arguments.
/// @export
pub fn sum_three(a: f64, b: f64, c: f64) f64 {
    return a + b + c;
}

/// Exercise a generated wrapper with eight R-visible arguments.
/// @export
pub fn sum_eight(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64, g: f64, h: f64) f64 {
    return a + b + c + d + e + f + g + h;
}

/// Verify that Zig's C variadic ABI matches the R toolchain.
/// @export
pub fn ucrt_smoke(value: i32) i32 {
    rzig.internal.c.Rprintf("%s %d\n", "rzig-ucrt", @as(c_int, value));
    return value;
}

comptime {
    rzig.registerModule(@This());
}
