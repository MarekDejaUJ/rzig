//! THE BOUNDARY. The only ordinary control-flow code permitted to call
//! Rf_error, Rf_warning, or Rf_errorcall. `zig build lint` enforces that.
//!
//! R implements errors with longjmp, which skips Zig `defer`. The ordering in
//! `invoke` is therefore part of the public safety contract:
//!
//!   1. Reset message state and initialise Ctx and the protection stack.
//!   2. Enter R_UnwindProtect so R-side longjmp always releases Ctx.
//!   3. Type-check and unmarshal every R argument without signalling an error.
//!   4. Call the user function, collecting an Error value instead of longjmp.
//!   5. Marshal the result and protect each R allocation immediately.
//!   6. Let the unwind cleanup release every Zig-owned allocation.
//!   7. On failure, unprotect and signal once. On success, emit warnings while
//!      the result is protected, then unprotect and return it.
//!
//! Steps 6 and 7 are ordered, never interleaved. Do not simplify this. The R
//! protection stack is intentionally released after warnings: Rf_warning can
//! allocate, and the return value must remain reachable until the final R call.

const std = @import("std");
const c = @import("c/abi.zig");
const protect = @import("protect.zig");
const convert = @import("convert.zig");
const es = @import("error_state.zig");
const Ctx = @import("alloc.zig").Ctx;

/// Entry point used by every generated fixed-arity wrapper.
///
/// `sexps` is a tuple of `c.SEXP` with one element per user-visible parameter.
/// An optional leading `*Ctx` parameter is supplied by RZig, not by R.
pub fn invoke(
    comptime func: anytype,
    comptime name: []const u8,
    sexps: anytype,
) c.SEXP {
    es.reset();

    const State = InvocationState(func, name, @TypeOf(sexps));
    var state = State{
        .ctx = Ctx.init(),
        .stack = protect.Stack.init(),
        .sexps = sexps,
    };

    // R invokes cleanup on both ordinary return and non-local transfer. Passing
    // a C NULL continuation asks R to resume any longjmp after cleanup.
    const result = c.R_UnwindProtect(
        &State.run,
        @ptrCast(&state),
        &State.cleanup,
        @ptrCast(&state),
        null,
    );
    std.debug.assert(state.cleaned);

    if (state.failed) {
        state.stack.unwindAll();
        state.stack.deinit();
        const recorded = es.take();
        const message: [:0]const u8 = if (recorded.len > 0)
            recorded
        else
            name ++ " failed without an error message";

        // This is the one ordinary error exit in the project. No Zig-owned
        // allocation or cleanup remains live when R performs its longjmp.
        c.Rf_errorcall(c.R_NilValue, "%s", message.ptr);
    }

    // The arena has already been released, but the result stays protected
    // because warning delivery can allocate or become an R error.
    while (es.takeWarning()) |warning| c.Rf_warning("%s", warning.ptr);

    state.stack.unwindAll();
    state.stack.deinit();
    return result;
}

/// Validate an exported function while its name, parameter positions and Zig
/// types are all available, producing diagnostics intended for package authors.
pub fn validateSignature(comptime func: anytype, comptime name: []const u8) void {
    const Func = @TypeOf(func);
    const info = functionInfo(Func);
    const has_ctx = comptime takesContext(Func);

    inline for (@intFromBool(has_ctx)..info.params.len) |parameter_index| {
        const position = parameter_index - @intFromBool(has_ctx) + 1;
        const Parameter = info.params[parameter_index].type orelse @compileError(
            "rzig: function `" ++ name ++ "`, parameter " ++
                std.fmt.comptimePrint("{d}", .{position}) ++
                " uses anytype and cannot be exported.\n" ++
                "  use a concrete supported type",
        );
        convert.validateInputType(Parameter, name, position);
    }

    const Return = info.return_type orelse
        @compileError("rzig: function `" ++ name ++ "` must declare a return type");
    if (@typeInfo(Return) == .error_union and @typeInfo(Return).error_union.error_set != es.Error) {
        @compileError(
            "rzig: function `" ++ name ++ "` must return rzig.Error!T, not " ++ @typeName(Return),
        );
    }
    convert.validateReturnType(ReturnPayload(Func), name);
}

