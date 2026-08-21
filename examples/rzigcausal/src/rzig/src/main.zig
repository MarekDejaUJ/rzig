const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

/// Route ReleaseSafe failures through R while retaining Zig test behavior.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

const max_variables = 64;
const max_conditioning_depth = 5;
const singular_tolerance = 1.0e-12;

const CorrelationWork = struct {
    standardized: []const f64,
    output: []f64,
    nrow: usize,
    ncol: usize,

    fn run(work: *@This(), index: usize) void {
        const row_variable = index % work.ncol;
        const column_variable = index / work.ncol;
        if (row_variable == column_variable) {
            work.output[index] = 1.0;
            return;
        }

        var correlation: f64 = 0.0;
        for (0..work.nrow) |row| {
            correlation += work.standardized[row + row_variable * work.nrow] *
                work.standardized[row + column_variable * work.nrow];
        }
        work.output[index] = @max(-1.0, @min(1.0, correlation));
    }
};

const CombinationSearch = struct {
    correlation: []const f64,
    candidates: []const usize,
    selected: []usize,
    workspace: []f64,
    variable_count: usize,
    left: usize,
    right: usize,
    depth: usize,
    sample_count: usize,
    critical_z: f64,
    tests: *usize,

    fn findsSeparation(self: *@This(), start: usize, selected_count: usize) rzig.Error!bool {
        if (selected_count == self.depth) {
            self.tests.* +|= 1;
            if (self.tests.* % 256 == 0) try rzig.checkInterrupt();

            const partial = partialCorrelation(
                self.correlation,
                self.variable_count,
                self.left,
                self.right,
                self.selected[0..self.depth],
                self.workspace,
            ) orelse return false;
            const magnitude = @min(@abs(partial), 1.0 - 1.0e-12);
            const degrees = self.sample_count - self.depth - 3;
            const fisher_z = 0.5 * @log((1.0 + magnitude) / (1.0 - magnitude)) *
                @sqrt(@as(f64, @floatFromInt(degrees)));
            return fisher_z <= self.critical_z;
        }

        const needed = self.depth - selected_count;
        var candidate_index = start;
        while (candidate_index + needed <= self.candidates.len) : (candidate_index += 1) {
            self.selected[selected_count] = self.candidates[candidate_index];
            if (try self.findsSeparation(candidate_index + 1, selected_count + 1)) return true;
        }
        return false;
    }
};

/// Compute a Pearson correlation matrix using pure Zig worker threads.
/// @param data A double matrix with observations in rows and variables in columns.
/// @return A symmetric variable-by-variable correlation matrix.
/// @export
pub fn correlation_matrix(
    ctx: *rzig.Ctx,
    data: rzig.Matrix,
) rzig.Error!rzig.Attributed([]const f64) {
    const correlation = try computeCorrelation(ctx, data);
    const dimensions = [_]i32{ @intCast(data.ncol), @intCast(data.ncol) };
    var result = rzig.Attributed([]const f64).init(ctx, correlation);
    try result.setDim(&dimensions);
    return result;
}

