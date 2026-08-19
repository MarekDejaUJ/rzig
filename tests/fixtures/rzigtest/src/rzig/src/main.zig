const std = @import("std");

const SEXP = *opaque {};
const R_xlen_t = isize;
const Rboolean = c_int;
const DllInfo = opaque {};
const DL_FUNC = *const fn () callconv(.c) ?*anyopaque;

const REALSXP: c_uint = 14;
const FALSE: Rboolean = 0;
const TRUE: Rboolean = 1;

const R_CallMethodDef = extern struct {
    name: ?[*:0]const u8,
    fun: ?DL_FUNC,
    numArgs: c_int,
};

extern var R_NilValue: SEXP;
extern fn TYPEOF(value: SEXP) c_int;
extern fn Rf_xlength(value: SEXP) R_xlen_t;
extern fn REAL_RO(value: SEXP) [*]const f64;
extern fn REAL(value: SEXP) [*]f64;
extern fn Rf_allocVector(kind: c_uint, len: R_xlen_t) SEXP;
extern fn Rf_protect(value: SEXP) SEXP;
extern fn Rf_unprotect(count: c_int) void;
extern fn REprintf(format: [*:0]const u8, ...) void;
extern fn Rf_error(format: [*:0]const u8, ...) noreturn;
extern fn R_registerRoutines(
    dll: *DllInfo,
    c_methods: ?*const anyopaque,
    call_methods: ?[*]const R_CallMethodDef,
    fortran_methods: ?*const anyopaque,
    external_methods: ?*const anyopaque,
) c_int;
extern fn R_useDynamicSymbols(dll: *DllInfo, value: Rboolean) Rboolean;
extern fn R_forceSymbols(dll: *DllInfo, value: Rboolean) Rboolean;

/// Route a Zig safety panic into R instead of terminating the process.
pub const panic = std.debug.FullPanic(rzigPanic);

fn rzigPanic(message: []const u8, first_trace_addr: ?usize) noreturn {
    var storage: [1024]u8 = undefined;
    const rendered: [:0]const u8 = if (first_trace_addr) |address|
        std.fmt.bufPrintZ(
            &storage,
            "rzig: internal Zig safety failure: {s}\ntrace origin: 0x{x}",
            .{ message, address },
        ) catch "rzig: internal Zig safety failure"
    else
        std.fmt.bufPrintZ(
            &storage,
            "rzig: internal Zig safety failure: {s}",
            .{message},
        ) catch "rzig: internal Zig safety failure";

    REprintf("%s\n", rendered.ptr);
    Rf_error("%s", rendered.ptr);
}

/// Hand-written proof that R can call Zig and receive a newly allocated vector.
export fn add_one(value: SEXP) SEXP {
    if (TYPEOF(value) != REALSXP) return R_NilValue;

    const len = Rf_xlength(value);
    if (len < 0) return R_NilValue;

    const result = Rf_protect(Rf_allocVector(REALSXP, len));
    const input = REAL_RO(value);
    const output = REAL(result);
    const count: usize = @intCast(len);
    for (input[0..count], output[0..count]) |number, *slot| {
        slot.* = number + 1.0;
    }
    Rf_unprotect(1);
    return result;
}

/// Deliberately trigger a ReleaseSafe bounds panic for the integration test.
export fn panic_bounds(value: SEXP) SEXP {
    const r_length = Rf_xlength(value);
    if (r_length < 0) return R_NilValue;

    const one = [_]u8{0};
    const index: usize = @intCast(r_length);
    if (one[index] == 0) return R_NilValue;
    return R_NilValue;
}

const call_methods = [_]R_CallMethodDef{
    .{ .name = "add_one", .fun = @ptrCast(&add_one), .numArgs = 1 },
    .{ .name = "panic_bounds", .fun = @ptrCast(&panic_bounds), .numArgs = 1 },
    .{ .name = null, .fun = null, .numArgs = 0 },
};

/// Register the proof-of-life routine and require symbol-based lookup.
export fn rzig_init(dll: *DllInfo) void {
    _ = R_registerRoutines(dll, null, &call_methods, null, null);
    _ = R_useDynamicSymbols(dll, FALSE);
    _ = R_forceSymbols(dll, TRUE);
}
