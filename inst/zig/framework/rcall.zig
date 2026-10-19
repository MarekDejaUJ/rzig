//! Calls of R functions from Zig, and the jumps of R stopped before Zig frames.
//!
//! R leaves R code by longjmp when the code signals an error, when an interrupt
//! arrives, and when a condition handler or a restart outside the code takes
//! control. A longjmp would skip the deferred cleanup of the Zig frames it
//! crosses, so rzig evaluates R code that can run user code only through
//! `rzig_unwind_run()` (src/entry.c of the package): a jump out of the R code
//! stops there, the evaluation returns `error.RZigError`, the Zig frames return
//! normally, and the boundary resumes the jump with R_ContinueUnwind() once no
//! Zig frame of the call is left. The jump then reaches its target as it
//! would have without Zig in between: the condition keeps its class and call,
//! handlers outside the call run, and `traceback()` shows the R frames.

const std = @import("std");
const c = @import("c/abi.zig");
const compat = @import("compat.zig");
const es = @import("error_state.zig");
const Ctx = @import("alloc.zig").Ctx;
const convert = @import("convert.zig");
const complex = @import("complex.zig");
const matrix = @import("matrix.zig");
const protect = @import("protect.zig");
const panic = @import("panic.zig");
const boundary = @import("boundary.zig");

extern fn rzig_unwind_run(
    body: *const fn (?*anyopaque) callconv(.c) c.SEXP,
    data: ?*anyopaque,
    token: c.SEXP,
    result: *c.SEXP,
) c_int;

/// An R function (a closure, a builtin or a special) received as an argument
/// of an exported function. It is valid until the exported function returns.
pub const Function = struct {
    object: c.SEXP,
    /// The name of the function in the calls that R shows in messages and
    /// in `traceback()`: the name of the R argument, or `FUN`.
    name: [:0]const u8,

    /// Call the function and convert its result to `T`.
    ///
    /// `args` is a tuple of positional arguments, `.{ x, 2.0 }`, or a struct
    /// of named arguments, `.{ .x = x, .@"na.rm" = true }`; each value has a
    /// type that an exported function can return (integer literals become R
    /// integers, float literals doubles, string literals strings). `T` is a
    /// type that an exported function accepts, or `void` to ignore the
    /// result; when `T` borrows R memory, the result stays allocated until
    /// the exported function returns. The call runs on the thread that
    /// entered R, in a new environment whose parent is the global environment
    /// and which binds `name` to the function. Warnings queued with
    /// `rzig.warn` are delivered first, and R's random-number state is handed
    /// over to R and back when `ctx.rng()` is in use.
    ///
    /// An R error, an interrupt, or the exit of a condition handler or a
    /// restart outside the call returns `error.RZigError`. Return the error:
    /// R continues the error or the exit when the exported function has
    /// returned. An exported function that handles the error and returns
    /// normally discards it, and one that raises another error with
    /// `rzig.raise` signals that error instead.
    pub fn call(self: Function, ctx: *Ctx, comptime T: type, args: anytype) es.Error!T {
        comptime validateCall(T, @TypeOf(args));
        if (!panic.onRThread()) @panic("rzig.Function.call runs only on the thread that entered R");
        const State = CallState(T, @TypeOf(args));
        var state = State{ .function = self, .ctx = ctx, .args = args };
        // R code can call exported functions of rzig packages, which start
        // from an empty error state; the state of this call waits here.
        var saved: es.Saved = .{};
        es.save(&saved);
        intercept(ctx, &state, State.run) catch |err| {
            dropSaved(&saved);
            return err;
        };
        if (state.failed) {
            dropSaved(&saved);
            return es.Error.RZigError;
        }
        es.restore(&saved);
        return state.value;
    }
};

/// The R name of an argument, from its conversion label ("argument `f` of g").
/// Call it at compile time.
pub fn callName(comptime label: []const u8) [:0]const u8 {
    const start = std.mem.indexOfScalar(u8, label, '`') orelse return "FUN";
    const rest = label[start + 1 ..];
    const end = std.mem.indexOfScalar(u8, rest, '`') orelse return "FUN";
    if (end == 0) return "FUN";
    return std.fmt.comptimePrint("{s}", .{rest[0..end]});
}

const result_label = "the result of the R function";

