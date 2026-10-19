//! The response-type linear program for probabilities of causation.
//!
//! A unit has a factual treatment level x0 in 0..m-1 and a response type
//! r = (r_0, ..., r_{m-1}), where r_k in 0..n-1 is the outcome the unit would
//! show under treatment level k. Variable q(x0, r) is the probability of the
//! pair; the column index is x0 * n^m + sum_k r_k * n^k.

const std = @import("std");

/// Upper limit on tableau cells (128 MiB of doubles).
pub const max_cells: usize = 16_777_216;

pub const Shape = struct {
    m: usize,
    n: usize,
    types: usize,
    columns: usize,
    rows: usize,
};

/// Dimensions of the program for m treatment and n outcome levels, or null
/// when they overflow.
pub fn shape(m: usize, n: usize) ?Shape {
    var types: usize = 1;
    for (0..m) |_| types = std.math.mul(usize, types, n) catch return null;
    const columns = std.math.mul(usize, m, types) catch return null;
    const mn = std.math.mul(usize, m, n) catch return null;
    const rows = std.math.mul(usize, 2, mn) catch return null;
    return .{ .m = m, .n = n, .types = types, .columns = columns, .rows = rows };
}

/// Outcome of response type `code` under treatment level `k`.
pub fn response(s: Shape, code: usize, k: usize) usize {
    var rest = code;
    for (0..k) |_| rest /= s.n;
    return rest % s.n;
}

/// Fill the column-major constraint matrix: rows 0..mn-1 hold the
/// observational equations P(X = x0, Y = y0), rows mn..2mn-1 the experimental
/// equations P(Y_{x1} = y1).
pub fn constraints(s: Shape, a: []f64) void {
    @memset(a, 0.0);
    const mn = s.m * s.n;
    for (0..s.m) |factual| {
        for (0..s.types) |code| {
            const column = factual * s.types + code;
            const offset = column * s.rows;
            a[offset + factual * s.n + response(s, code, factual)] = 1.0;
            for (0..s.m) |level| {
                a[offset + mn + level * s.n + response(s, code, level)] = 1.0;
            }
        }
    }
}

/// Right-hand sides from the observational and experimental matrices, both
/// column-major m x n with treatment levels in rows.
pub fn rightHandSide(s: Shape, observed: []const f64, experimental: []const f64, b: []f64) void {
    const mn = s.m * s.n;
    for (0..s.m) |level| {
        for (0..s.n) |outcome| {
            b[level * s.n + outcome] = observed[level + outcome * s.m];
            b[mn + level * s.n + outcome] = experimental[level + outcome * s.m];
        }
    }
}

pub const Quantity = enum { pns, pn, ps };

/// Objective coefficients of the numerator of PNS, PN or PS for the query
/// "Y_x = y and Y_{x'} = y'" (zero-based levels).
pub fn objective(s: Shape, quantity: Quantity, x: usize, y: usize, x_prime: usize, y_prime: usize, c: []f64) void {
    for (0..s.m) |factual| {
        for (0..s.types) |code| {
            const in_event = response(s, code, x) == y and response(s, code, x_prime) == y_prime;
            const selected = switch (quantity) {
                .pns => in_event,
                .pn => in_event and factual == x,
                .ps => in_event and factual == x_prime,
            };
            c[factual * s.types + code] = if (selected) 1.0 else 0.0;
        }
    }
}

test "binary shape matches the eight parameters of Tian and Pearl" {
    const s = shape(2, 2).?;
    try std.testing.expectEqual(@as(usize, 8), s.columns);
    try std.testing.expectEqual(@as(usize, 8), s.rows);
}
