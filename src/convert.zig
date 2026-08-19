//! Conversion between borrowed R values and Zig values.
//!
//! Everything here can allocate on the R side, so everything here can trigger
//! GC. Protect immediately after every allocation.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const na = @import("na.zig");
const protect = @import("protect.zig");
const Ctx = @import("alloc.zig").Ctx;

/// Opt-in mutable input. The wrapper duplicates the incoming SEXP first,
/// because R vectors are copy-on-modify and may be shared.
pub fn Mut(comptime T: type) type {
    return struct {
        pub const rzig_mut_inner = T;
        data: T,
    };
}

/// SEXP -> Zig. `pos` is the zero-based parameter index and `name` its
/// identifier, both used only to build a good error message.
pub fn fromSexp(
    comptime T: type,
    ctx: *Ctx,
    x: c.SEXP,
    comptime name: []const u8,
) es.Error!T {
    _ = ctx;
    _ = x;
    return switch (@typeInfo(T)) {
        // TODO: scalars, slices, optionals and strings.
        else => @compileError(unsupportedMessage(T, name)),
    };
}

/// Zig -> SEXP. Pushes onto `stack` immediately after allocating.
pub fn toSexp(
    stack: *protect.Stack,
    ctx: *Ctx,
    value: anytype,
) es.Error!c.SEXP {
    _ = stack;
    _ = ctx;
    _ = value;
    // TODO: marshal supported Zig return types.
    return c.R_NilValue;
}

/// Compile-error text. Message quality is a first-class feature here - it is
/// most of what RZig offers over hand-written glue. Always name the parameter,
/// the type, the supported set, and the likely intended alternative.
fn unsupportedMessage(comptime T: type, comptime name: []const u8) []const u8 {
    return "rzig: parameter `" ++ name ++ "` has unsupported type '" ++ @typeName(T) ++ "'.\n" ++
        "  supported: f64, i32, bool, usize, ?T,\n" ++
        "             []const f64, []const i32, []const bool, []const u8, []const []const u8,\n" ++
        "             rzig.Sexp (escape hatch)\n" ++
        "  for a mutable vector use rzig.Mut([]f64)\n" ++
        "  note []f64 is NOT accepted as an input: R inputs are borrowed and read-only";
}

/// Human-readable R type name, for runtime error messages. Never say "SEXP" or
/// "REALSXP" to an R user.
pub fn typeName(x: c.SEXP) []const u8 {
    return std.mem.span(c.Rf_type2char(c.TYPEOF(x)));
}
