//! Registration: manifest -> R_CallMethodDef table -> rzig_init.
//!
//! Zig cannot synthesise function bodies with a comptime parameter count, so
//! fixed-arity wrappers are generated in src/generated/arity.zig.

const std = @import("std");
const c = @import("c/abi.zig");
const arity = @import("generated/arity.zig");

/// Scan a module's manifest and emit one C-ABI wrapper per exported function,
/// plus the registration table.
pub fn registerModule(comptime M: type) void {
    _ = M;
    // TODO:
    //   const manifest = @import("generated/manifest.zig");
    //   comptime var defs: [manifest.exports.len + 1]c.R_CallMethodDef = undefined;
    //   inline for (manifest.exports, 0..) |e, i| {
    //       const info = @typeInfo(@TypeOf(e.func)).@"fn";
    //       const takes_ctx = info.params.len > 0 and info.params[0].type == *Ctx;
    //       const n = info.params.len - @intFromBool(takes_ctx);
    //       const W = switch (n) {
    //           0 => arity.Arity0(e.func, e.name),
    //           1 => arity.Arity1(e.func, e.name),
    //           ...
    //           else => @compileError("rzig: " ++ e.name ++ " has " ++ n ++
    //               " parameters; the maximum is 32. Pass a list instead."),
    //       };
    //       @export(&W.call, .{ .name = e.name, .linkage = .strong });
    //       defs[i] = .{ .name = e.name, .fun = @ptrCast(&W.call), .numArgs = n };
    //   }
    //   defs[manifest.exports.len] = .{ .name = null, .fun = null, .numArgs = 0 };
}

/// Called from the generated entry.c. Registration order matters: register,
/// then disable dynamic symbol lookup, then force symbol objects.
export fn rzig_init(dll: *c.DllInfo) callconv(.c) void {
    // TODO: register the generated routine table.
    _ = c.R_registerRoutines(dll, null, null, null, null);
    _ = c.R_useDynamicSymbols(dll, c.FALSE);
    _ = c.R_forceSymbols(dll, c.TRUE);
}
