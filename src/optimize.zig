//! R's optimizers (`optim()`) and numerical integration (`integrate()`) with
//! Zig objective functions.
//!
//! A problem is a pointer to a struct with `pub fn value(self, x: []const f64)
//! f64` (or `rzig.Error!f64`) and, optionally, `pub fn gradient(self, x:
//! []const f64, g: []f64) void` (or `rzig.Error!void`). Without a gradient,
//! derivative-based methods use central differences with the step 1e-3 of
//! `optim()`. An error of a callback is recorded and returned when the
//! optimizer finishes. The routines run inside R_ToplevelExec, because they
//! can signal R errors (for example for non-finite values).

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const Ctx = @import("alloc.zig").Ctx;

const optimfn = *const fn (c_int, [*]f64, ?*anyopaque) callconv(.c) f64;
const optimgr = *const fn (c_int, [*]f64, [*]f64, ?*anyopaque) callconv(.c) void;
const integr_fn = *const fn ([*]f64, c_int, ?*anyopaque) callconv(.c) void;

extern fn vmmin(n: c_int, b: [*]f64, fmin: *f64, fn_: optimfn, gr: optimgr, maxit: c_int, trace: c_int, mask: [*]c_int, abstol: f64, reltol: f64, nreport: c_int, ex: ?*anyopaque, fncount: *c_int, grcount: *c_int, fail: *c_int) void;
extern fn nmmin(n: c_int, bvec: [*]f64, x: [*]f64, fmin: *f64, fn_: optimfn, fail: *c_int, abstol: f64, intol: f64, ex: ?*anyopaque, alpha: f64, bet: f64, gamm: f64, trace: c_int, fncount: *c_int, maxit: c_int) void;
extern fn cgmin(n: c_int, bvec: [*]f64, x: [*]f64, fmin: *f64, fn_: optimfn, gr: optimgr, fail: *c_int, abstol: f64, intol: f64, ex: ?*anyopaque, type_: c_int, trace: c_int, fncount: *c_int, grcount: *c_int, maxit: c_int) void;
extern fn lbfgsb(n: c_int, m: c_int, x: [*]f64, l: [*]f64, u: [*]f64, nbd: [*]c_int, fmin: *f64, fn_: optimfn, gr: optimgr, fail: *c_int, ex: ?*anyopaque, factr: f64, pgtol: f64, fncount: *c_int, grcount: *c_int, maxit: c_int, msg: [*]u8, trace: c_int, nreport: c_int) void;
extern fn Rdqags(f: integr_fn, ex: ?*anyopaque, a: *f64, b: *f64, epsabs: *f64, epsrel: *f64, result: *f64, abserr: *f64, neval: *c_int, ier: *c_int, limit: *c_int, lenw: *c_int, last: *c_int, iwork: [*]c_int, work: [*]f64) void;
extern fn Rdqagi(f: integr_fn, ex: ?*anyopaque, bound: *f64, inf: *c_int, epsabs: *f64, epsrel: *f64, result: *f64, abserr: *f64, neval: *c_int, ier: *c_int, limit: *c_int, lenw: *c_int, last: *c_int, iwork: [*]c_int, work: [*]f64) void;

/// Call `function`, which returns `T` or an error union of it; an error is
/// recorded in `failed` and `fallback` is returned.
fn callRecorded(comptime T: type, result: anytype, failed: *bool, fallback: T) T {
    if (comptime @typeInfo(@TypeOf(result)) == .error_union) {
        return result catch {
            failed.* = true;
            return fallback;
        };
    }
    return result;
}

