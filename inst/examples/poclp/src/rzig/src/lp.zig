//! Dense two-phase simplex method for small linear programs in equality form:
//! optimize c'q subject to A q = b and q >= 0.
//!
//! Every function works on caller-provided memory and allocates nothing, so the
//! same code runs on the calling thread and on worker threads. Pivoting follows
//! Bland's rule, which guarantees termination on degenerate problems.

const std = @import("std");

pub const pivot_tolerance: f64 = 1e-10;
pub const feasibility_tolerance: f64 = 1e-9;

pub const Status = enum(i32) {
    optimal = 0,
    infeasible = 1,
    unbounded = 2,
    iteration_limit = 3,
};

pub const Result = struct {
    status: Status,
    value: f64,
    iterations: usize,
};

/// Number of tableau cells for `rows` constraints and `columns` variables,
/// or null when the product overflows.
pub fn cellCount(rows: usize, columns: usize) ?usize {
    const width = std.math.add(usize, columns, rows) catch return null;
    const width_rhs = std.math.add(usize, width, 1) catch return null;
    const height = std.math.add(usize, rows, 1) catch return null;
    return std.math.mul(usize, height, width_rhs) catch null;
}

/// Memory for one tableau. `cells` holds (rows + 1) * (columns + rows + 1)
/// values, `basis` and `active` hold one entry per constraint row.
pub const Workspace = struct {
    rows: usize,
    columns: usize,
    cells: []f64,
    basis: []usize,
    active: []bool,

    fn width(self: *const Workspace) usize {
        return self.columns + self.rows + 1;
    }

    fn at(self: *Workspace, row: usize, column: usize) *f64 {
        return &self.cells[row * self.width() + column];
    }

    fn rhs(self: *Workspace, row: usize) *f64 {
        return self.at(row, self.width() - 1);
    }

    /// Copy a feasible tableau so several objectives can start from it.
    pub fn copyFrom(self: *Workspace, other: *const Workspace) void {
        @memcpy(self.cells, other.cells);
        @memcpy(self.basis, other.basis);
        @memcpy(self.active, other.active);
    }

    fn pivot(self: *Workspace, pivot_row: usize, pivot_column: usize) void {
        const w = self.width();
        const pivot_value = self.at(pivot_row, pivot_column).*;
        const row_start = pivot_row * w;
        for (self.cells[row_start .. row_start + w]) |*cell| cell.* /= pivot_value;
        for (0..self.rows + 1) |row| {
            if (row == pivot_row) continue;
            if (row < self.rows and !self.active[row]) continue;
            const factor = self.at(row, pivot_column).*;
            if (factor == 0.0) continue;
            const target_start = row * w;
            for (0..w) |column| {
                self.cells[target_start + column] -= factor * self.cells[row_start + column];
            }
        }
        self.basis[pivot_row] = pivot_column;
    }

    /// Run simplex iterations on the current objective row with Bland's rule.
    /// Only columns below `eligible` may enter the basis.
    fn iterate(self: *Workspace, eligible: usize, max_iterations: usize, iterations: *usize) Status {
        while (true) {
            var entering: ?usize = null;
            for (0..eligible) |column| {
                if (self.at(self.rows, column).* < -pivot_tolerance) {
                    entering = column;
                    break;
                }
            }
            const column = entering orelse return .optimal;

            var leaving: ?usize = null;
            var best_ratio: f64 = std.math.inf(f64);
            for (0..self.rows) |row| {
                if (!self.active[row]) continue;
                const coefficient = self.at(row, column).*;
                if (coefficient <= pivot_tolerance) continue;
                const ratio = self.rhs(row).* / coefficient;
                const better = ratio < best_ratio - 1e-12 or
                    (ratio <= best_ratio + 1e-12 and leaving != null and
                        self.basis[row] < self.basis[leaving.?]);
                if (leaving == null or better) {
                    leaving = row;
                    best_ratio = @min(best_ratio, ratio);
                }
            }
            const row = leaving orelse return .unbounded;

            if (iterations.* >= max_iterations) return .iteration_limit;
            iterations.* += 1;
            self.pivot(row, column);
        }
    }
};

