//! Hand-written declarations for the subset of R's C API used by RZig.
//!
//! R's macro-heavy headers are deliberately not imported. Keep these types and
//! constants synchronized with the public R headers, and never inspect SEXPREC
//! fields directly because their layout is not stable.

const std = @import("std");

/// Opaque handle to an R object.
pub const SEXP = *opaque {};
/// C's `SEXPTYPE`, declared by R as `unsigned int`.
pub const SEXPTYPE = c_uint;
/// Long-vector length and index type.
pub const R_xlen_t = isize;
/// R's two-valued C boolean type.
pub const Rboolean = c_int;
/// Raw-vector element type.
pub const Rbyte = u8;
/// R's false boolean value.
pub const FALSE: Rboolean = 0;
/// R's true boolean value.
pub const TRUE: Rboolean = 1;

// SEXPTYPE values. The C ABI checker verifies every value against Rinternals.h.
/// Null object.
pub const NILSXP: SEXPTYPE = 0;
/// Symbol.
pub const SYMSXP: SEXPTYPE = 1;
/// Pair list.
pub const LISTSXP: SEXPTYPE = 2;
/// Closure.
pub const CLOSXP: SEXPTYPE = 3;
/// Environment.
pub const ENVSXP: SEXPTYPE = 4;
/// Promise.
pub const PROMSXP: SEXPTYPE = 5;
/// Language object.
pub const LANGSXP: SEXPTYPE = 6;
/// Special form.
pub const SPECIALSXP: SEXPTYPE = 7;
/// Built-in function.
pub const BUILTINSXP: SEXPTYPE = 8;
/// Internal scalar string.
pub const CHARSXP: SEXPTYPE = 9;
/// Logical vector.
pub const LGLSXP: SEXPTYPE = 10;
/// Integer vector.
pub const INTSXP: SEXPTYPE = 13;
/// Double vector.
pub const REALSXP: SEXPTYPE = 14;
/// Complex vector.
pub const CPLXSXP: SEXPTYPE = 15;
/// Character vector.
pub const STRSXP: SEXPTYPE = 16;
/// Dot-dot-dot object.
pub const DOTSXP: SEXPTYPE = 17;
/// Wildcard used in native routine registration.
pub const ANYSXP: SEXPTYPE = 18;
/// Generic vector (R list).
pub const VECSXP: SEXPTYPE = 19;
/// Expression vector.
pub const EXPRSXP: SEXPTYPE = 20;
/// Byte code.
pub const BCODESXP: SEXPTYPE = 21;
/// External pointer.
pub const EXTPTRSXP: SEXPTYPE = 22;
/// Weak reference.
pub const WEAKREFSXP: SEXPTYPE = 23;
/// Raw vector.
pub const RAWSXP: SEXPTYPE = 24;
/// Non-vector object.
pub const OBJSXP: SEXPTYPE = 25;
/// S4 object; retained by R as an alias for `OBJSXP`.
pub const S4SXP: SEXPTYPE = 25;
/// Fresh internal node used by R's protection diagnostics.
pub const NEWSXP: SEXPTYPE = 30;
/// Released internal node used by R's protection diagnostics.
pub const FREESXP: SEXPTYPE = 31;
/// Any callable R function.
pub const FUNSXP: SEXPTYPE = 99;

/// Missing integer sentinel, guaranteed by R to be `INT_MIN`.
pub const NA_INTEGER: c_int = std.math.minInt(c_int);
/// Missing logical sentinel, identical to `NA_INTEGER`.
pub const NA_LOGICAL: c_int = std.math.minInt(c_int);

/// Native string encoding.
pub const CE_NATIVE: c_uint = 0;
/// UTF-8 string encoding.
pub const CE_UTF8: c_uint = 1;
/// Latin-1 string encoding.
pub const CE_LATIN1: c_uint = 2;
/// Byte string with no declared character encoding.
pub const CE_BYTES: c_uint = 3;
/// Symbol encoding.
pub const CE_SYMBOL: c_uint = 5;
/// Any string encoding.
pub const CE_ANY: c_uint = 99;

/// R's global environment.
pub extern var R_GlobalEnv: SEXP;
/// R's base environment.
pub extern var R_BaseEnv: SEXP;
/// R's null singleton.
pub extern var R_NilValue: SEXP;
/// R's distinguished missing-string singleton.
pub extern var R_NaString: SEXP;
/// R's empty CHARSXP singleton.
pub extern var R_BlankString: SEXP;
/// Installed `class` symbol.
pub extern var R_ClassSymbol: SEXP;
/// Installed `dim` symbol.
pub extern var R_DimSymbol: SEXP;
/// Installed `names` symbol.
pub extern var R_NamesSymbol: SEXP;
/// R's ordinary NaN value.
pub extern var R_NaN: f64;
/// R's missing-real sentinel with its distinguished NaN payload.
pub extern var R_NaReal: f64;
/// Runtime missing-integer sentinel.
pub extern var R_NaInt: c_int;