fn Bridge(comptime Problem: type) type {
    const Base = @typeInfo(Problem).pointer.child;
    return struct {
        const Self = @This();

        problem: Problem,
        failed: bool = false,
        /// Bounds that the differences of the numeric gradient respect (L-BFGS-B).
        lower: ?[]const f64 = null,
        upper: ?[]const f64 = null,

        fn evaluate(self: *Self, x: []const f64) f64 {
            if (self.failed) return std.math.inf(f64);
            return callRecorded(f64, self.problem.value(x), &self.failed, std.math.inf(f64));
        }

        fn value(n: c_int, par: [*]f64, ex: ?*anyopaque) callconv(.c) f64 {
            const self: *Self = @ptrCast(@alignCast(ex.?));
            return self.evaluate(par[0..@intCast(n)]);
        }

        fn gradient(n: c_int, par: [*]f64, gr: [*]f64, ex: ?*anyopaque) callconv(.c) void {
            const self: *Self = @ptrCast(@alignCast(ex.?));
            const count: usize = @intCast(n);
            const x = par[0..count];
            const g = gr[0..count];
            if (self.failed) {
                @memset(g, 0);
                return;
            }
            if (comptime @hasDecl(Base, "gradient")) {
                callRecorded(void, self.problem.gradient(x, g), &self.failed, {});
                return;
            }
            // Central differences with the step of optim() (ndeps = 1e-3),
            // shortened at bounds as optim() does for L-BFGS-B.
            const step = 1e-3;
            for (0..count) |index| {
                const saved = x[index];
                var up = saved + step;
                var step_up: f64 = step;
                if (self.upper) |upper| {
                    if (up > upper[index]) {
                        up = upper[index];
                        step_up = up - saved;
                    }
                }
                var down = saved - step;
                var step_down: f64 = step;
                if (self.lower) |lower| {
                    if (down < lower[index]) {
                        down = lower[index];
                        step_down = saved - down;
                    }
                }
                x[index] = up;
                const above = self.evaluate(x);
                x[index] = down;
                const below = self.evaluate(x);
                x[index] = saved;
                g[index] = (above - below) / (step_up + step_down);
            }
        }
    };
}

/// Run `function` with `args` inside R_ToplevelExec; false if R jumped.
fn guarded(comptime function: anytype, args: anytype) bool {
    const State = struct {
        args: @TypeOf(args),

        fn run(data: ?*anyopaque) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            @call(.auto, function, self.args);
        }
    };
    var state = State{ .args = args };
    return c.R_ToplevelExec(State.run, &state) != c.FALSE;
}

