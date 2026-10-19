//! BLAS and LAPACK through the libraries R links (`$(BLAS_LIBS)`,
//! `$(LAPACK_LIBS)`). A package that uses them opts in with
//! `rzig::use_rzig_lapack()`, which links the libraries and `$(FLIBS)`.
//!
//! Every routine checks the shapes of its operands before the call, because
//! BLAS and LAPACK report invalid arguments through `xerbla`, which R
//! implements as an R error. The call itself runs inside R_ToplevelExec as a
//! second guard. LAPACK's `info` values become recorded R errors. Matrices
//! are column-major with the number of rows as leading dimension.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const matrix = @import("matrix.zig");
const Ctx = @import("alloc.zig").Ctx;

const Matrix = matrix.Matrix;
const MutMatrix = matrix.MutableMatrixOf(f64);

/// `op(A)` is `A` or its transpose.
pub const Transpose = enum { no, yes };
/// The triangle of a symmetric or triangular matrix that is used.
pub const Triangle = enum { upper, lower };
/// The side on which a matrix multiplies.
pub const Side = enum { left, right };
/// Whether a triangular matrix has a unit diagonal.
pub const Diagonal = enum { non_unit, unit };

fn letter(value: anytype) u8 {
    return switch (@TypeOf(value)) {
        Transpose => if (value == .no) 'N' else 'T',
        Triangle => if (value == .upper) 'U' else 'L',
        Side => if (value == .left) 'L' else 'R',
        Diagonal => if (value == .non_unit) 'N' else 'U',
        else => @compileError("not a LAPACK option"),
    };
}

extern fn dgemm_(ta: *const u8, tb: *const u8, m: *const c_int, n: *const c_int, k: *const c_int, alpha: *const f64, a: [*]const f64, lda: *const c_int, b: [*]const f64, ldb: *const c_int, beta: *const f64, cm: [*]f64, ldc: *const c_int, ta_len: usize, tb_len: usize) void;
extern fn dgemv_(t: *const u8, m: *const c_int, n: *const c_int, alpha: *const f64, a: [*]const f64, lda: *const c_int, x: [*]const f64, incx: *const c_int, beta: *const f64, y: [*]f64, incy: *const c_int, t_len: usize) void;
extern fn dsyrk_(uplo: *const u8, t: *const u8, n: *const c_int, k: *const c_int, alpha: *const f64, a: [*]const f64, lda: *const c_int, beta: *const f64, cm: [*]f64, ldc: *const c_int, uplo_len: usize, t_len: usize) void;
extern fn dtrsm_(side: *const u8, uplo: *const u8, t: *const u8, diag: *const u8, m: *const c_int, n: *const c_int, alpha: *const f64, a: [*]const f64, lda: *const c_int, b: [*]f64, ldb: *const c_int, side_len: usize, uplo_len: usize, t_len: usize, diag_len: usize) void;
extern fn dpotrf_(uplo: *const u8, n: *const c_int, a: [*]f64, lda: *const c_int, info: *c_int, uplo_len: usize) void;
extern fn dpotrs_(uplo: *const u8, n: *const c_int, nrhs: *const c_int, a: [*]const f64, lda: *const c_int, b: [*]f64, ldb: *const c_int, info: *c_int, uplo_len: usize) void;
extern fn dgetrf_(m: *const c_int, n: *const c_int, a: [*]f64, lda: *const c_int, ipiv: [*]c_int, info: *c_int) void;
extern fn dgetrs_(t: *const u8, n: *const c_int, nrhs: *const c_int, a: [*]const f64, lda: *const c_int, ipiv: [*]const c_int, b: [*]f64, ldb: *const c_int, info: *c_int, t_len: usize) void;
extern fn dgeqrf_(m: *const c_int, n: *const c_int, a: [*]f64, lda: *const c_int, tau: [*]f64, work: [*]f64, lwork: *const c_int, info: *c_int) void;
extern fn dormqr_(side: *const u8, t: *const u8, m: *const c_int, n: *const c_int, k: *const c_int, a: [*]const f64, lda: *const c_int, tau: [*]const f64, cm: [*]f64, ldc: *const c_int, work: [*]f64, lwork: *const c_int, info: *c_int, side_len: usize, t_len: usize) void;
extern fn dgels_(t: *const u8, m: *const c_int, n: *const c_int, nrhs: *const c_int, a: [*]f64, lda: *const c_int, b: [*]f64, ldb: *const c_int, work: [*]f64, lwork: *const c_int, info: *c_int, t_len: usize) void;
extern fn dsyevr_(jobz: *const u8, range: *const u8, uplo: *const u8, n: *const c_int, a: [*]f64, lda: *const c_int, vl: *const f64, vu: *const f64, il: *const c_int, iu: *const c_int, abstol: *const f64, m: *c_int, w: [*]f64, z: [*]f64, ldz: *const c_int, isuppz: [*]c_int, work: [*]f64, lwork: *const c_int, iwork: [*]c_int, liwork: *const c_int, info: *c_int, jobz_len: usize, range_len: usize, uplo_len: usize) void;
extern fn dgesdd_(jobz: *const u8, m: *const c_int, n: *const c_int, a: [*]f64, lda: *const c_int, s: [*]f64, u: [*]f64, ldu: *const c_int, vt: [*]f64, ldvt: *const c_int, work: [*]f64, lwork: *const c_int, iwork: [*]c_int, info: *c_int, jobz_len: usize) void;