fn CallState(comptime T: type, comptime Args: type) type {
    return struct {
        const Self = @This();

        function: Function,
        ctx: *Ctx,
        args: Args,
        value: T = undefined,
        failed: bool = false,

        fn run(self: *Self) void {
            self.failed = !self.evaluate();
        }

        // R can leave this function at each R call; it holds only R's own
        // protection, which R releases on a jump.
        fn evaluate(self: *Self) bool {
            boundary.deliverWarnings();
            var stack = protect.Stack.init();
            defer stack.unwindAll();
            const arguments = buildArguments(&stack, self.ctx, self.args) catch return false;
            const symbol = c.Rf_install(self.function.name.ptr);
            const call_object = stack.push(c.Rf_lcons(symbol, arguments));
            const environment = stack.push(c.R_NewEnv(c.R_GlobalEnv, 0, 0));
            c.Rf_defineVar(symbol, self.function.object, environment);
            if (self.ctx.rng_active) c.PutRNGstate();
            const result = stack.push(c.Rf_eval(call_object, environment));
            if (self.ctx.rng_active) c.GetRNGstate();
            if (comptime T == void) return true;
            self.value = convert.fromSexp(T, self.ctx, result, result_label) catch {
                nameResult(self.function.name);
                return false;
            };
            if (comptime keepsResult(T)) keep(self.ctx, result) catch return false;
            return true;
        }
    };
}

fn ArgumentType(comptime F: type) type {
    return switch (@typeInfo(F)) {
        .comptime_int => i32,
        .comptime_float => f64,
        .pointer => |info| if (info.size == .one and @typeInfo(info.child) == .array)
            []const @typeInfo(info.child).array.child
        else
            F,
        else => F,
    };
}

fn validateCall(comptime T: type, comptime Args: type) void {
    if (T != void and (convert.isMutableInput(T) or T == *Ctx or !convert.supportsInput(T))) {
        @compileError("rzig.Function.call: the result type '" ++ @typeName(T) ++
            "' is not a type that exported functions accept; use void to ignore the result");
    }
    const info = switch (@typeInfo(Args)) {
        .@"struct" => |info| info,
        else => @compileError("rzig.Function.call: pass the arguments as a tuple, .{ x, y }, " ++
            "or as a struct of named arguments, .{ .x = x }"),
    };
    inline for (comptime compat.fieldTypes(info), 0..) |Field, index| {
        const Argument = ArgumentType(Field);
        if (!convert.supportsReturn(Argument) or Argument == void) {
            @compileError("rzig.Function.call: argument " ++ compat.fieldNames(info)[index] ++
                " has type '" ++ @typeName(Field) ++ "', which exported functions cannot return");
        }
    }
}

fn buildArguments(stack: *protect.Stack, ctx: *Ctx, args: anytype) es.Error!c.SEXP {
    const info = @typeInfo(@TypeOf(args)).@"struct";
    const names = comptime compat.fieldNames(info);
    var list: c.SEXP = c.R_NilValue;
    comptime var index = names.len;
    inline while (index > 0) {
        index -= 1;
        const value: ArgumentType(@TypeOf(@field(args, names[index]))) = @field(args, names[index]);
        const object = quoted(stack, try convert.toSexp(stack, ctx, value));
        list = stack.push(c.Rf_cons(object, list));
        if (comptime !info.is_tuple) c.SET_TAG(list, c.Rf_install(names[index].ptr));
    }
    return list;
}

/// Symbols, calls and promises would be evaluated as arguments; `quote()`
/// passes them as they are.
fn quoted(stack: *protect.Stack, object: c.SEXP) c.SEXP {
    const kind: c.SEXPTYPE = @intCast(c.TYPEOF(object));
    if (kind != c.SYMSXP and kind != c.LANGSXP and kind != c.PROMSXP and
        kind != c.DOTSXP and kind != c.BCODESXP) return object;
    const quote = c.Rf_findFun(c.Rf_install("quote"), c.R_BaseEnv);
    return stack.push(c.Rf_lang2(quote, object));
}

/// Results that the conversion copies into the call context need not stay
/// allocated.
fn keepsResult(comptime T: type) bool {
    const Inner = switch (@typeInfo(T)) {
        .optional => |info| info.child,
        else => T,
    };
    return !(Inner == f64 or Inner == i32 or Inner == bool or Inner == usize or Inner == i64 or
        Inner == complex.Complex or Inner == []const u8 or Inner == []const []const u8 or
        Inner == []const bool or Inner == []const ?[]const u8 or Inner == matrix.BoolMatrix);
}

/// Replace "the R function" in a conversion message with the function's name.
fn nameResult(name: []const u8) void {
    var copy: [1024]u8 = undefined;
    const message = es.take();
    const length = @min(message.len, copy.len);
    @memcpy(copy[0..length], message[0..length]);
    const text = copy[0..length];
    const placeholder = "the R function";
    if (std.mem.indexOf(u8, text, placeholder)) |at| {
        es.record("{s}`{s}`{s}", .{ text[0..at], name, text[at + placeholder.len ..] });
    } else {
        es.record("{s}", .{text});
    }
}