/// Estimate an undirected Gaussian PC-stable skeleton.
/// @param data A double matrix with observations in rows and variables in columns.
/// @param alpha The two-sided Gaussian conditional-independence level.
/// @param max_depth The maximum conditioning-set size, from zero through five.
/// @return A symmetric logical adjacency matrix with a false diagonal.
/// @export
pub fn pc_skeleton(
    ctx: *rzig.Ctx,
    data: rzig.Matrix,
    alpha: f64,
    max_depth: usize,
) rzig.Error!rzig.Attributed([]const bool) {
    if (!std.math.isFinite(alpha) or alpha <= 0.0 or alpha >= 1.0) {
        return rzig.raise("alpha must be finite and strictly between zero and one", .{});
    }
    if (max_depth > max_conditioning_depth) {
        return rzig.raise(
            "max_depth exceeds this demonstration's limit of {d}; got {d}",
            .{ max_conditioning_depth, max_depth },
        );
    }
    if (data.nrow <= max_depth + 3) {
        return rzig.raise(
            "data needs more than max_depth + 3 rows; got {d} rows and depth {d}",
            .{ data.nrow, max_depth },
        );
    }

    const probability = 1.0 - alpha / 2.0;
    if (probability >= 1.0) {
        return rzig.raise("alpha is too small for double-precision Gaussian testing", .{});
    }
    const critical_z = normalQuantile(probability);
    if (!std.math.isFinite(critical_z)) {
        return rzig.raise("could not derive a finite Gaussian critical value from alpha", .{});
    }

    const correlation = try computeCorrelation(ctx, data);
    const variable_count = data.ncol;
    const matrix_size = try checkedSquare(variable_count);
    const adjacency = try ctx.alloc(u8, matrix_size);
    @memset(adjacency, 1);
    for (0..variable_count) |variable| adjacency[matrixIndex(variable_count, variable, variable)] = 0;

    const snapshot = try ctx.alloc(u8, matrix_size);
    const candidates = try ctx.alloc(usize, variable_count);
    const selected = try ctx.alloc(usize, max_depth);
    const precision_size = try checkedSquare(max_depth + 2);
    const workspace_length = std.math.mul(usize, precision_size, 2) catch
        return rzig.raise("conditioning workspace exceeds the native size limit", .{});
    const workspace = try ctx.alloc(f64, workspace_length);
    var tests: usize = 0;

    var depth: usize = 0;
    while (depth <= max_depth) : (depth += 1) {
        @memcpy(snapshot, adjacency);
        var eligible = false;

        for (0..variable_count) |left| {
            if (left % 8 == 0) try rzig.checkInterrupt();
            for (left + 1..variable_count) |right| {
                if (snapshot[matrixIndex(variable_count, left, right)] == 0) continue;

                const left_candidates = collectNeighbors(
                    snapshot,
                    variable_count,
                    left,
                    right,
                    candidates,
                );
                if (left_candidates.len >= depth) {
                    eligible = true;
                    var search = CombinationSearch{
                        .correlation = correlation,
                        .candidates = left_candidates,
                        .selected = selected,
                        .workspace = workspace,
                        .variable_count = variable_count,
                        .left = left,
                        .right = right,
                        .depth = depth,
                        .sample_count = data.nrow,
                        .critical_z = critical_z,
                        .tests = &tests,
                    };
                    if (try search.findsSeparation(0, 0)) {
                        removeEdge(adjacency, variable_count, left, right);
                        continue;
                    }
                }

                if (depth == 0) continue;
                const right_candidates = collectNeighbors(
                    snapshot,
                    variable_count,
                    right,
                    left,
                    candidates,
                );
                if (right_candidates.len >= depth) {
                    eligible = true;
                    var search = CombinationSearch{
                        .correlation = correlation,
                        .candidates = right_candidates,
                        .selected = selected,
                        .workspace = workspace,
                        .variable_count = variable_count,
                        .left = left,
                        .right = right,
                        .depth = depth,
                        .sample_count = data.nrow,
                        .critical_z = critical_z,
                        .tests = &tests,
                    };
                    if (try search.findsSeparation(0, 0)) {
                        removeEdge(adjacency, variable_count, left, right);
                    }
                }
            }
        }

        if (!eligible) break;
    }

    const result_values = try ctx.alloc(bool, matrix_size);
    for (adjacency, result_values) |edge, *value| value.* = edge != 0;
    const dimensions = [_]i32{ @intCast(variable_count), @intCast(variable_count) };
    var result = rzig.Attributed([]const bool).init(ctx, result_values);
    try result.setDim(&dimensions);
    return result;
}

