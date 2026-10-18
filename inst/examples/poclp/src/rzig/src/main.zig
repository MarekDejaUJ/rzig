const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");
const lp = @import("lp.zig");
const poc = @import("poc.zig");

/// Route ReleaseSafe failures through R while retaining Zig test behavior.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

const max_iterations: usize = 50_000;
const sum_tolerance: f64 = 1e-9;
const points_per_chunk: usize = 256;
const max_chunks: usize = 4096;
const status_names = [_][]const u8{
    "optimal", "infeasible", "unbounded", "iteration_limit",
};
const bound_names = [_][]const u8{
    "PNS_lower", "PNS_upper", "PN_lower", "PN_upper", "PS_lower", "PS_upper",
};

fn statusName(status: lp.Status) []const u8 {
    return status_names[@intCast(@intFromEnum(status))];
}

/// Solve a linear program in equality form by the two-phase simplex method.
/// @param a The constraint matrix.
/// @param b The right-hand sides of the equality constraints.
/// @param objective The objective coefficients.
/// @param maximize Whether to maximize the objective.
/// @return A list with the status, the optimal value, the solution and
/// the number of pivots.
/// @export
pub fn lp_solve(
    ctx: *rzig.Ctx,
    a: rzig.Matrix,
    b: []const f64,
    objective: []const f64,
    maximize: bool,
) rzig.Error!rzig.List {
    if (a.ncol == 0) {
        return rzig.raise("`a` needs at least one column", .{});
    }
    if (a.nrow != b.len) {
        return rzig.raise(
            "`a` has {d} rows but `b` has {d} values",
            .{ a.nrow, b.len },
        );
    }
    if (a.ncol != objective.len) {
        return rzig.raise(
            "`a` has {d} columns but `objective` has {d} values",
            .{ a.ncol, objective.len },
        );
    }
    try requireFinite(a.data, "a");
    try requireFinite(b, "b");
    try requireFinite(objective, "objective");

    var ws = try workspace(ctx, a.nrow, a.ncol);
    var first_pivots: usize = 0;
    const feasibility =
        lp.phaseOne(&ws, a.data, b, max_iterations, &first_pivots);
    const result: lp.Result = if (feasibility == .optimal)
        lp.phaseTwo(&ws, objective, maximize, max_iterations)
    else
        .{
            .status = feasibility,
            .value = std.math.nan(f64),
            .iterations = 0,
        };

    var solution: ?[]f64 = null;
    if (result.status == .optimal) {
        const values = try ctx.alloc(f64, a.ncol);
        lp.primal(&ws, values);
        solution = values;
    }
    const pivots = @min(first_pivots + result.iterations, 2_000_000_000);
    var out = rzig.List.init(ctx);
    try out.put("status", statusName(result.status));
    try out.put("objective", result.value);
    try out.put("solution", solution);
    try out.put("pivots", @as(i32, @intCast(pivots)));
    return out;
}