/// Return an object's SEXPTYPE. Does not allocate or longjmp.
pub extern fn TYPEOF(x: SEXP) c_int;
/// Return an object's long-vector-safe length. Does not allocate or longjmp.
pub extern fn Rf_xlength(x: SEXP) R_xlen_t;
/// Test whether an object is R's null singleton.
pub extern fn Rf_isNull(x: SEXP) Rboolean;
/// Test whether an object has matrix dimensions.
pub extern fn Rf_isMatrix(x: SEXP) Rboolean;
/// Return R's static name for a SEXPTYPE.
pub extern fn Rf_type2char(t: SEXPTYPE) [*:0]const u8;

/// Borrow read-only double-vector storage without forcing writable access.
pub extern fn REAL_RO(x: SEXP) [*]const f64;
/// Borrow read-only integer-vector storage without forcing writable access.
pub extern fn INTEGER_RO(x: SEXP) [*]const c_int;
/// Borrow read-only logical-vector storage without forcing writable access.
pub extern fn LOGICAL_RO(x: SEXP) [*]const c_int;
/// Borrow read-only raw-vector storage without forcing writable access.
pub extern fn RAW_RO(x: SEXP) [*]const Rbyte;
/// Read one double element, including from ALTREP vectors.
pub extern fn REAL_ELT(x: SEXP, i: R_xlen_t) f64;
/// Read one integer element, including from ALTREP vectors.
pub extern fn INTEGER_ELT(x: SEXP, i: R_xlen_t) c_int;
/// Read one logical element, including from ALTREP vectors.
pub extern fn LOGICAL_ELT(x: SEXP, i: R_xlen_t) c_int;
/// Copy a region of a double vector into caller-owned storage.
pub extern fn REAL_GET_REGION(x: SEXP, i: R_xlen_t, n: R_xlen_t, buf: [*]f64) R_xlen_t;

/// Obtain writable double-vector storage; may materialize ALTREP data.
pub extern fn REAL(x: SEXP) [*]f64;
/// Obtain writable integer-vector storage; may materialize ALTREP data.
pub extern fn INTEGER(x: SEXP) [*]c_int;
/// Obtain writable logical-vector storage; may materialize ALTREP data.
pub extern fn LOGICAL(x: SEXP) [*]c_int;

/// Read one CHARSXP from a character vector.
pub extern fn STRING_ELT(x: SEXP, i: R_xlen_t) SEXP;
/// Store one CHARSXP in a character vector using R's write barrier.
pub extern fn SET_STRING_ELT(x: SEXP, i: R_xlen_t, value: SEXP) void;
/// Allocate a CHARSXP from an explicitly sized encoded byte sequence.
pub extern fn Rf_mkCharLenCE(bytes: [*]const u8, len: c_int, encoding: c_uint) SEXP;
/// Translate a CHARSXP to temporary UTF-8 storage; may allocate and longjmp.
pub extern fn Rf_translateCharUTF8(x: SEXP) [*:0]const u8;

/// Read one element from a generic vector.
pub extern fn VECTOR_ELT(x: SEXP, i: R_xlen_t) SEXP;
/// Store an element in a generic vector using R's write barrier.
pub extern fn SET_VECTOR_ELT(x: SEXP, i: R_xlen_t, value: SEXP) SEXP;

/// Allocate an R vector; may allocate and longjmp.
pub extern fn Rf_allocVector(t: SEXPTYPE, len: R_xlen_t) SEXP;
/// Allocate an R matrix; may allocate and longjmp.
pub extern fn Rf_allocMatrix(t: SEXPTYPE, rows: c_int, columns: c_int) SEXP;
/// Deep-duplicate an R object; may allocate and longjmp.
pub extern fn Rf_duplicate(x: SEXP) SEXP;
/// Shallow-duplicate an R object; may allocate and longjmp.
pub extern fn Rf_shallow_duplicate(x: SEXP) SEXP;
/// Read an attribute; may allocate and longjmp for some objects.
pub extern fn Rf_getAttrib(x: SEXP, symbol: SEXP) SEXP;
/// Set an attribute using R's write barrier; may allocate and longjmp.
pub extern fn Rf_setAttrib(x: SEXP, symbol: SEXP, value: SEXP) SEXP;
/// Install a NUL-terminated symbol name; may allocate and longjmp.
pub extern fn Rf_install(name: [*:0]const u8) SEXP;
/// Construct a zero-argument R call; may allocate and longjmp.
pub extern fn Rf_lang1(function: SEXP) SEXP;
/// Evaluate an expression in an environment; may allocate and longjmp.
pub extern fn Rf_eval(expression: SEXP, environment: SEXP) SEXP;

/// Protect an R object from garbage collection.
pub extern fn Rf_protect(x: SEXP) SEXP;
/// Pop objects from R's protection stack.
pub extern fn Rf_unprotect(count: c_int) void;

/// Snapshot R's temporary allocation stack.
pub extern fn vmaxget() ?*anyopaque;
/// Restore R's temporary allocation stack.
pub extern fn vmaxset(mark: ?*const anyopaque) void;

