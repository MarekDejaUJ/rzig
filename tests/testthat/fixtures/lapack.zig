const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

fn result(ctx: *rzig.Ctx, m: rzig.MutableMatrix) rzig.Error!rzig.Attributed([]f64) {
    var out = rzig.Attributed([]f64).init(ctx, m.data);
    try out.setMatrix(m.nrow, m.ncol);
    return out;
}

fn copy(ctx: *rzig.Ctx, a: rzig.Matrix) rzig.Error!rzig.MutableMatrix {
    const m = try ctx.matrix(a.nrow, a.ncol);
    @memcpy(m.data, a.data);
    return m;
}

/// @export
pub fn la_gemm(ctx: *rzig.Ctx, a: rzig.Matrix, b: rzig.Matrix, transpose_a: bool) rzig.Error!rzig.Attributed([]f64) {
    const rows = if (transpose_a) a.ncol else a.nrow;
    const out = try ctx.matrix(rows, b.ncol);
    try rzig.Blas.gemm(ctx, if (transpose_a) .yes else .no, .no, 1, a, b, 0, out);
    return result(ctx, out);
}

/// @export
pub fn la_gemv(ctx: *rzig.Ctx, a: rzig.Matrix, x: []const f64) rzig.Error![]f64 {
    const y = try ctx.alloc(f64, a.nrow);
    try rzig.Blas.gemv(ctx, .no, 1, a, x, 0, y);
    return y;
}

/// @export
pub fn la_crossprod(ctx: *rzig.Ctx, a: rzig.Matrix) rzig.Error!rzig.Attributed([]f64) {
    const out = try ctx.matrix(a.ncol, a.ncol);
    try rzig.Blas.syrk(ctx, .lower, .yes, 1, a, 0, out);
    for (0..out.ncol) |j| {
        for (0..j) |i| out.set(i, j, out.at(j, i));
    }
    return result(ctx, out);
}

/// @export
pub fn la_backsolve(ctx: *rzig.Ctx, r: rzig.Matrix, b: rzig.Matrix) rzig.Error!rzig.Attributed([]f64) {
    const x = try copy(ctx, b);
    try rzig.Blas.trsm(ctx, .left, .upper, .no, .non_unit, 1, r, x);
    return result(ctx, x);
}

/// @export
pub fn la_chol(ctx: *rzig.Ctx, a: rzig.Matrix) rzig.Error!rzig.Attributed([]f64) {
    const factor = try copy(ctx, a);
    try rzig.Lapack.potrf(ctx, .upper, factor);
    for (0..factor.ncol) |j| {
        for (j + 1..factor.nrow) |i| factor.set(i, j, 0);
    }
    return result(ctx, factor);
}

/// @export
pub fn la_chol_solve(ctx: *rzig.Ctx, a: rzig.Matrix, b: rzig.Matrix) rzig.Error!rzig.Attributed([]f64) {
    const factor = try copy(ctx, a);
    try rzig.Lapack.potrf(ctx, .lower, factor);
    const x = try copy(ctx, b);
    try rzig.Lapack.potrs(ctx, .lower, factor.view(), x);
    return result(ctx, x);
}

/// @export
pub fn la_solve(ctx: *rzig.Ctx, a: rzig.Matrix, b: rzig.Matrix) rzig.Error!rzig.Attributed([]f64) {
    const factors = try copy(ctx, a);
    const x = try copy(ctx, b);
    try rzig.Lapack.gesv(ctx, factors, x);
    return result(ctx, x);
}

/// @export
pub fn la_qr_r(ctx: *rzig.Ctx, a: rzig.Matrix) rzig.Error!rzig.Attributed([]f64) {
    const factors = try copy(ctx, a);
    const tau = try ctx.alloc(f64, @min(a.nrow, a.ncol));
    try rzig.Lapack.geqrf(ctx, factors, tau);
    const r = try ctx.matrix(a.ncol, a.ncol);
    for (0..a.ncol) |j| {
        for (0..@min(j + 1, a.nrow)) |i| r.set(i, j, factors.at(i, j));
    }
    return result(ctx, r);
}

/// The first column of Q of a QR factorization, through ormqr.
/// @export
pub fn la_qr_q1(ctx: *rzig.Ctx, a: rzig.Matrix) rzig.Error![]f64 {
    const factors = try copy(ctx, a);
    const tau = try ctx.alloc(f64, @min(a.nrow, a.ncol));
    try rzig.Lapack.geqrf(ctx, factors, tau);
    const e1 = try ctx.matrix(a.nrow, 1);
    e1.set(0, 0, 1);
    try rzig.Lapack.ormqr(ctx, .left, .no, factors.view(), tau, e1);
    return e1.data;
}

/// @export
pub fn la_lstsq(ctx: *rzig.Ctx, a: rzig.Matrix, y: []const f64) rzig.Error![]f64 {
    const factors = try copy(ctx, a);
    const b = try ctx.matrix(@max(a.nrow, a.ncol), 1);
    @memcpy(b.data[0..y.len], y);
    try rzig.Lapack.gels(ctx, .no, factors, b);
    return b.data[0..a.ncol];
}

/// @export
pub fn la_eigen(ctx: *rzig.Ctx, a: rzig.Matrix) rzig.Error![]f64 {
    const work = try copy(ctx, a);
    const values = try ctx.alloc(f64, a.nrow);
    const vectors = try ctx.matrix(a.nrow, a.nrow);
    try rzig.Lapack.syevr(ctx, .lower, work, values, vectors);
    return values;
}

/// @export
pub fn la_svd(ctx: *rzig.Ctx, a: rzig.Matrix) rzig.Error![]f64 {
    const work = try copy(ctx, a);
    const k = @min(a.nrow, a.ncol);
    const s = try ctx.alloc(f64, k);
    const u = try ctx.matrix(a.nrow, k);
    const vt = try ctx.matrix(k, a.ncol);
    try rzig.Lapack.gesdd(ctx, work, s, u, vt);
    return s;
}

comptime {
    rzig.registerModule(@This());
}