fn dimension(value: usize, comptime what: []const u8) es.Error!c_int {
    if (value > std.math.maxInt(c_int)) return es.raise("rzig: " ++ what ++ " {d} exceeds the BLAS limit of 2147483647", .{value});
    return @intCast(value);
}

fn leading(rows: usize) es.Error!c_int {
    return dimension(@max(rows, 1), "a leading dimension");
}

fn shape(comptime what: []const u8, rows: usize, columns: usize, want_rows: usize, want_columns: usize) es.Error!void {
    if (rows != want_rows or columns != want_columns) {
        return es.raise("rzig: " ++ what ++ " is {d} x {d}; it must be {d} x {d}", .{ rows, columns, want_rows, want_columns });
    }
}

fn length(comptime what: []const u8, have: usize, want: usize) es.Error!void {
    if (have != want) return es.raise("rzig: " ++ what ++ " has {d} values; it must have {d}", .{ have, want });
}

/// Call a BLAS or LAPACK routine inside R_ToplevelExec.
fn guarded(comptime function: anytype, args: anytype) es.Error!void {
    const State = struct {
        args: @TypeOf(args),

        fn run(data: ?*anyopaque) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            @call(.auto, function, self.args);
        }
    };
    var state = State{ .args = args };
    if (c.R_ToplevelExec(State.run, &state) == c.FALSE) {
        return es.raise("rzig: BLAS or LAPACK rejected an argument (an R error from xerbla)", .{});
    }
}

/// The optimal workspace of a LAPACK routine, from a query with lwork = -1.
fn workspace(ctx: *Ctx, query: f64) es.Error![]f64 {
    const count: usize = @intFromFloat(@max(1, @ceil(query)));
    return ctx.alloc(f64, count);
}

fn operandShape(trans: Transpose, a: Matrix) [2]usize {
    return if (trans == .no) .{ a.nrow, a.ncol } else .{ a.ncol, a.nrow };
}

