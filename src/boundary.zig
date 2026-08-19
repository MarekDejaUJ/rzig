//! THE BOUNDARY. The only file in this project permitted to call Rf_error,
//! Rf_warning or Rf_errorcall. `zig build lint` enforces that.
//!
//! The ordering in `invoke` below is the entire safety argument of the project:
//! R's error mechanism is longjmp, which skips Zig `defer`. So every Zig
//! cleanup must have already run by the time we signal an error to R.
//!
//!   1. init Ctx                       defer ctx.deinit()
//!   2. init protect stack             defer stack.unwindAll()
//!   3. unmarshal args  -> may record an error, must not signal one
//!   4. call user fn    -> returns Error!T
//!   5. marshal result  -> protect immediately after each allocation
//!   6. run deferred cleanups          <- everything Zig-owned is released here
//!   7. THEN signal the error, or return the SEXP
//!
//! Steps 6 and 7 are ordered, never interleaved. Do not "simplify" this.

const std = @import("std");
const c = @import("c/abi.zig");
const protect = @import("protect.zig");
const convert = @import("convert.zig");
const es = @import("error_state.zig");
const Ctx = @import("alloc.zig").Ctx;

/// Entry point used by every generated arity wrapper.
///
/// `sexps` is a tuple of c.SEXP with one element per user-visible parameter
/// (the optional *Ctx parameter is supplied by us, not by R).
pub fn invoke(
    comptime func: anytype,
    comptime name: []const u8,
    sexps: anytype,
) c.SEXP {
    // ---- step 1 and 2 -----------------------------------------------------
    var ctx = Ctx.init();
    var stack = protect.Stack.init();

    // `failed` is set instead of signalling immediately. Nothing below this
    // point may call Rf_error.
    var failed = false;
    var result: c.SEXP = c.R_NilValue;

    blk: {
        // ---- step 3: unmarshal ---------------------------------------------
        // TODO: detect an optional *Ctx first parameter at comptime.
        // TODO: build the ArgsTuple, converting each element.
        //   const info = @typeInfo(@TypeOf(func)).@"fn";
        //   var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;
        //   inline for (...) |i| { args[i] = convert.fromSexp(...) catch { failed = true; break :blk; }; }
        _ = sexps;
        _ = name;

        // ---- step 4: call the user's function -------------------------------
        // const ret = @call(.auto, func, args);
        // const payload = if (isErrorUnion) ret catch { failed = true; break :blk; } else ret;

        // ---- step 5: marshal the result -------------------------------------
        // result = convert.toSexp(&stack, &ctx, payload) catch { failed = true; break :blk; };
        _ = func;
    }

    // ---- step 6: release everything Zig owns, in order ----------------------
    stack.unwindAll();
    const msg = es.take(); // copy message out of the buffer before ctx dies
    ctx.deinit();

    // ---- step 7: and only now talk to R ------------------------------------
    if (failed) {
        // The one and only error exit in the project. This longjmps.
        c.Rf_error("%s", msg.ptr);
        unreachable; // Rf_error is noreturn in practice; keep for the optimiser
    }
    return result;
}