/// General-purpose optimization, as `optim()` does it.
pub const Optimize = struct {
    pub const Method = enum { bfgs, nelder_mead, conjugate_gradient, lbfgsb };

    /// The options of `optim()`'s `control`; `null` means the method's default.
    pub const Options = struct {
        /// Maximum iterations: 100 for the gradient methods, 500 for Nelder-Mead.
        max_iterations: ?i32 = null,
        /// Absolute convergence tolerance (`abstol`).
        abs_tol: f64 = -std.math.inf(f64),
        /// Relative convergence tolerance (`reltol`), sqrt(.Machine$double.eps).
        rel_tol: f64 = 1.4901161193847656e-08,
        /// Lower and upper bounds for `.lbfgsb`; infinite values are no bound.
        lower: ?[]const f64 = null,
        upper: ?[]const f64 = null,
        /// L-BFGS-B tolerances (`factr`, `pgtol`) and memory (`lmm`).
        factr: f64 = 1e7,
        pgtol: f64 = 0,
        lmm: i32 = 5,
        /// Conjugate gradient update: 1 Fletcher-Reeves, 2 Polak-Ribiere, 3 Beale-Sorenson.
        cg_type: i32 = 1,
    };

    pub const Result = struct {
        /// The value of the objective at the solution (`x` holds the solution).
        value: f64,
        /// Evaluations of the objective and of the gradient (`counts`).
        value_count: i32,
        gradient_count: i32,
        /// The `convergence` code of `optim()`: 0 for success, 1 for the
        /// iteration limit, 10 for a degenerate Nelder-Mead simplex, 51 and 52
        /// for warnings and errors of L-BFGS-B.
        code: i32,
    };

    /// Minimize the problem starting at `x`, which receives the solution.
    pub fn minimize(ctx: *Ctx, comptime method: Method, problem: anytype, x: []f64, options: Options) es.Error!Result {
        const Problem = @TypeOf(problem);
        if (comptime @typeInfo(Problem) != .pointer) @compileError("rzig.Optimize.minimize takes a pointer to the problem");
        var bridge = Bridge(Problem){ .problem = problem };
        const n = std.math.cast(c_int, x.len) orelse return es.raise("rzig: too many parameters ({d})", .{x.len});
        if (x.len == 0) return es.raise("rzig: the optimization needs at least one parameter", .{});
        if (comptime method == .lbfgsb) {
            // L-BFGS-B starts from the starting values moved into the bounds.
            if (options.lower) |values| if (values.len != x.len) return es.raise("rzig: `lower` has {d} values for {d} parameters", .{ values.len, x.len });
            if (options.upper) |values| if (values.len != x.len) return es.raise("rzig: `upper` has {d} values for {d} parameters", .{ values.len, x.len });
            for (x, 0..) |*value, index| {
                if (options.lower) |values| value.* = @max(value.*, values[index]);
                if (options.upper) |values| value.* = @min(value.*, values[index]);
            }
        }
        const start = bridge.evaluate(x);
        if (bridge.failed) return es.Error.RZigError;
        if (!std.math.isFinite(start)) {
            return es.raise("rzig: the objective is not finite at the starting values (it is {d})", .{start});
        }
        var result = Result{ .value = start, .value_count = 0, .gradient_count = 0, .code = 0 };
        var fail: c_int = 0;
        var ok = true;
        switch (method) {
            .bfgs => {
                const mask = try ctx.alloc(c_int, x.len);
                @memset(mask, 1);
                ok = guarded(vmmin, .{ n, x.ptr, &result.value, &Bridge(Problem).value, &Bridge(Problem).gradient, options.max_iterations orelse 100, 0, mask.ptr, options.abs_tol, options.rel_tol, 10, @as(?*anyopaque, @ptrCast(&bridge)), &result.value_count, &result.gradient_count, &fail });
            },
            .nelder_mead => {
                const start_point = try ctx.dupe(f64, x);
                ok = guarded(nmmin, .{ n, start_point.ptr, x.ptr, &result.value, &Bridge(Problem).value, &fail, options.abs_tol, options.rel_tol, @as(?*anyopaque, @ptrCast(&bridge)), 1.0, 0.5, 2.0, 0, &result.value_count, options.max_iterations orelse 500 });
                result.gradient_count = -1;
            },
            .conjugate_gradient => {
                const start_point = try ctx.dupe(f64, x);
                ok = guarded(cgmin, .{ n, start_point.ptr, x.ptr, &result.value, &Bridge(Problem).value, &Bridge(Problem).gradient, &fail, options.abs_tol, options.rel_tol, @as(?*anyopaque, @ptrCast(&bridge)), options.cg_type, 0, &result.value_count, &result.gradient_count, options.max_iterations orelse 100 });
            },
            .lbfgsb => {
                const lower = try ctx.alloc(f64, x.len);
                const upper = try ctx.alloc(f64, x.len);
                const nbd = try ctx.alloc(c_int, x.len);
                for (0..x.len) |index| {
                    lower[index] = if (options.lower) |values| values[index] else -std.math.inf(f64);
                    upper[index] = if (options.upper) |values| values[index] else std.math.inf(f64);
                    const has_lower = std.math.isFinite(lower[index]);
                    const has_upper = std.math.isFinite(upper[index]);
                    nbd[index] = if (has_lower and has_upper) 2 else if (has_lower) 1 else if (has_upper) 3 else 0;
                    if (has_lower and has_upper and lower[index] > upper[index]) {
                        return es.raise("rzig: lower bound {d} exceeds upper bound {d} for parameter {d}", .{ lower[index], upper[index], index + 1 });
                    }
                }
                bridge.lower = lower;
                bridge.upper = upper;
                var message: [60]u8 = @splat(0);
                ok = guarded(lbfgsb, .{ n, options.lmm, x.ptr, lower.ptr, upper.ptr, nbd.ptr, &result.value, &Bridge(Problem).value, &Bridge(Problem).gradient, &fail, @as(?*anyopaque, @ptrCast(&bridge)), options.factr, options.pgtol, &result.value_count, &result.gradient_count, options.max_iterations orelse 100, &message, 0, 10 });
            },
        }
        if (bridge.failed) return es.Error.RZigError;
        if (!ok) return es.raise("rzig: the optimizer stopped with an R error (shown above)", .{});
        result.code = fail;
        return result;
    }
};