/// Bound the probabilities of causation by the response-type linear program.
/// @param observed The observational distribution, treatment levels in rows
/// and outcome levels in columns.
/// @param experimental The experimental distributions, one row per
/// treatment level.
/// @param x The treatment level of the query, counted from one.
/// @param y The outcome level under treatment level x.
/// @param x_prime The contrasting treatment level.
/// @param y_prime The outcome level under treatment level x_prime.
/// @return Lower and upper bounds of PNS, PN and PS.
/// @export
pub fn poc_bounds(
    ctx: *rzig.Ctx,
    observed: rzig.Matrix,
    experimental: rzig.Matrix,
    x: usize,
    y: usize,
    x_prime: usize,
    y_prime: usize,
) rzig.Error!rzig.Attributed([]const f64) {
    const s = try checkProblem(observed, experimental);
    try checkQuery(s, x, y, x_prime, y_prime);

    const a = try ctx.alloc(f64, s.rows * s.columns);
    poc.constraints(s, a);
    const b = try ctx.alloc(f64, s.rows);
    poc.rightHandSide(s, observed.data, experimental.data, b);

    var feasible = try workspace(ctx, s.rows, s.columns);
    var scratch = try workspace(ctx, s.rows, s.columns);
    var pivots: usize = 0;
    switch (lp.phaseOne(&feasible, a, b, max_iterations, &pivots)) {
        .optimal => {},
        .infeasible => return rzig.raise(
            "the experimental distribution is incompatible with " ++
                "the observational distribution",
            .{},
        ),
        else => return rzig.raise(
            "phase one stopped after {d} pivots",
            .{pivots},
        ),
    }

    const denominators = [3]f64{
        1.0,
        observed.data[(x - 1) + (y - 1) * s.m],
        observed.data[(x_prime - 1) + (y_prime - 1) * s.m],
    };
    const c = try ctx.alloc(f64, s.columns);
    const bounds = try ctx.alloc(f64, 6);
    const quantities = [_]poc.Quantity{ .pns, .pn, .ps };
    for (quantities, 0..) |quantity, index| {
        poc.objective(s, quantity, x - 1, y - 1, x_prime - 1, y_prime - 1, c);
        for ([_]bool{ false, true }, 0..) |maximize, side| {
            try rzig.checkInterrupt();
            scratch.copyFrom(&feasible);
            const result =
                lp.phaseTwo(&scratch, c, maximize, max_iterations);
            if (result.status != .optimal) {
                return rzig.raise(
                    "phase two ended with status {s}",
                    .{statusName(result.status)},
                );
            }
            bounds[2 * index + side] =
                scaled(result.value, denominators[index]);
        }
    }
    if (denominators[1] == 0.0) {
        rzig.warn("P(X = x, Y = y) is zero, so PN is undefined", .{});
    }
    if (denominators[2] == 0.0) {
        rzig.warn("P(X = x', Y = y') is zero, so PS is undefined", .{});
    }

    var out = rzig.Attributed([]const f64).init(ctx, bounds);
    try out.setNames(&bound_names);
    try out.setClass("poc_bounds");
    return out;
}

const GridWork = struct {
    a: []const f64,
    rows: usize,
    columns: usize,
    observed: []const f64,
    risk_treated: []const f64,
    risk_control: []const f64,
    objectives: []const f64,
    denominators: [3]f64,
    first_point: usize,
    batch_points: usize,
    total_points: usize,
    cells_per_tableau: usize,
    rhs: []f64,
    cells: []f64,
    basis: []usize,
    active: []bool,
    output: []f64,
    status: []i32,

    fn tableau(work: *GridWork, chunk: usize, slot: usize) lp.Workspace {
        const index = 2 * chunk + slot;
        const size = work.cells_per_tableau;
        return .{
            .rows = work.rows,
            .columns = work.columns,
            .cells = work.cells[index * size ..][0..size],
            .basis = work.basis[index * work.rows ..][0..work.rows],
            .active = work.active[index * work.rows ..][0..work.rows],
        };
    }

    fn run(work: *GridWork, chunk: usize) void {
        const start = chunk * points_per_chunk;
        if (start >= work.batch_points) return;
        const stop = @min(start + points_per_chunk, work.batch_points);
        var feasible = work.tableau(chunk, 0);
        var scratch = work.tableau(chunk, 1);
        const b = work.rhs[chunk * work.rows ..][0..work.rows];
        const shape = poc.shape(2, 2).?;
        const total = work.total_points;
        const levels = work.risk_treated.len;

        for (start..stop) |local| {
            const point = work.first_point + local;
            const treated = work.risk_treated[point % levels];
            const control = work.risk_control[point / levels];
            const experimental =
                [4]f64{ 1.0 - control, 1.0 - treated, control, treated };
            poc.rightHandSide(shape, work.observed, &experimental, b);

            var pivots: usize = 0;
            const feasibility =
                lp.phaseOne(&feasible, work.a, b, max_iterations, &pivots);
            work.status[point] = @intFromEnum(feasibility);
            for (0..6) |k| {
                work.output[point + k * total] = std.math.nan(f64);
            }
            if (feasibility != .optimal) continue;

            for (0..3) |q| {
                const width = work.columns;
                const c = work.objectives[q * width ..][0..width];
                for (0..2) |side| {
                    scratch.copyFrom(&feasible);
                    const result =
                        lp.phaseTwo(&scratch, c, side == 1, max_iterations);
                    if (result.status != .optimal) {
                        work.status[point] = @intFromEnum(result.status);
                    }
                    work.output[point + (2 * q + side) * total] =
                        scaled(result.value, work.denominators[q]);
                }
            }
        }
    }
};

