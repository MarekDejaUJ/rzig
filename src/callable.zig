//! C-callable functions shared between R packages (R_RegisterCCallable).
//!
//! A package registers the functions of `pub const rzig_callables = .{ .name
//! = function, ... }` in its root Zig file when it loads, under its package
//! name; each function has `callconv(.c)`. Another package, in Zig or in C,
//! fetches one with `R_GetCCallable(package, name)`, which `callable` wraps.
//! R checks neither the signature nor a version, so a package that declares
//! `pub const rzig_interface_version: u32` registers it as well, and
//! `callable` compares it with the version the caller asks for.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const Ctx = @import("alloc.zig").Ctx;
const rcall = @import("rcall.zig");
const compat = @import("compat.zig");
const protect = @import("protect.zig");

/// The name under which the interface version is registered.
pub const interface_version_name = "rzig_interface_version";

pub const CallableOptions = struct {
    /// The interface version that the providing package must declare in
    /// `rzig_interface_version`; `null` skips the check.
    interface: ?u32 = null,
};

/// The C-callable function `name` of the R package `package`, as type `F`
/// (a function type with `callconv(.c)`). The namespace of `package` is
/// loaded first (R_GetCCallable does not load it); an R error (a package that
/// is not installed, a name it does not register) returns `error.RZigError`
/// and reaches R as it is.
pub fn callable(
    ctx: *Ctx,
    comptime F: type,
    package: [:0]const u8,
    name: [:0]const u8,
    options: CallableOptions,
) es.Error!*const F {
    comptime validate(F, "rzig.callable: the function type");
    const State = struct {
        package: [*:0]const u8,
        name: [*:0]const u8,
        check_version: bool,
        function: ?c.DL_FUNC = null,
        version: c_int = 0,

        fn run(self: *@This()) void {
            var stack = protect.Stack.init();
            defer stack.unwindAll();
            const load = stack.push(c.Rf_lang2(c.Rf_install("loadNamespace"), stack.push(c.Rf_mkString(self.package))));
            _ = c.Rf_eval(load, c.R_BaseEnv);
            self.function = c.R_GetCCallable(self.package, self.name);
            if (self.check_version) {
                const get: *const fn () callconv(.c) c_int = @ptrCast(c.R_GetCCallable(self.package, interface_version_name));
                self.version = get();
            }
        }
    };
    var state = State{ .package = package.ptr, .name = name.ptr, .check_version = options.interface != null };
    try rcall.intercept(ctx, &state, State.run);
    if (options.interface) |wanted| {
        if (state.version != @as(c_int, @intCast(wanted))) {
            return es.raise(
                "rzig: package {s} provides version {d} of its C-callable functions, and this package needs version {d}; " ++
                    "install versions of the two packages that agree",
                .{ package, state.version, wanted },
            );
        }
    }
    const function = state.function orelse return es.raise("rzig: package {s} registers no function {s}", .{ package, name });
    return @ptrCast(function);
}

/// `F` must be a function type with the C calling convention.
pub fn validate(comptime F: type, comptime what: []const u8) void {
    const info = switch (@typeInfo(F)) {
        .@"fn" => |info| info,
        else => @compileError(what ++ " '" ++ @typeName(F) ++ "' is not a function type"),
    };
    if (!compat.hasCCallingConvention(info)) {
        @compileError(what ++ " '" ++ @typeName(F) ++ "' needs callconv(.c)");
    }
}

fn plain(x: f64) callconv(.c) f64 {
    return x;
}

test "callable function types need the C calling convention" {
    comptime validate(@TypeOf(plain), "test");
    comptime validate(fn ([*]const f64, usize) callconv(.c) f64, "test");
}