/// Phase one: find a basic feasible solution of A q = b, q >= 0.
/// `a` is column-major with `ws.rows` rows and `ws.columns` columns.
/// On `.optimal`, `ws` holds a feasible tableau whose artificial columns never
/// re-enter; redundant constraint rows are marked inactive.
pub fn phaseOne(ws: *Workspace, a: []const f64, b: []const f64, max_iterations: usize, iterations: *usize) Status {
    const rows = ws.rows;
    const columns = ws.columns;
    const w = ws.width();
    @memset(ws.cells, 0.0);

    for (0..rows) |row| {
        const sign: f64 = if (b[row] < 0.0) -1.0 else 1.0;
        for (0..columns) |column| ws.at(row, column).* = sign * a[row + column * rows];
        ws.at(row, columns + row).* = 1.0;
        ws.rhs(row).* = sign * b[row];
        ws.basis[row] = columns + row;
        ws.active[row] = true;
    }
    for (0..columns) |column| {
        var total: f64 = 0.0;
        for (0..rows) |row| total += ws.at(row, column).*;
        ws.at(rows, column).* = -total;
    }
    var rhs_total: f64 = 0.0;
    for (0..rows) |row| rhs_total += ws.rhs(row).*;
    ws.cells[rows * w + w - 1] = -rhs_total;

    const status = ws.iterate(columns, max_iterations, iterations);
    if (status == .iteration_limit) return status;
    if (-ws.cells[rows * w + w - 1] > feasibility_tolerance) return .infeasible;

    for (0..rows) |row| {
        if (ws.basis[row] < columns) continue;
        var replacement: ?usize = null;
        for (0..columns) |column| {
            if (@abs(ws.at(row, column).*) > pivot_tolerance) {
                replacement = column;
                break;
            }
        }
        if (replacement) |column| {
            ws.pivot(row, column);
        } else {
            ws.active[row] = false;
        }
    }
    return .optimal;
}

/// Phase two: optimize `objective` from the feasible tableau left by phase one.
pub fn phaseTwo(ws: *Workspace, objective: []const f64, maximize: bool, max_iterations: usize) Result {
    const rows = ws.rows;
    const columns = ws.columns;
    const w = ws.width();
    const sign: f64 = if (maximize) -1.0 else 1.0;

    for (0..w) |column| ws.cells[rows * w + column] = 0.0;
    for (0..columns) |column| ws.at(rows, column).* = sign * objective[column];
    for (0..rows) |row| {
        if (!ws.active[row]) continue;
        const basic = ws.basis[row];
        if (basic >= columns) continue;
        const cost = sign * objective[basic];
        if (cost == 0.0) continue;
        for (0..w) |column| ws.cells[rows * w + column] -= cost * ws.at(row, column).*;
    }

    var iterations: usize = 0;
    const status = ws.iterate(columns, max_iterations, &iterations);
    const minimum = -ws.cells[rows * w + w - 1];
    return .{
        .status = status,
        .value = if (status == .optimal) sign * minimum else std.math.nan(f64),
        .iterations = iterations,
    };
}

/// Write the primal solution of the current tableau into `solution`.
pub fn primal(ws: *Workspace, solution: []f64) void {
    @memset(solution, 0.0);
    for (0..ws.rows) |row| {
        if (!ws.active[row]) continue;
        const basic = ws.basis[row];
        if (basic < ws.columns) solution[basic] = ws.rhs(row).*;
    }
}

test "a two-variable program reaches its optimum" {
    // maximize q1 + 2 q2 subject to q1 + q2 + s = 4, q2 + t = 3
    const a = [_]f64{ 1, 0, 1, 1, 1, 0, 0, 1 };
    const b = [_]f64{ 4, 3 };
    var cells: [3 * 7]f64 = undefined;
    var basis: [2]usize = undefined;
    var active: [2]bool = undefined;
    var ws = Workspace{ .rows = 2, .columns = 4, .cells = &cells, .basis = &basis, .active = &active };
    var iterations: usize = 0;
    try std.testing.expectEqual(Status.optimal, phaseOne(&ws, &a, &b, 100, &iterations));
    const result = phaseTwo(&ws, &[_]f64{ 1, 2, 0, 0 }, true, 100);
    try std.testing.expectEqual(Status.optimal, result.status);
    try std.testing.expectApproxEqAbs(@as(f64, 7), result.value, 1e-12);
}
