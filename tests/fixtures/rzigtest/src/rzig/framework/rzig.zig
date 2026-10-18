//! RZig public API. Nothing but re-exports lives here.

const std = @import("std");

/// Per-call arena for Zig-owned scratch and result memory.
pub const Ctx = @import("alloc.zig").Ctx;
/// Atomic-vector return wrapper with arena-backed names, dimensions, and classes.
pub const Attributed = @import("attributes.zig").Attributed;
/// Recoverable error set used by exported functions.
pub const Error = @import("error_state.zig").Error;
/// Record a recoverable R error without non-local control flow.
pub const raise = @import("error_state.zig").raise;
/// Queue a warning for safe delivery after Zig cleanup.
pub const warn = @import("error_state.zig").warn;
/// Check for Ctrl-C without allowing R's longjmp to cross Zig frames.
pub const checkInterrupt = @import("interrupt.zig").checkInterrupt;
/// Run a pure Zig indexed loop on worker threads without exposing R capabilities.
pub const parallelFor = @import("parallel.zig").parallelFor;
/// Reduce over indices on worker threads in an order fixed by the count alone.
pub const parallelReduce = @import("parallel.zig").parallelReduce;
/// Random streams for workers, from `ctx.rngStreams()`.
pub const RngStreams = @import("rng.zig").Streams;
pub const RngStream = @import("rng.zig").Stream;
/// The number of worker threads `parallelFor` uses for `count` indices (see
/// `parallel.threadCount`: RZIG_NUM_THREADS, OMP_THREAD_LIMIT, R CMD check).
pub const parallelThreadCount = @import("parallel.zig").threadCount;
/// Calling-thread capability for draws controlled by R's `set.seed()`.
pub const Rng = @import("rng.zig").Rng;
/// Progress bar on R's message stream, created with `ctx.progress()`.
pub const Progress = @import("progress.zig").Progress;
/// R's distribution functions: `density`, `cdf` and `quantile` for each
/// `rzig.Distribution`; draws come from `rzig.Rng.draw`.
pub const Rmath = @import("rmath.zig").Rmath;
/// The distributions of R's Rmath library.
pub const Distribution = @import("rmath.zig").Distribution;
/// BLAS routines of the libraries R links (opt in with use_rzig_lapack()).
pub const Blas = @import("lapack.zig").Blas;
/// LAPACK routines of the libraries R links (opt in with use_rzig_lapack()).
pub const Lapack = @import("lapack.zig").Lapack;
/// Options of BLAS and LAPACK routines.
pub const Transpose = @import("lapack.zig").Transpose;
pub const Triangle = @import("lapack.zig").Triangle;
pub const Side = @import("lapack.zig").Side;
pub const Diagonal = @import("lapack.zig").Diagonal;
/// An R function received as an argument, called from Zig with `call`.
pub const Function = @import("rcall.zig").Function;
/// R's optimizers (optim(): BFGS, Nelder-Mead, CG, L-BFGS-B) for Zig objectives.
pub const Optimize = @import("optimize.zig").Optimize;
/// R's numerical integration (integrate(): QUADPACK dqags and dqagi).
pub const Integrate = @import("optimize.zig").Integrate;
/// A borrowed view of a Matrix::dgCMatrix (column-compressed sparse matrix).
pub const CscMatrix = @import("sparse.zig").CscMatrix;
/// A writable column-major double matrix (`rzig.Mut(rzig.Matrix).data`, `ctx.matrix()`).
pub const MutableMatrix = @import("matrix.zig").MutableMatrixOf(f64);
/// NA constants (`NA.real`, `NA.integer`, `NA.logical`) and predicates.
pub const NA = @import("na.zig");
/// One element of an R logical vector: `TRUE`, `FALSE` or `NA`.
pub const Logical = @import("na.zig").Logical;
/// One element of an R complex vector, with the layout of `Rcomplex`.
pub const Complex = @import("complex.zig").Complex;
/// The bytes of an R raw vector.
pub const Raw = @import("complex.zig").Raw;
/// A named R list read into, or built from, a Zig struct.
pub const Record = @import("record.zig").Record;
/// A data frame read into, or built from, a Zig struct of columns.
pub const DataFrame = @import("record.zig").DataFrame;
/// An R factor: codes and levels.
pub const Factor = @import("record.zig").Factor;
/// A Zig value owned by an R object (an external pointer) across calls.
pub const External = @import("external.zig").External;
/// Borrowed R value with read-only methods (kind, length, attributes, names,
/// classes, list elements, typed conversion with `get`).
pub const Sexp = @import("sexp.zig").Sexp;
/// The kinds of R objects that `Sexp.kind()` reports.
pub const SexpKind = @import("sexp.zig").Kind;
/// Arena-backed builder materialized as a named R list at the boundary.
pub const List = @import("list.zig").List;
/// Borrowed column-major view of an R double matrix.
pub const Matrix = @import("matrix.zig").Matrix;
/// Borrowed column-major view of an R integer matrix.
pub const IntMatrix = @import("matrix.zig").IntMatrix;
/// Copied column-major view of an R logical matrix without NA.
pub const BoolMatrix = @import("matrix.zig").BoolMatrix;
/// Opt-in mutable input that duplicates an R vector before exposing writes.
pub const Mut = @import("convert.zig").Mut;
/// Generate native wrappers and register every manifest export.
pub const registerModule = @import("register.zig").registerModule;
/// Last-resort panic handler for a Zig-backed R shared library.
pub const Panic = @import("panic.zig").Panic;

/// Internal surface. Not covered by semver. Use at your own risk.
pub const internal = struct {
    pub const boundary = @import("boundary.zig");
    pub const compat = @import("compat.zig");
    pub const convert = @import("convert.zig");
    pub const interrupt = @import("interrupt.zig");
    pub const io = @import("io.zig");
    pub const parallel = @import("parallel.zig");
    pub const protect = @import("protect.zig");
    pub const unwind = @import("unwind.zig");
    pub const c = @import("c/abi.zig");
};

test {
    std.testing.refAllDecls(@This());
}