/// Keep `object` allocated until the exported function returns.
fn keep(ctx: *Ctx, object: c.SEXP) es.Error!void {
    c.R_PreserveObject(object);
    ctx.r_objects.append(ctx.allocator(), @ptrCast(object)) catch {
        c.R_ReleaseObject(object);
        return es.raise("rzig: out of memory", .{});
    };
    ctx.release_r_object = &releaseObject;
}

fn releaseObject(object: *anyopaque) void {
    c.R_ReleaseObject(@ptrCast(object));
}

/// Run `body(state)` and stop every jump of R out of it at this call.
///
/// When R jumps out of `body`, the jump is kept for the boundary and the call
/// returns `error.RZigError`; return that error, so that the Zig frames above
/// unwind before R resumes the jump. `body` must hold no resource across a
/// call of R other than R's protection, because R can leave it at any such
/// call. Not for code inside R_ToplevelExec, whose context ends before the
/// boundary could resume a jump to it.
pub fn intercept(ctx: *Ctx, state: anytype, comptime body: fn (@TypeOf(state)) void) es.Error!void {
    const State = @TypeOf(state);
    const Adapter = struct {
        fn run(data: ?*anyopaque) callconv(.c) c.SEXP {
            body(@as(State, @ptrCast(@alignCast(data.?))));
            return c.R_NilValue;
        }
    };
    const token = try takeToken(ctx);
    var result: c.SEXP = c.R_NilValue;
    if (rzig_unwind_run(&Adapter.run, state, token, &result) != 0) {
        recordJump(token);
        return es.Error.RZigError;
    }
    // R_UnwindProtect stored the result in the token.
    _ = c.SETCAR(token, c.R_NilValue);
    returnToken(ctx, token);
}

/// Resume a kept jump of R, unless another error replaced it. Only for the C
/// callbacks of R's routines (the optimizers, integration): the jump then
/// passes over the routine to the `intercept` around it, and no Zig frame in
/// between has cleanup.
pub fn resumeJump() void {
    const jump = es.takeJump() orelse return;
    c.R_ReleaseObject(@ptrCast(jump.token));
    if (!jump.superseded) c.R_ContinueUnwind(@ptrCast(jump.token));
}

/// Discard a kept jump of R.
pub fn dropJump() void {
    const jump = es.takeJump() orelse return;
    c.R_ReleaseObject(@ptrCast(jump.token));
}

fn recordJump(token: c.SEXP) void {
    // A later jump replaces an earlier one, as an error in an on.exit()
    // expression replaces the error that ran it.
    dropJump();
    es.noteJump(@ptrCast(token));
}

fn dropSaved(saved: *const es.Saved) void {
    if (saved.jump) |token| c.R_ReleaseObject(@ptrCast(token));
}

// A continuation token for R_UnwindProtect. A call keeps one spare token;
// nested intercepts use tokens of their own, and a token that holds a jump
// belongs to the error state until the boundary resumes the jump.
fn takeToken(ctx: *Ctx) es.Error!c.SEXP {
    if (ctx.spare_token) |token| {
        ctx.spare_token = null;
        return @ptrCast(token);
    }
    const Make = struct {
        token: ?c.SEXP = null,

        fn run(data: ?*anyopaque) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            const token = c.R_MakeUnwindCont();
            c.R_PreserveObject(token);
            self.token = token;
        }
    };
    var make = Make{};
    if (c.R_ToplevelExec(Make.run, &make) == c.FALSE or make.token == null) {
        return es.raise("rzig: unable to allocate the state for a call of R", .{});
    }
    ctx.release_r_object = &releaseObject;
    return make.token.?;
}

fn returnToken(ctx: *Ctx, token: c.SEXP) void {
    if (ctx.spare_token == null) {
        ctx.spare_token = @ptrCast(token);
    } else {
        c.R_ReleaseObject(token);
    }
}

test "call names come from the argument label" {
    try std.testing.expectEqualStrings("objective", comptime callName("argument `objective` of fit"));
    try std.testing.expectEqualStrings("FUN", comptime callName("argument 2 of fit"));
    try std.testing.expectEqualStrings("f", comptime callName("field `f` of argument `x` of g"));
}

test "argument types of literals" {
    try std.testing.expectEqual(i32, ArgumentType(comptime_int));
    try std.testing.expectEqual(f64, ArgumentType(comptime_float));
    try std.testing.expectEqual([]const u8, ArgumentType(@TypeOf("text")));
    try std.testing.expectEqual(f64, ArgumentType(f64));
    try std.testing.expect(!keepsResult(f64));
    try std.testing.expect(!keepsResult(?i32));
    try std.testing.expect(keepsResult([]const f64));
}