/// Bound PNS, PN and PS over a grid of experimental risks for a binary
/// treatment and outcome.
/// @param observed The 2 x 2 observational distribution with the control
/// level in row 1, the treated level in row 2, failure in column 1 and
/// success in column 2.
/// @param risk_treated Experimental risks of success under the treated
/// level.
/// @param risk_control Experimental risks of success under the control
/// level.
/// @param chunks The number of work chunks per batch; values above one
/// allow worker threads.
/// @return A matrix with one row per grid point, the treated risk varying
/// fastest, and six columns of bounds.
/// @export
pub fn poc_grid(
    ctx: *rzig.Ctx,
    observed: rzig.Matrix,
    risk_treated: []const f64,
    risk_control: []const f64,
    chunks: usize,
) rzig.Error!rzig.Attributed([]const f64) {
    if (observed.nrow != 2 or observed.ncol != 2) {
        return rzig.raise(
            "`observed` must be a 2 x 2 matrix; got {d} x {d}",
            .{ observed.nrow, observed.ncol },
        );
    }
    try checkObserved(observed);
    try requireProbabilities(risk_treated, "risk_treated");
    try requireProbabilities(risk_control, "risk_control");
    if (risk_treated.len == 0 or risk_control.len == 0) {
        return rzig.raise("both risk vectors need at least one value", .{});
    }
    if (chunks == 0 or chunks > max_chunks) {
        return rzig.raise(
            "`chunks` must be between 1 and {d}; got {d}",
            .{ max_chunks, chunks },
        );
    }
    const total_points =
        std.math.mul(usize, risk_treated.len, risk_control.len) catch
            return rzig.raise("the grid is too large", .{});
    if (total_points > std.math.maxInt(i32) / 6) {
        return rzig.raise("the grid is too large", .{});
    }

    const s = poc.shape(2, 2).?;
    const a = try ctx.alloc(f64, s.rows * s.columns);
    poc.constraints(s, a);
    const objectives = try ctx.alloc(f64, 3 * s.columns);
    const quantities = [_]poc.Quantity{ .pns, .pn, .ps };
    for (quantities, 0..) |quantity, index| {
        const c = objectives[index * s.columns ..][0..s.columns];
        poc.objective(s, quantity, 1, 1, 0, 0, c);
    }
    const cells_per_tableau = lp.cellCount(s.rows, s.columns).?;
    var work = GridWork{
        .a = a,
        .rows = s.rows,
        .columns = s.columns,
        .observed = observed.data,
        .risk_treated = risk_treated,
        .risk_control = risk_control,
        .objectives = objectives,
        .denominators = .{ 1.0, observed.data[3], observed.data[0] },
        .first_point = 0,
        .batch_points = 0,
        .total_points = total_points,
        .cells_per_tableau = cells_per_tableau,
        .rhs = try ctx.alloc(f64, chunks * s.rows),
        .cells = try ctx.alloc(f64, 2 * chunks * cells_per_tableau),
        .basis = try ctx.alloc(usize, 2 * chunks * s.rows),
        .active = try ctx.alloc(bool, 2 * chunks * s.rows),
        .output = try ctx.alloc(f64, 6 * total_points),
        .status = try ctx.alloc(i32, total_points),
    };

    const capacity = chunks * points_per_chunk;
    while (work.first_point < total_points) {
        work.batch_points = @min(capacity, total_points - work.first_point);
        const used = (work.batch_points + points_per_chunk - 1) /
            points_per_chunk;
        try rzig.parallelFor(ctx, used, &work, GridWork.run);
        try rzig.checkInterrupt();
        work.first_point += work.batch_points;
    }

    var incompatible: usize = 0;
    for (work.status) |code| {
        const status: lp.Status = @enumFromInt(code);
        switch (status) {
            .optimal => {},
            .infeasible => incompatible += 1,
            else => return rzig.raise(
                "a grid point ended with status {s}",
                .{statusName(status)},
            ),
        }
    }
    if (incompatible > 0) {
        rzig.warn(
            "{d} of {d} grid points are incompatible with the " ++
                "observational distribution; their bounds are NaN",
            .{ incompatible, total_points },
        );
    }

    var out = rzig.Attributed([]const f64).init(ctx, work.output);
    const dimensions = [_]i32{ @intCast(total_points), 6 };
    try out.setDim(&dimensions);
    return out;
}