/// Raise an R error without call context; longjmps and never returns.
pub extern fn Rf_error(format: [*:0]const u8, ...) noreturn;
/// Raise an R error with call context; longjmps and never returns.
pub extern fn Rf_errorcall(call: SEXP, format: [*:0]const u8, ...) noreturn;
/// Emit an R warning; may longjmp when warnings are configured as errors.
pub extern fn Rf_warning(format: [*:0]const u8, ...) void;
/// Print through R's standard output connection.
pub extern fn Rprintf(format: [*:0]const u8, ...) void;
/// Print through R's standard error connection.
pub extern fn REprintf(format: [*:0]const u8, ...) void;

/// Probe for a user interrupt; longjmps when an interrupt is pending.
pub extern fn R_CheckUserInterrupt() void;
/// Signal R's interrupt condition without offering a resume restart.
pub extern fn Rf_onintrNoResume() void;
/// Run a callback behind an R top-level context that catches longjmp.
pub extern fn R_ToplevelExec(callback: *const fn (?*anyopaque) callconv(.c) void, data: ?*anyopaque) Rboolean;
/// Run a callback with cleanup that R invokes during non-local unwinding.
pub extern fn R_UnwindProtect(
    callback: *const fn (?*anyopaque) callconv(.c) SEXP,
    data: ?*anyopaque,
    cleanup: *const fn (?*anyopaque, Rboolean) callconv(.c) void,
    cleanup_data: ?*anyopaque,
    continuation: ?SEXP,
) SEXP;

/// Load R's random-number state for native draws; may allocate and longjmp.
pub extern fn GetRNGstate() void;
/// Save R's random-number state after native draws; may allocate and longjmp.
pub extern fn PutRNGstate() void;
/// Draw from R's current uniform random-number generator.
pub extern fn unif_rand() f64;
/// Draw from R's current standard-normal random-number generator.
pub extern fn norm_rand() f64;
/// Draw from R's current standard-exponential random-number generator.
pub extern fn exp_rand() f64;

/// Evaluate the normal cumulative distribution function from Rmath.
pub extern fn Rf_pnorm5(x: f64, mean: f64, standard_deviation: f64, lower_tail: c_int, log_probability: c_int) f64;
/// Evaluate the normal quantile function from Rmath.
pub extern fn Rf_qnorm5(probability: f64, mean: f64, standard_deviation: f64, lower_tail: c_int, log_probability: c_int) f64;

/// Distinguish R's missing-real payload from other NaN values.
pub extern fn R_IsNA(value: f64) c_int;
/// Test for a non-NA NaN value.
pub extern fn R_IsNaN(value: f64) c_int;

/// Opaque descriptor for a loaded R dynamic library.
pub const DllInfo = opaque {};
/// Erased native routine pointer used by R's registration API.
pub const DL_FUNC = *const fn () callconv(.c) ?*anyopaque;
/// Native primitive argument type identifier.
pub const R_NativePrimitiveArgType = c_uint;
/// Registration record for `.C` routines.
pub const R_CMethodDef = extern struct {
    name: ?[*:0]const u8,
    fun: ?DL_FUNC,
    numArgs: c_int,
    types: ?[*]R_NativePrimitiveArgType,
};
/// Registration record for `.Fortran` routines.
pub const R_FortranMethodDef = R_CMethodDef;
/// Registration record for `.Call` routines.
pub const R_CallMethodDef = extern struct {
    name: ?[*:0]const u8,
    fun: ?DL_FUNC,
    numArgs: c_int,
};
/// Registration record for `.External` routines.
pub const R_ExternalMethodDef = R_CallMethodDef;

/// Register native routines with a loaded R dynamic library.
pub extern fn R_registerRoutines(
    info: *DllInfo,
    c_routines: ?[*]const R_CMethodDef,
    call_routines: ?[*]const R_CallMethodDef,
    fortran_routines: ?[*]const R_FortranMethodDef,
    external_routines: ?[*]const R_ExternalMethodDef,
) c_int;
/// Enable or disable lookup of unregistered native symbols.
pub extern fn R_useDynamicSymbols(info: *DllInfo, value: Rboolean) Rboolean;
/// Require callers to use registered native symbols rather than strings.
pub extern fn R_forceSymbols(info: *DllInfo, value: Rboolean) Rboolean;

comptime {
    if (@sizeOf(SEXPTYPE) != @sizeOf(c_uint)) @compileError("SEXPTYPE must match C unsigned int");
    if (@sizeOf(Rboolean) != @sizeOf(c_int)) @compileError("Rboolean must match C int");
    if (@sizeOf(R_xlen_t) != @sizeOf(isize)) @compileError("R_xlen_t must match pointer width");
}

test "hard-coded sentinel relationships" {
    try std.testing.expectEqual(NA_INTEGER, NA_LOGICAL);
    try std.testing.expectEqual(@as(SEXPTYPE, 25), S4SXP);
    try std.testing.expectEqual(OBJSXP, S4SXP);
}