fn InvocationState(
    comptime func: anytype,
    comptime name: []const u8,
    comptime Sexps: type,
) type {
    return struct {
        const Self = @This();

        ctx: Ctx,
        stack: protect.Stack,
        sexps: Sexps,
        failed: bool = false,
        cleaned: bool = false,

        fn run(data: ?*anyopaque) callconv(.c) c.SEXP {
            const self: *Self = @ptrCast(@alignCast(data.?));
            return callAndMarshal(func, name, self.sexps, &self.ctx, &self.stack) catch {
                self.failed = true;
                return c.R_NilValue;
            };
        }

        fn cleanup(data: ?*anyopaque, jump: c.Rboolean) callconv(.c) void {
            const self: *Self = @ptrCast(@alignCast(data.?));
            self.ctx.deinit();
            self.cleaned = true;
            _ = jump;
        }
    };
}

fn callAndMarshal(
    comptime func: anytype,
    comptime name: []const u8,
    sexps: anytype,
    ctx: *Ctx,
    stack: *protect.Stack,
) es.Error!c.SEXP {
    const value = try callUser(func, name, sexps, ctx);
    return convert.toSexp(stack, ctx, value);
}

fn callUser(
    comptime func: anytype,
    comptime name: []const u8,
    sexps: anytype,
    ctx: *Ctx,
) es.Error!ReturnPayload(@TypeOf(func)) {
    const Func = @TypeOf(func);
    comptime validateSignature(func, name);
    const info = functionInfo(Func);
    const has_ctx = comptime takesContext(Func);
    const supplied = comptime tupleLength(@TypeOf(sexps));
    const expected = info.params.len - @intFromBool(has_ctx);
    if (supplied != expected) {
        @compileError(std.fmt.comptimePrint(
            "rzig: function `{s}` expects {d} R arguments, but its wrapper supplies {d}",
            .{ name, expected, supplied },
        ));
    }

    var args: std.meta.ArgsTuple(Func) = undefined;
    if (comptime has_ctx) args[0] = ctx;

    inline for (0..supplied) |visible_index| {
        const parameter_index = visible_index + @intFromBool(has_ctx);
        const Parameter = info.params[parameter_index].type orelse @compileError(
            "rzig: function `" ++ name ++ "` has a generic parameter that cannot be exported",
        );
        const parameter_name = std.fmt.comptimePrint(
            "argument {d} of `{s}`",
            .{ visible_index + 1, name },
        );
        args[parameter_index] = try convert.fromSexp(
            Parameter,
            ctx,
            sexps[visible_index],
            parameter_name,
        );
    }

    return @call(.auto, func, args);
}

fn functionInfo(comptime Func: type) std.builtin.Type.Fn {
    return switch (@typeInfo(Func)) {
        .@"fn" => |info| info,
        else => @compileError("rzig: only functions can be exported, found " ++ @typeName(Func)),
    };
}

fn takesContext(comptime Func: type) bool {
    const params = functionInfo(Func).params;
    return params.len > 0 and params[0].type != null and params[0].type.? == *Ctx;
}

fn ReturnPayload(comptime Func: type) type {
    const Return = functionInfo(Func).return_type orelse
        @compileError("rzig: exported functions must declare a return type");
    return switch (@typeInfo(Return)) {
        .error_union => |info| info.payload,
        else => Return,
    };
}

fn tupleLength(comptime Tuple: type) usize {
    return switch (@typeInfo(Tuple)) {
        .@"struct" => |info| if (info.is_tuple)
            info.fields.len
        else
            @compileError("rzig: generated wrappers must pass arguments as a tuple"),
        else => @compileError("rzig: generated wrappers must pass arguments as a tuple"),
    };
}

fn testPlain() i32 {
    return 17;
}

fn testWithContext(ctx: *Ctx) es.Error!i32 {
    const values = try ctx.alloc(u8, 3);
    return @intCast(values.len);
}

fn testSupportedSignature(ctx: *Ctx, value: f64, labels: []const []const u8) es.Error!?f64 {
    _ = ctx;
    _ = value;
    _ = labels;
    return null;
}

test "user calls accept plain and context-aware signatures" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    try std.testing.expectEqual(@as(i32, 17), try callUser(testPlain, "test_plain", .{}, &ctx));
    try std.testing.expectEqual(@as(i32, 3), try callUser(testWithContext, "test_ctx", .{}, &ctx));
}

test "signature validation accepts context, supported inputs, and optional output" {
    comptime validateSignature(testSupportedSignature, "supported_signature");
}

test "the R unwind callback path instantiates" {
    const State = InvocationState(testPlain, "test_plain", @TypeOf(.{}));
    std.testing.refAllDecls(State);
    const Wrapper = struct {
        fn call() c.SEXP {
            return invoke(testPlain, "test_plain", .{});
        }
    };
    std.testing.refAllDecls(Wrapper);
}