fn scaled(value: f64, denominator: f64) f64 {
    if (denominator == 0.0 or std.math.isNan(value)) {
        return std.math.nan(f64);
    }
    const ratio = value / denominator;
    return if (@abs(ratio) < 1e-12) 0.0 else ratio;
}

fn workspace(
    ctx: *rzig.Ctx,
    rows: usize,
    columns: usize,
) rzig.Error!lp.Workspace {
    const cells = try cellLimit(rows, columns);
    return .{
        .rows = rows,
        .columns = columns,
        .cells = try ctx.alloc(f64, cells),
        .basis = try ctx.alloc(usize, rows),
        .active = try ctx.alloc(bool, rows),
    };
}

fn checkObserved(observed: rzig.Matrix) rzig.Error!void {
    if (observed.nrow < 2 or observed.ncol < 2) {
        return rzig.raise(
            "`observed` needs at least two treatment and two outcome levels",
            .{},
        );
    }
    try requireProbabilities(observed.data, "observed");
    var total: f64 = 0.0;
    for (observed.data) |value| total += value;
    if (@abs(total - 1.0) > sum_tolerance) {
        return rzig.raise(
            "`observed` must sum to one; the sum is {d}",
            .{total},
        );
    }
}

fn checkProblem(
    observed: rzig.Matrix,
    experimental: rzig.Matrix,
) rzig.Error!poc.Shape {
    try checkObserved(observed);
    if (experimental.nrow != observed.nrow or
        experimental.ncol != observed.ncol)
    {
        return rzig.raise(
            "`experimental` must have the dimensions of `observed`",
            .{},
        );
    }
    try requireProbabilities(experimental.data, "experimental");
    const m = experimental.nrow;
    for (0..m) |level| {
        var row_total: f64 = 0.0;
        for (0..experimental.ncol) |outcome| {
            row_total += experimental.data[level + outcome * m];
        }
        if (@abs(row_total - 1.0) > sum_tolerance) {
            return rzig.raise(
                "row {d} of `experimental` must sum to one; the sum is {d}",
                .{ level + 1, row_total },
            );
        }
    }
    const s = poc.shape(observed.nrow, observed.ncol) orelse
        return rzig.raise("the linear program is too large", .{});
    _ = try cellLimit(s.rows, s.columns);
    return s;
}

fn cellLimit(rows: usize, columns: usize) rzig.Error!usize {
    const cells = lp.cellCount(rows, columns) orelse
        return rzig.raise("the linear program is too large", .{});
    if (cells > poc.max_cells) {
        return rzig.raise(
            "the linear program needs {d} tableau cells; the limit is {d}",
            .{ cells, poc.max_cells },
        );
    }
    return cells;
}

fn checkQuery(
    s: poc.Shape,
    x: usize,
    y: usize,
    x_prime: usize,
    y_prime: usize,
) rzig.Error!void {
    if (x < 1 or x > s.m or x_prime < 1 or x_prime > s.m) {
        return rzig.raise(
            "treatment levels must lie between 1 and {d}",
            .{s.m},
        );
    }
    if (y < 1 or y > s.n or y_prime < 1 or y_prime > s.n) {
        return rzig.raise(
            "outcome levels must lie between 1 and {d}",
            .{s.n},
        );
    }
    if (x == x_prime) {
        return rzig.raise("`x` and `x_prime` must differ", .{});
    }
}

fn requireFinite(
    values: []const f64,
    comptime name: []const u8,
) rzig.Error!void {
    for (values, 0..) |value, index| {
        if (!std.math.isFinite(value)) {
            return rzig.raise(
                "`" ++ name ++ "` must be finite; element {d} is not",
                .{index + 1},
            );
        }
    }
}

fn requireProbabilities(
    values: []const f64,
    comptime name: []const u8,
) rzig.Error!void {
    try requireFinite(values, name);
    for (values, 0..) |value, index| {
        if (value < 0.0 or value > 1.0) {
            return rzig.raise(
                "`" ++ name ++ "` must lie in [0, 1]; element {d} is {d}",
                .{ index + 1, value },
            );
        }
    }
}

comptime {
    rzig.registerModule(@This());
}

test {
    _ = lp;
    _ = poc;
}
