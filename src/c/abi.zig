//! Hand-written declarations of R's C API. R's macro-heavy headers are not
//! imported directly.
//!
//! Keep every constant synchronized with the installed Rinternals.h. A stale
//! value can silently break when R changes.
//!
//! Never dereference SEXPREC fields directly - the struct layout is not stable.
//! Use the accessor functions only.

const std = @import("std");

pub const SEXP = *opaque {};
pub const R_xlen_t = isize;
pub const Rboolean = c_int;
pub const FALSE: Rboolean = 0;
pub const TRUE: Rboolean = 1;

// ---------------------------------------------------------------------------
// SEXPTYPE. VERIFY EACH IN tools/abi_check.c.
// ---------------------------------------------------------------------------
pub const NILSXP: c_uint = 0;
pub const SYMSXP: c_uint = 1;
pub const LISTSXP: c_uint = 2;
pub const CLOSXP: c_uint = 3;
pub const ENVSXP: c_uint = 4;
pub const PROMSXP: c_uint = 5;
pub const LANGSXP: c_uint = 6;
pub const SPECIALSXP: c_uint = 7;
pub const BUILTINSXP: c_uint = 8;
pub const CHARSXP: c_uint = 9;
pub const LGLSXP: c_uint = 10;
pub const INTSXP: c_uint = 13;
pub const REALSXP: c_uint = 14;
pub const CPLXSXP: c_uint = 15;
pub const STRSXP: c_uint = 16;
pub const DOTSXP: c_uint = 17;
pub const ANYSXP: c_uint = 18;
pub const VECSXP: c_uint = 19;
pub const EXPRSXP: c_uint = 20;
pub const EXTPTRSXP: c_uint = 22;
pub const RAWSXP: c_uint = 24;

// NA sentinels. NA_REAL is a specific NaN payload; see na.zig.
pub const NA_INTEGER: c_int = std.math.minInt(c_int);
pub const NA_LOGICAL: c_int = std.math.minInt(c_int);

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
pub extern var R_NilValue: SEXP;
pub extern var R_NaString: SEXP;
pub extern var R_BlankString: SEXP;
pub extern var R_GlobalEnv: SEXP;
pub extern var R_NamesSymbol: SEXP;
pub extern var R_DimSymbol: SEXP;
pub extern var R_ClassSymbol: SEXP;

// ---------------------------------------------------------------------------
// Type and length. Rf_length returns int and truncates long vectors, so
// it is deliberately NOT declared here so it cannot be used by accident.
// ---------------------------------------------------------------------------
pub extern fn TYPEOF(x: SEXP) c_uint;
pub extern fn Rf_xlength(x: SEXP) R_xlen_t;
pub extern fn Rf_isNull(x: SEXP) Rboolean;
pub extern fn Rf_isMatrix(x: SEXP) Rboolean;
pub extern fn Rf_type2char(t: c_uint) [*:0]const u8;

// ---------------------------------------------------------------------------
// Read-only data access. Prefer these over REAL/INTEGER so ALTREP objects are
// not needlessly materialised.
// ---------------------------------------------------------------------------
pub extern fn REAL_RO(x: SEXP) [*]const f64;
pub extern fn INTEGER_RO(x: SEXP) [*]const c_int;
pub extern fn LOGICAL_RO(x: SEXP) [*]const c_int;
pub extern fn RAW_RO(x: SEXP) [*]const u8;
pub extern fn REAL_ELT(x: SEXP, i: R_xlen_t) f64;
pub extern fn INTEGER_ELT(x: SEXP, i: R_xlen_t) c_int;
pub extern fn REAL_GET_REGION(x: SEXP, i: R_xlen_t, n: R_xlen_t, buf: [*]f64) R_xlen_t;

// Writable access - only for vectors allocated by this package.
pub extern fn REAL(x: SEXP) [*]f64;
pub extern fn INTEGER(x: SEXP) [*]c_int;
pub extern fn LOGICAL(x: SEXP) [*]c_int;