fn computeCorrelation(ctx: *rzig.Ctx, data: rzig.Matrix) rzig.Error![]f64 {
    try validateDimensions(data);
    const standardized = try ctx.alloc(f64, data.data.len);

    for (0..data.ncol) |column| {
        var mean: f64 = 0.0;
        var sum_squares: f64 = 0.0;
        var count: f64 = 0.0;
        for (0..data.nrow) |row| {
            const value = data.data[row + column * data.nrow];
            if (!std.math.isFinite(value)) {
                return rzig.raise(
                    "data must contain only finite values; column {d}, row {d} is non-finite",
                    .{ column + 1, row + 1 },
                );
            }
            count += 1.0;
            const delta = value - mean;
            mean += delta / count;
            sum_squares += delta * (value - mean);
            if (!std.math.isFinite(mean) or !std.math.isFinite(sum_squares)) {
                return rzig.raise(
                    "column {d} has non-finite moments; rescale the data",
                    .{column + 1},
                );
            }
        }
        if (sum_squares <= 0.0) {
            return rzig.raise("column {d} is constant", .{column + 1});
        }

        const norm = @sqrt(sum_squares);
        for (0..data.nrow) |row| {
            standardized[row + column * data.nrow] =
                (data.data[row + column * data.nrow] - mean) / norm;
        }
    }

    const matrix_size = try checkedSquare(data.ncol);
    const correlation = try ctx.alloc(f64, matrix_size);
    var work = CorrelationWork{
        .standardized = standardized,
        .output = correlation,
        .nrow = data.nrow,
        .ncol = data.ncol,
    };
    try rzig.parallelFor(ctx, matrix_size, &work, CorrelationWork.run);
    return correlation;
}

fn validateDimensions(data: rzig.Matrix) rzig.Error!void {
    if (data.nrow < 4) {
        return rzig.raise("data must have at least four observation rows; got {d}", .{data.nrow});
    }
    if (data.ncol < 2) {
        return rzig.raise("data must have at least two variable columns; got {d}", .{data.ncol});
    }
    if (data.ncol > max_variables) {
        return rzig.raise(
            "this demonstration supports at most {d} variables; got {d}",
            .{ max_variables, data.ncol },
        );
    }
}

fn checkedSquare(value: usize) rzig.Error!usize {
    return std.math.mul(usize, value, value) catch
        rzig.raise("matrix dimensions exceed the native size limit", .{});
}

fn matrixIndex(size: usize, row: usize, column: usize) usize {
    return row + column * size;
}

fn collectNeighbors(
    adjacency: []const u8,
    variable_count: usize,
    source: usize,
    excluded: usize,
    buffer: []usize,
) []const usize {
    var count: usize = 0;
    for (0..variable_count) |candidate| {
        if (candidate == excluded or candidate == source) continue;
        if (adjacency[matrixIndex(variable_count, source, candidate)] == 0) continue;
        buffer[count] = candidate;
        count += 1;
    }
    return buffer[0..count];
}

fn removeEdge(adjacency: []u8, variable_count: usize, left: usize, right: usize) void {
    adjacency[matrixIndex(variable_count, left, right)] = 0;
    adjacency[matrixIndex(variable_count, right, left)] = 0;
}