/// Basic linear algebra.
pub const Blas = struct {
    /// `c = alpha * op(a) * op(b) + beta * c`.
    pub fn gemm(ctx: *Ctx, trans_a: Transpose, trans_b: Transpose, alpha: f64, a: Matrix, b: Matrix, beta: f64, out: MutMatrix) es.Error!void {
        _ = ctx;
        const op_a = operandShape(trans_a, a);
        const op_b = operandShape(trans_b, b);
        if (op_a[1] != op_b[0]) {
            return es.raise("rzig: gemm: op(a) is {d} x {d} and op(b) is {d} x {d}; their inner dimensions differ", .{ op_a[0], op_a[1], op_b[0], op_b[1] });
        }
        try shape("gemm: c", out.nrow, out.ncol, op_a[0], op_b[1]);
        const m = try dimension(op_a[0], "a dimension");
        const n = try dimension(op_b[1], "a dimension");
        const k = try dimension(op_a[1], "a dimension");
        const ta = letter(trans_a);
        const tb = letter(trans_b);
        try guarded(dgemm_, .{ &ta, &tb, &m, &n, &k, &alpha, a.data.ptr, &(try leading(a.nrow)), b.data.ptr, &(try leading(b.nrow)), &beta, out.data.ptr, &(try leading(out.nrow)), 1, 1 });
    }

    /// `y = alpha * op(a) * x + beta * y`.
    pub fn gemv(ctx: *Ctx, trans: Transpose, alpha: f64, a: Matrix, x: []const f64, beta: f64, y: []f64) es.Error!void {
        _ = ctx;
        const op = operandShape(trans, a);
        try length("gemv: x", x.len, op[1]);
        try length("gemv: y", y.len, op[0]);
        const m = try dimension(a.nrow, "a dimension");
        const n = try dimension(a.ncol, "a dimension");
        const t = letter(trans);
        const one: c_int = 1;
        try guarded(dgemv_, .{ &t, &m, &n, &alpha, a.data.ptr, &(try leading(a.nrow)), x.ptr, &one, &beta, y.ptr, &one, 1 });
    }

    /// `c = alpha * a * a^T + beta * c` (or `a^T * a` with `trans = .yes`),
    /// updating the `triangle` of the symmetric `c`.
    pub fn syrk(ctx: *Ctx, triangle: Triangle, trans: Transpose, alpha: f64, a: Matrix, beta: f64, out: MutMatrix) es.Error!void {
        _ = ctx;
        const op = operandShape(trans, a);
        try shape("syrk: c", out.nrow, out.ncol, op[0], op[0]);
        const n = try dimension(op[0], "a dimension");
        const k = try dimension(op[1], "a dimension");
        const u = letter(triangle);
        const t = letter(trans);
        try guarded(dsyrk_, .{ &u, &t, &n, &k, &alpha, a.data.ptr, &(try leading(a.nrow)), &beta, out.data.ptr, &(try leading(out.nrow)), 1, 1 });
    }

    /// Solve `op(a) * x = alpha * b` (`side = .left`) or `x * op(a) = alpha * b`
    /// for the triangular `a`; `b` is overwritten by `x`.
    pub fn trsm(ctx: *Ctx, side: Side, triangle: Triangle, trans: Transpose, diagonal: Diagonal, alpha: f64, a: Matrix, b: MutMatrix) es.Error!void {
        _ = ctx;
        const order = if (side == .left) b.nrow else b.ncol;
        try shape("trsm: a", a.nrow, a.ncol, order, order);
        const m = try dimension(b.nrow, "a dimension");
        const n = try dimension(b.ncol, "a dimension");
        const s = letter(side);
        const u = letter(triangle);
        const t = letter(trans);
        const d = letter(diagonal);
        try guarded(dtrsm_, .{ &s, &u, &t, &d, &m, &n, &alpha, a.data.ptr, &(try leading(a.nrow)), b.data.ptr, &(try leading(b.nrow)), 1, 1, 1, 1 });
    }
};

