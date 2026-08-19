//! Registration: manifest -> R_CallMethodDef table -> rzig_init.
//!
//! Zig cannot synthesise function bodies with a comptime parameter count, so
//! fixed-arity wrappers are generated in src/generated/arity.zig.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("c/abi.zig");
const arity = @import("generated/arity.zig");
const manifest = @import("generated/manifest.zig");
const boundary = @import("boundary.zig");
const Ctx = @import("alloc.zig").Ctx;

/// Select the fixed C-ABI wrapper for `visible_arity`, producing a focused
/// compile error when an exported function exceeds the supported limit.
pub fn wrapperForArity(
    comptime visible_arity: usize,
    comptime func: anytype,
    comptime name: []const u8,
) type {
    return arity.Wrapper(visible_arity, func, name);
}

/// Scan a module's manifest and emit one C-ABI wrapper per exported function,
/// plus the registration table.
pub fn registerModule(comptime M: type) void {
    const exports = if (@hasDecl(manifest, "Bind"))
        manifest.Bind(M).exports
    else if (@hasDecl(manifest, "exports"))
        manifest.exports
    else
        @compileError("rzig: generated manifest must declare Bind(root) or exports");
    const Registration = RegistrationFor(exports);

    if (!builtin.is_test) {
        inline for (exports) |entry| {
            const Wrapper = wrapperForArity(visibleArity(entry.func), entry.func, entry.name);
            @export(&Wrapper.call, .{ .name = entry.name, .linkage = .strong });
        }
        @export(&Registration.init, .{ .name = "rzig_init", .linkage = .strong });
    }
}

fn RegistrationFor(comptime exports: anytype) type {
    return struct {
        pub const call_methods = buildCallMethods(exports);

        /// Called from the generated entry.c. Registration order matters:
        /// register, disable dynamic lookup, then force symbol objects.
        fn init(dll: *c.DllInfo) callconv(.c) void {
            if (builtin.is_test) return;
            _ = c.R_registerRoutines(dll, null, &call_methods, null, null);
            _ = c.R_useDynamicSymbols(dll, c.FALSE);
            _ = c.R_forceSymbols(dll, c.TRUE);
        }
    };
}

fn buildCallMethods(comptime exports: anytype) [exports.len + 1]c.R_CallMethodDef {
    var definitions: [exports.len + 1]c.R_CallMethodDef = undefined;
    inline for (exports, 0..) |entry, index| {
        comptime boundary.validateSignature(entry.func, entry.name);
        const visible_arity = visibleArity(entry.func);
        definitions[index] = .{
            .name = entry.name,
            .fun = if (builtin.is_test) null else wrapper: {
                const Wrapper = wrapperForArity(visible_arity, entry.func, entry.name);
                break :wrapper @ptrCast(&Wrapper.call);
            },
            .numArgs = @intCast(visible_arity),
        };
    }
    definitions[exports.len] = .{ .name = null, .fun = null, .numArgs = 0 };
    return definitions;
}

fn visibleArity(comptime func: anytype) usize {
    return switch (@typeInfo(@TypeOf(func))) {
        .@"fn" => |info| info.params.len - @intFromBool(
            info.params.len > 0 and
                info.params[0].type != null and
                info.params[0].type.? == *Ctx,
        ),
        else => @compileError("rzig: only functions can be exported, found " ++ @typeName(@TypeOf(func))),
    };
}

fn testZero() i32 {
    return 0;
}

fn testTwo(left: i32, right: i32) i32 {
    return left + right;
}

fn testWithContext(ctx: *Ctx, value: i32) i32 {
    _ = ctx;
    return value;
}

test "registration table contains wrappers and a terminating sentinel" {
    const exports = .{
        .{ .name = "test_zero", .func = testZero, .doc = "Zero arguments." },
        .{ .name = "test_two", .func = testTwo, .doc = "Two arguments." },
        .{ .name = "test_context", .func = testWithContext, .doc = "Injected context." },
    };
    const Registration = RegistrationFor(exports);

    try std.testing.expectEqual(@as(usize, 4), Registration.call_methods.len);
    try std.testing.expectEqualStrings("test_zero", std.mem.span(Registration.call_methods[0].name.?));
    try std.testing.expectEqual(@as(c_int, 0), Registration.call_methods[0].numArgs);
    try std.testing.expectEqualStrings("test_two", std.mem.span(Registration.call_methods[1].name.?));
    try std.testing.expectEqual(@as(c_int, 2), Registration.call_methods[1].numArgs);
    try std.testing.expectEqualStrings("test_context", std.mem.span(Registration.call_methods[2].name.?));
    try std.testing.expectEqual(@as(c_int, 1), Registration.call_methods[2].numArgs);
    try std.testing.expectEqual(null, Registration.call_methods[3].name);
    try std.testing.expectEqual(null, Registration.call_methods[3].fun);
}
