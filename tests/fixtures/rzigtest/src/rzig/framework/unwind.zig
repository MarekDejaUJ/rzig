//! Typed resource cleanup around R calls that may perform a non-local transfer.
//!
//! This module is internal because its callback returns a raw R object. Ordinary
//! package code should remain on RZig's plain-data public API.

const std = @import("std");
const c = @import("c/abi.zig");

/// Run `body` behind `R_UnwindProtect` and invoke `cleanup` on every exit path.
///
/// `state` must be a mutable single-item pointer. The body may call R only on
/// the thread that entered the native boundary. Cleanup receives `true` during
/// a non-local transfer and must release only non-R resources; it must not call
/// R, fail, or panic. When R jumps, cleanup runs and the jump is then resumed,
/// so this function does not return on that path.
pub fn protect(
    state: anytype,
    comptime body: anytype,
    comptime cleanup: anytype,
) c.SEXP {
    const StatePointer = @TypeOf(state);
    comptime validateCallbacks(StatePointer, body, cleanup);
    const Callbacks = CallbackAdapter(StatePointer, body, cleanup);
    return c.R_UnwindProtect(
        &Callbacks.run,
        @ptrCast(state),
        &Callbacks.clean,
        @ptrCast(state),
        null,
    );
}

/// Validate typed unwind callbacks without invoking R.
pub fn validateCallbacks(
    comptime StatePointer: type,
    comptime body: anytype,
    comptime cleanup: anytype,
) void {
    const pointer = switch (@typeInfo(StatePointer)) {
        .pointer => |info| info,
        else => @compileError(
            "rzig.internal.unwind.protect: state must be a mutable single-item pointer",
        ),
    };
    if (pointer.size != .one or pointer.is_const or pointer.is_allowzero) {
        @compileError(
            "rzig.internal.unwind.protect: state must be a mutable single-item pointer",
        );
    }

    const Body = @TypeOf(body);
    const body_info = functionInfo(
        Body,
        "rzig.internal.unwind.protect: body must have signature fn(" ++
            @typeName(StatePointer) ++ ") c.SEXP",
    );
    if (body_info.params.len != 1 or
        body_info.params[0].type == null or body_info.params[0].type.? != StatePointer or
        body_info.return_type == null or body_info.return_type.? != c.SEXP)
    {
        @compileError(
            "rzig.internal.unwind.protect: body must have signature fn(" ++
                @typeName(StatePointer) ++ ") c.SEXP",
        );
    }

    const Cleanup = @TypeOf(cleanup);
    const cleanup_info = functionInfo(
        Cleanup,
        "rzig.internal.unwind.protect: cleanup must have signature fn(" ++
            @typeName(StatePointer) ++ ", bool) void",
    );
    if (cleanup_info.params.len != 2 or
        cleanup_info.params[0].type == null or cleanup_info.params[0].type.? != StatePointer or
        cleanup_info.params[1].type == null or cleanup_info.params[1].type.? != bool or
        cleanup_info.return_type == null or cleanup_info.return_type.? != void)
    {
        @compileError(
            "rzig.internal.unwind.protect: cleanup must have signature fn(" ++
                @typeName(StatePointer) ++ ", bool) void",
        );
    }
}

fn CallbackAdapter(
    comptime StatePointer: type,
    comptime body: anytype,
    comptime cleanup: anytype,
) type {
    return struct {
        fn run(data: ?*anyopaque) callconv(.c) c.SEXP {
            const state: StatePointer = @ptrCast(@alignCast(data.?));
            return body(state);
        }

        fn clean(data: ?*anyopaque, jump: c.Rboolean) callconv(.c) void {
            const state: StatePointer = @ptrCast(@alignCast(data.?));
            cleanup(state, jump != c.FALSE);
        }
    };
}

fn functionInfo(comptime Function: type, comptime message: []const u8) std.builtin.Type.Fn {
    return switch (@typeInfo(Function)) {
        .@"fn" => |info| info,
        else => @compileError(message),
    };
}