fn partialCorrelation(
    correlation: []const f64,
    variable_count: usize,
    left: usize,
    right: usize,
    conditioning: []const usize,
    workspace: []f64,
) ?f64 {
    const order = conditioning.len + 2;
    const width = order * 2;
    const required = order * width;
    const augmented = workspace[0..required];

    for (0..order) |row| {
        const row_variable = selectedVariable(left, right, conditioning, row);
        for (0..order) |column| {
            const column_variable = selectedVariable(left, right, conditioning, column);
            augmented[row * width + column] =
                correlation[matrixIndex(variable_count, row_variable, column_variable)];
            augmented[row * width + order + column] = if (row == column) 1.0 else 0.0;
        }
    }

    for (0..order) |pivot_column| {
        var pivot_row = pivot_column;
        var pivot_size = @abs(augmented[pivot_row * width + pivot_column]);
        for (pivot_column + 1..order) |candidate_row| {
            const candidate_size = @abs(augmented[candidate_row * width + pivot_column]);
            if (candidate_size > pivot_size) {
                pivot_row = candidate_row;
                pivot_size = candidate_size;
            }
        }
        if (!std.math.isFinite(pivot_size) or pivot_size <= singular_tolerance) return null;

        if (pivot_row != pivot_column) {
            for (0..width) |column| {
                const left_index = pivot_column * width + column;
                const right_index = pivot_row * width + column;
                const temporary = augmented[left_index];
                augmented[left_index] = augmented[right_index];
                augmented[right_index] = temporary;
            }
        }

        const pivot = augmented[pivot_column * width + pivot_column];
        for (0..width) |column| augmented[pivot_column * width + column] /= pivot;
        for (0..order) |row| {
            if (row == pivot_column) continue;
            const factor = augmented[row * width + pivot_column];
            for (0..width) |column| {
                augmented[row * width + column] -=
                    factor * augmented[pivot_column * width + column];
            }
        }
    }

    const precision_left = augmented[order];
    const precision_right = augmented[width + order + 1];
    const precision_cross = augmented[order + 1];
    const denominator = @sqrt(precision_left * precision_right);
    if (!std.math.isFinite(denominator) or denominator <= 0.0) return null;
    const result = -precision_cross / denominator;
    if (!std.math.isFinite(result)) return null;
    return @max(-1.0, @min(1.0, result));
}

fn selectedVariable(
    left: usize,
    right: usize,
    conditioning: []const usize,
    position: usize,
) usize {
    return switch (position) {
        0 => left,
        1 => right,
        else => conditioning[position - 2],
    };
}

fn normalQuantile(probability: f64) f64 {
    const a1 = -3.969_683_028_665_376e1;
    const a2 = 2.209_460_984_245_205e2;
    const a3 = -2.759_285_104_469_687e2;
    const a4 = 1.383_577_518_672_690e2;
    const a5 = -3.066_479_806_614_716e1;
    const a6 = 2.506_628_277_459_239;
    const b1 = -5.447_609_879_822_406e1;
    const b2 = 1.615_858_368_580_409e2;
    const b3 = -1.556_989_798_598_866e2;
    const b4 = 6.680_131_188_771_972e1;
    const b5 = -1.328_068_155_288_572e1;
    const c1 = -7.784_894_002_430_293e-3;
    const c2 = -3.223_964_580_411_365e-1;
    const c3 = -2.400_758_277_161_838;
    const c4 = -2.549_732_539_343_734;
    const c5 = 4.374_664_141_464_968;
    const c6 = 2.938_163_982_698_783;
    const d1 = 7.784_695_709_041_462e-3;
    const d2 = 3.224_671_290_700_398e-1;
    const d3 = 2.445_134_137_142_996;
    const d4 = 3.754_408_661_907_416;
    const lower = 0.024_25;
    const upper = 1.0 - lower;

    if (probability < lower) {
        const q = @sqrt(-2.0 * @log(probability));
        return (((((c1 * q + c2) * q + c3) * q + c4) * q + c5) * q + c6) /
            ((((d1 * q + d2) * q + d3) * q + d4) * q + 1.0);
    }
    if (probability <= upper) {
        const q = probability - 0.5;
        const r = q * q;
        return (((((a1 * r + a2) * r + a3) * r + a4) * r + a5) * r + a6) * q /
            (((((b1 * r + b2) * r + b3) * r + b4) * r + b5) * r + 1.0);
    }

    const q = @sqrt(-2.0 * @log(1.0 - probability));
    return -(((((c1 * q + c2) * q + c3) * q + c4) * q + c5) * q + c6) /
        ((((d1 * q + d2) * q + d3) * q + d4) * q + 1.0);
}

comptime {
    rzig.registerModule(@This());
}