// ---------------------------------------------------------------------------
// Strings
// ---------------------------------------------------------------------------
pub extern fn STRING_ELT(x: SEXP, i: R_xlen_t) SEXP;
pub extern fn SET_STRING_ELT(x: SEXP, i: R_xlen_t, v: SEXP) void;
pub extern fn Rf_mkCharLenCE(s: [*]const u8, len: c_int, ce: c_uint) SEXP;
pub extern fn Rf_translateCharUTF8(x: SEXP) [*:0]const u8;
pub const CE_NATIVE: c_uint = 0;
pub const CE_UTF8: c_uint = 1;

// ---------------------------------------------------------------------------
// Lists
// ---------------------------------------------------------------------------
pub extern fn VECTOR_ELT(x: SEXP, i: R_xlen_t) SEXP;
pub extern fn SET_VECTOR_ELT(x: SEXP, i: R_xlen_t, v: SEXP) SEXP;

// ---------------------------------------------------------------------------
// Allocation - all of these can trigger GC and can longjmp.
// Protect anything you hold across them.
// ---------------------------------------------------------------------------
pub extern fn Rf_allocVector(t: c_uint, n: R_xlen_t) SEXP;
pub extern fn Rf_allocMatrix(t: c_uint, nrow: c_int, ncol: c_int) SEXP;
pub extern fn Rf_duplicate(x: SEXP) SEXP;
pub extern fn Rf_shallow_duplicate(x: SEXP) SEXP;
pub extern fn Rf_getAttrib(x: SEXP, sym: SEXP) SEXP;
pub extern fn Rf_setAttrib(x: SEXP, sym: SEXP, val: SEXP) SEXP;
pub extern fn Rf_install(name: [*:0]const u8) SEXP;

// Protection. PROTECT/UNPROTECT are macros, so use the callable functions.
pub extern fn Rf_protect(x: SEXP) SEXP;
pub extern fn Rf_unprotect(n: c_int) void;

// vmax stack, for translateCharUTF8 scratch memory.
pub extern fn vmaxget() ?*anyopaque;
pub extern fn vmaxset(p: ?*anyopaque) void;

// ---------------------------------------------------------------------------
// Errors and output. Rf_error/Rf_warning longjmp - boundary.zig only.
// ---------------------------------------------------------------------------
pub extern fn Rf_error(fmt: [*:0]const u8, ...) noreturn;
pub extern fn Rf_warning(fmt: [*:0]const u8, ...) void;
pub extern fn Rprintf(fmt: [*:0]const u8, ...) void;
pub extern fn REprintf(fmt: [*:0]const u8, ...) void;

// Interrupts. R_CheckUserInterrupt longjmps; always go through R_ToplevelExec.
pub extern fn R_CheckUserInterrupt() void;
pub extern fn R_ToplevelExec(fun: *const fn (?*anyopaque) callconv(.c) void, data: ?*anyopaque) Rboolean;
pub extern fn R_UnwindProtect(
    fun: *const fn (?*anyopaque) callconv(.c) SEXP,
    data: ?*anyopaque,
    cleanfun: *const fn (?*anyopaque, Rboolean) callconv(.c) void,
    cleandata: ?*anyopaque,
    cont: SEXP,
) SEXP;

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
pub const DllInfo = opaque {};
pub const DL_FUNC = *const fn () callconv(.c) void;
pub const R_CallMethodDef = extern struct {
    name: ?[*:0]const u8,
    fun: ?DL_FUNC,
    numArgs: c_int,
};
pub extern fn R_registerRoutines(
    info: *DllInfo,
    croutines: ?*const anyopaque,
    callRoutines: ?[*]const R_CallMethodDef,
    fortranRoutines: ?*const anyopaque,
    externalRoutines: ?*const anyopaque,
) c_int;
pub extern fn R_useDynamicSymbols(info: *DllInfo, value: Rboolean) Rboolean;
pub extern fn R_forceSymbols(info: *DllInfo, value: Rboolean) Rboolean;