/// Numerical integration of a function of one variable, as `integrate()`.
pub const Integrate = struct {
    pub const Options = struct {
        /// Relative accuracy requested (`rel.tol`), .Machine$double.eps^0.25.
        rel_tol: f64 = 1.220703125e-04,
        /// Absolute accuracy requested (`abs.tol`); `null` means `rel_tol`.
        abs_tol: ?f64 = null,
        /// Maximum number of subintervals (`subdivisions`).
        subdivisions: i32 = 100,
    };

    pub const Result = struct {
        value: f64,
        abs_error: f64,
        evaluations: i32,
    };

    /// Integrate `integrand.value(x)` from `lower` to `upper`; infinite bounds
    /// are allowed. A failure of QUADPACK is an error with the message of
    /// `integrate()`.
    pub fn integrate(ctx: *Ctx, integrand: anytype, lower: f64, upper: f64, options: Options) es.Error!Result {
        const Integrand = @TypeOf(integrand);
        if (comptime @typeInfo(Integrand) != .pointer) @compileError("rzig.Integrate.integrate takes a pointer to the integrand");
        if (std.math.isNan(lower) or std.math.isNan(upper)) return es.raise("rzig: the limits of integration cannot be NaN", .{});
        if (options.subdivisions < 1) return es.raise("rzig: `subdivisions` must be at least 1", .{});
        const State = struct {
            integrand: Integrand,
            failed: bool = false,
            non_finite: bool = false,
            at: f64 = 0,

            fn run(x: [*]f64, n: c_int, ex: ?*anyopaque) callconv(.c) void {
                const self: *@This() = @ptrCast(@alignCast(ex.?));
                for (x[0..@intCast(n)]) |*point| {
                    if (self.failed or self.non_finite) {
                        point.* = 0;
                        continue;
                    }
                    const where = point.*;
                    const result = callRecorded(f64, self.integrand.value(where), &self.failed, 0);
                    if (!self.failed and !std.math.isFinite(result)) {
                        self.non_finite = true;
                        self.at = where;
                    }
                    point.* = if (std.math.isFinite(result)) result else 0;
                }
            }
        };
        var state = State{ .integrand = integrand };
        var epsabs = options.abs_tol orelse options.rel_tol;
        var epsrel = options.rel_tol;
        var result = Result{ .value = 0, .abs_error = 0, .evaluations = 0 };
        var ier: c_int = 0;
        var limit: c_int = options.subdivisions;
        var lenw: c_int = 4 * limit;
        var last: c_int = 0;
        const iwork = try ctx.alloc(c_int, @intCast(limit));
        const work = try ctx.alloc(f64, @intCast(lenw));
        var ok: bool = undefined;
        if (std.math.isFinite(lower) and std.math.isFinite(upper)) {
            var a = lower;
            var b = upper;
            ok = guarded(Rdqags, .{ &State.run, @as(?*anyopaque, @ptrCast(&state)), &a, &b, &epsabs, &epsrel, &result.value, &result.abs_error, &result.evaluations, &ier, &limit, &lenw, &last, iwork.ptr, work.ptr });
        } else {
            var bound: f64 = 0;
            var inf: c_int = 2;
            if (std.math.isFinite(lower)) {
                bound = lower;
                inf = 1;
            } else if (std.math.isFinite(upper)) {
                bound = upper;
                inf = -1;
            }
            ok = guarded(Rdqagi, .{ &State.run, @as(?*anyopaque, @ptrCast(&state)), &bound, &inf, &epsabs, &epsrel, &result.value, &result.abs_error, &result.evaluations, &ier, &limit, &lenw, &last, iwork.ptr, work.ptr });
        }
        if (state.failed) return es.Error.RZigError;
        if (state.non_finite) return es.raise("rzig: the integrand is not finite at x = {d}", .{state.at});
        if (!ok) return es.raise("rzig: the integration stopped with an R error (shown above)", .{});
        return switch (ier) {
            0 => result,
            1 => es.raise("rzig: maximum number of subdivisions reached", .{}),
            2 => es.raise("rzig: roundoff error was detected", .{}),
            3 => es.raise("rzig: extremely bad integrand behaviour", .{}),
            4 => es.raise("rzig: roundoff error is detected in the extrapolation table", .{}),
            5 => es.raise("rzig: the integral is probably divergent", .{}),
            else => es.raise("rzig: the input is invalid", .{}),
        };
    }
};