/// Linear algebra routines of LAPACK.
pub const Lapack = struct {
    /// Cholesky factorization of the symmetric positive definite `a`; the
    /// `triangle` of `a` is overwritten by the factor.
    pub fn potrf(ctx: *Ctx, triangle: Triangle, a: MutMatrix) es.Error!void {
        _ = ctx;
        try shape("potrf: a", a.nrow, a.ncol, a.nrow, a.nrow);
        const n = try dimension(a.nrow, "a dimension");
        const u = letter(triangle);
        var info: c_int = 0;
        try guarded(dpotrf_, .{ &u, &n, a.data.ptr, &(try leading(a.nrow)), &info, 1 });
        if (info > 0) return es.raise("rzig: potrf: the matrix is not positive definite (leading minor {d})", .{info});
    }

    /// Solve `a * x = b` with the Cholesky factor from `potrf`; `b` is
    /// overwritten by `x`.
    pub fn potrs(ctx: *Ctx, triangle: Triangle, factor: Matrix, b: MutMatrix) es.Error!void {
        _ = ctx;
        try shape("potrs: factor", factor.nrow, factor.ncol, b.nrow, b.nrow);
        const n = try dimension(b.nrow, "a dimension");
        const nrhs = try dimension(b.ncol, "a dimension");
        const u = letter(triangle);
        var info: c_int = 0;
        try guarded(dpotrs_, .{ &u, &n, &nrhs, factor.data.ptr, &(try leading(factor.nrow)), b.data.ptr, &(try leading(b.nrow)), &info, 1 });
    }

    /// LU factorization with partial pivoting of `a`, overwritten by the
    /// factors; `pivots` (length `min(nrow, ncol)`) receives the 1-based row
    /// interchanges.
    pub fn getrf(ctx: *Ctx, a: MutMatrix, pivots: []i32) es.Error!void {
        _ = ctx;
        try length("getrf: pivots", pivots.len, @min(a.nrow, a.ncol));
        const m = try dimension(a.nrow, "a dimension");
        const n = try dimension(a.ncol, "a dimension");
        var info: c_int = 0;
        try guarded(dgetrf_, .{ &m, &n, a.data.ptr, &(try leading(a.nrow)), @as([*]c_int, @ptrCast(pivots.ptr)), &info });
        if (info > 0) return es.raise("rzig: getrf: the matrix is exactly singular (U[{d},{d}] is zero)", .{ info, info });
    }

    /// Solve `op(a) * x = b` with the LU factors from `getrf`; `b` is
    /// overwritten by `x`.
    pub fn getrs(ctx: *Ctx, trans: Transpose, factors: Matrix, pivots: []const i32, b: MutMatrix) es.Error!void {
        _ = ctx;
        try shape("getrs: factors", factors.nrow, factors.ncol, b.nrow, b.nrow);
        try length("getrs: pivots", pivots.len, b.nrow);
        for (pivots) |pivot| {
            if (pivot < 1 or pivot > b.nrow) return es.raise("rzig: getrs: pivot {d} is outside 1 to {d}", .{ pivot, b.nrow });
        }
        const n = try dimension(b.nrow, "a dimension");
        const nrhs = try dimension(b.ncol, "a dimension");
        const t = letter(trans);
        var info: c_int = 0;
        try guarded(dgetrs_, .{ &t, &n, &nrhs, factors.data.ptr, &(try leading(factors.nrow)), @as([*]const c_int, @ptrCast(pivots.ptr)), b.data.ptr, &(try leading(b.nrow)), &info, 1 });
    }

    /// Solve `a * x = b` for square `a` (LU with partial pivoting); `a` is
    /// overwritten by its factors and `b` by `x`.
    pub fn gesv(ctx: *Ctx, a: MutMatrix, b: MutMatrix) es.Error!void {
        try shape("gesv: a", a.nrow, a.ncol, b.nrow, b.nrow);
        const pivots = try ctx.alloc(i32, a.nrow);
        try getrf(ctx, a, pivots);
        try getrs(ctx, .no, a.view(), pivots, b);
    }

    /// QR factorization of `a`: `r` above the diagonal, Householder vectors
    /// below; `tau` (length `min(nrow, ncol)`) receives their scalars.
    pub fn geqrf(ctx: *Ctx, a: MutMatrix, tau: []f64) es.Error!void {
        try length("geqrf: tau", tau.len, @min(a.nrow, a.ncol));
        const m = try dimension(a.nrow, "a dimension");
        const n = try dimension(a.ncol, "a dimension");
        const lda = try leading(a.nrow);
        var info: c_int = 0;
        var query: f64 = 0;
        const minus_one: c_int = -1;
        var scratch: [1]f64 = .{0};
        try guarded(dgeqrf_, .{ &m, &n, a.data.ptr, &lda, if (tau.len > 0) tau.ptr else &scratch, @as([*]f64, @ptrCast(&query)), &minus_one, &info });
        const work = try workspace(ctx, query);
        const lwork = try dimension(work.len, "a workspace");
        try guarded(dgeqrf_, .{ &m, &n, a.data.ptr, &lda, if (tau.len > 0) tau.ptr else &scratch, work.ptr, &lwork, &info });
    }

    /// Multiply `c` by `op(Q)` from `geqrf` (`side = .left`: `op(Q) * c`).
    pub fn ormqr(ctx: *Ctx, side: Side, trans: Transpose, qr: Matrix, tau: []const f64, out: MutMatrix) es.Error!void {
        const order = if (side == .left) out.nrow else out.ncol;
        if (qr.nrow != order or tau.len > qr.ncol or tau.len > order) {
            return es.raise("rzig: ormqr: the factorization is {d} x {d} with {d} reflectors for an order of {d}", .{ qr.nrow, qr.ncol, tau.len, order });
        }
        const m = try dimension(out.nrow, "a dimension");
        const n = try dimension(out.ncol, "a dimension");
        const k = try dimension(tau.len, "a dimension");
        const s = letter(side);
        const t = letter(trans);
        const lda = try leading(qr.nrow);
        const ldc = try leading(out.nrow);
        var info: c_int = 0;
        var query: f64 = 0;
        const minus_one: c_int = -1;
        var scratch: [1]f64 = .{0};
        const tau_ptr: [*]const f64 = if (tau.len > 0) tau.ptr else &scratch;
        try guarded(dormqr_, .{ &s, &t, &m, &n, &k, qr.data.ptr, &lda, tau_ptr, out.data.ptr, &ldc, @as([*]f64, @ptrCast(&query)), &minus_one, &info, 1, 1 });
        const work = try workspace(ctx, query);
        const lwork = try dimension(work.len, "a workspace");
        try guarded(dormqr_, .{ &s, &t, &m, &n, &k, qr.data.ptr, &lda, tau_ptr, out.data.ptr, &ldc, work.ptr, &lwork, &info, 1, 1 });
    }

    /// Least squares (or minimum norm) solution of `op(a) * x = b` for `a` of
    /// full rank; `b` has `max(nrow, ncol)` rows and its first rows receive `x`.
    pub fn gels(ctx: *Ctx, trans: Transpose, a: MutMatrix, b: MutMatrix) es.Error!void {
        if (b.nrow != @max(a.nrow, a.ncol)) {
            return es.raise("rzig: gels: b has {d} rows; it must have max(nrow, ncol) = {d}", .{ b.nrow, @max(a.nrow, a.ncol) });
        }
        const m = try dimension(a.nrow, "a dimension");
        const n = try dimension(a.ncol, "a dimension");
        const nrhs = try dimension(b.ncol, "a dimension");
        const t = letter(trans);
        const lda = try leading(a.nrow);
        const ldb = try leading(b.nrow);
        var info: c_int = 0;
        var query: f64 = 0;
        const minus_one: c_int = -1;
        try guarded(dgels_, .{ &t, &m, &n, &nrhs, a.data.ptr, &lda, b.data.ptr, &ldb, @as([*]f64, @ptrCast(&query)), &minus_one, &info, 1 });
        const work = try workspace(ctx, query);
        const lwork = try dimension(work.len, "a workspace");
        try guarded(dgels_, .{ &t, &m, &n, &nrhs, a.data.ptr, &lda, b.data.ptr, &ldb, work.ptr, &lwork, &info, 1 });
        if (info > 0) return es.raise("rzig: gels: the matrix does not have full rank (diagonal element {d} of the factor is zero)", .{info});
    }

    /// Eigenvalues (ascending, in `values`) and, when `vectors` is given, the
    /// eigenvectors of the symmetric `a`, whose `triangle` is used and destroyed.
    pub fn syevr(ctx: *Ctx, triangle: Triangle, a: MutMatrix, values: []f64, vectors: ?MutMatrix) es.Error!void {
        try shape("syevr: a", a.nrow, a.ncol, a.nrow, a.nrow);
        try length("syevr: values", values.len, a.nrow);
        if (vectors) |z| try shape("syevr: vectors", z.nrow, z.ncol, a.nrow, a.nrow);
        const n = try dimension(a.nrow, "a dimension");
        const jobz: u8 = if (vectors != null) 'V' else 'N';
        const range: u8 = 'A';
        const u = letter(triangle);
        const lda = try leading(a.nrow);
        const zero: f64 = 0;
        const zero_int: c_int = 0;
        var found: c_int = 0;
        var scratch: [1]f64 = .{0};
        const z_ptr: [*]f64 = if (vectors) |z| (if (z.data.len > 0) z.data.ptr else &scratch) else &scratch;
        const ldz = try leading(a.nrow);
        const support = try ctx.alloc(c_int, 2 * @max(a.nrow, 1));
        var info: c_int = 0;
        var query: f64 = 0;
        var iquery: c_int = 0;
        const minus_one: c_int = -1;
        const values_ptr: [*]f64 = if (values.len > 0) values.ptr else &scratch;
        try guarded(dsyevr_, .{ &jobz, &range, &u, &n, a.data.ptr, &lda, &zero, &zero, &zero_int, &zero_int, &zero, &found, values_ptr, z_ptr, &ldz, support.ptr, @as([*]f64, @ptrCast(&query)), &minus_one, @as([*]c_int, @ptrCast(&iquery)), &minus_one, &info, 1, 1, 1 });
        const work = try workspace(ctx, query);
        const iwork = try ctx.alloc(c_int, @intCast(@max(iquery, 1)));
        const lwork = try dimension(work.len, "a workspace");
        const liwork = try dimension(iwork.len, "a workspace");
        try guarded(dsyevr_, .{ &jobz, &range, &u, &n, a.data.ptr, &lda, &zero, &zero, &zero_int, &zero_int, &zero, &found, values_ptr, z_ptr, &ldz, support.ptr, work.ptr, &lwork, iwork.ptr, &liwork, &info, 1, 1, 1 });
        if (info > 0) return es.raise("rzig: syevr: the eigenvalue computation failed (internal error {d})", .{info});
    }

    /// Singular values (descending, in `s`) and, when both `u` (nrow x k) and
    /// `vt` (k x ncol) are given, the singular vectors of `a` (destroyed),
    /// where k = min(nrow, ncol).
    pub fn gesdd(ctx: *Ctx, a: MutMatrix, s: []f64, u: ?MutMatrix, vt: ?MutMatrix) es.Error!void {
        const k = @min(a.nrow, a.ncol);
        try length("gesdd: s", s.len, k);
        if ((u == null) != (vt == null)) return es.raise("rzig: gesdd: give both u and vt, or neither", .{});
        if (u) |left| try shape("gesdd: u", left.nrow, left.ncol, a.nrow, k);
        if (vt) |right| try shape("gesdd: vt", right.nrow, right.ncol, k, a.ncol);
        const jobz: u8 = if (u != null) 'S' else 'N';
        const m = try dimension(a.nrow, "a dimension");
        const n = try dimension(a.ncol, "a dimension");
        const lda = try leading(a.nrow);
        const ldu = try leading(a.nrow);
        const ldvt = try leading(k);
        var scratch: [1]f64 = .{0};
        const s_ptr: [*]f64 = if (s.len > 0) s.ptr else &scratch;
        const u_ptr: [*]f64 = if (u) |left| (if (left.data.len > 0) left.data.ptr else &scratch) else &scratch;
        const vt_ptr: [*]f64 = if (vt) |right| (if (right.data.len > 0) right.data.ptr else &scratch) else &scratch;
        const iwork = try ctx.alloc(c_int, 8 * @max(k, 1));
        var info: c_int = 0;
        var query: f64 = 0;
        const minus_one: c_int = -1;
        try guarded(dgesdd_, .{ &jobz, &m, &n, a.data.ptr, &lda, s_ptr, u_ptr, &ldu, vt_ptr, &ldvt, @as([*]f64, @ptrCast(&query)), &minus_one, iwork.ptr, &info, 1 });
        const work = try workspace(ctx, query);
        const lwork = try dimension(work.len, "a workspace");
        try guarded(dgesdd_, .{ &jobz, &m, &n, a.data.ptr, &lda, s_ptr, u_ptr, &ldu, vt_ptr, &ldvt, work.ptr, &lwork, iwork.ptr, &info, 1 });
        if (info > 0) return es.raise("rzig: gesdd: the singular value decomposition did not converge", .{});
    }
};
