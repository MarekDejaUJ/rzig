//! Registration: manifest -> R_CallMethodDef table -> rzig_init.
//!
//! Zig cannot synthesise function bodies with a comptime parameter count, so
//! fixed-arity wrappers are generated in src/generated/arity.zig.

const std = @import("std");
const compat = @import("compat.zig");
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
    comptime parameters: anytype,
) type {
    return arity.Wrapper(visible_arity, func, name, parameters);
}

/// The R argument names of a manifest entry, or an empty tuple for a
/// hand-written manifest without them.
fn entryParameters(comptime entry: anytype) @TypeOf(if (@hasField(@TypeOf(entry), "parameters")) entry.parameters else .{}) {
    return if (@hasField(@TypeOf(entry), "parameters")) entry.parameters else .{};
}

/// Scan a module's manifest and build one C-ABI wrapper per exported function,
/// plus the registration table.
///
/// The wrappers are reached only through the registration table, so none of
/// them becomes a symbol of the shared object. A wrapper exported under its R
/// name would replace a C function of the same name inside the package (an
/// export named `exp`, `log` or `free` would intercept the calls the framework
/// and the C runtime make to those functions). `rzig_init` is called from the
/// generated `entry.c` of the same package and is therefore hidden as well.
pub fn registerModule(comptime M: type) void {
    const exports = if (@hasDecl(manifest, "Bind"))
        manifest.Bind(M).exports
    else if (@hasDecl(manifest, "exports"))
        manifest.exports
    else
        @compileError("rzig: generated manifest must declare Bind(root) or exports");
    const Registration = RegistrationFor(exports);

    if (!builtin.is_test) {
        @export(&Registration.init, .{
            .name = "rzig_init",
            .linkage = .strong,
            .visibility = .hidden,
        });
        @export(&Registration.registerWith, .{
            .name = "rzig_register",
            .linkage = .strong,
            .visibility = .hidden,
        });
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

        /// Called from the package's own R_init_<pkg> in a package with C,
        /// C++ or Fortran sources (Config/rzig/mixed): registers the
        /// package's routines and the Zig routines together. R copies the
        /// tables, so the merged one is released afterwards.
        fn registerWith(
            dll: *c.DllInfo,
            c_methods: ?[*]const c.R_CMethodDef,
            package_call_methods: ?[*]const c.R_CallMethodDef,
            fortran_methods: ?[*]const c.R_FortranMethodDef,
            external_methods: ?[*]const c.R_ExternalMethodDef,
        ) callconv(.c) void {
            if (builtin.is_test) return;
            var count: usize = 0;
            if (package_call_methods) |methods| {
                while (methods[count].name != null) count += 1;
            }
            const zig_count = call_methods.len - 1;
            const merged = std.heap.c_allocator.alloc(c.R_CallMethodDef, zig_count + count + 1) catch {
                c.REprintf("rzig: not enough memory to register the native routines\n");
                return;
            };
            defer std.heap.c_allocator.free(merged);
            @memcpy(merged[0..zig_count], call_methods[0..zig_count]);
            var length = zig_count;
            if (package_call_methods) |methods| {
                for (methods[0..count]) |method| {
                    if (isZigRoutine(method.name.?)) {
                        c.REprintf("rzig: the C routine %s has the name of a Zig export and is not registered\n", method.name.?);
                        continue;
                    }
                    merged[length] = method;
                    length += 1;
                }
            }
            merged[length] = .{ .name = null, .fun = null, .numArgs = 0 };
            _ = c.R_registerRoutines(dll, c_methods, merged.ptr, fortran_methods, external_methods);
            _ = c.R_useDynamicSymbols(dll, c.FALSE);
            // The R code of such a package may name its C routines by string.
            _ = c.R_forceSymbols(dll, c.FALSE);
        }

        fn isZigRoutine(name: [*:0]const u8) bool {
            const text = std.mem.span(name);
            inline for (exports) |entry| {
                if (std.mem.eql(u8, text, entry.name)) return true;
            }
            return false;
        }
    };
}

fn buildCallMethods(comptime exports: anytype) [exports.len + 1]c.R_CallMethodDef {
    @setEvalBranchQuota(100_000);
    var definitions: [exports.len + 1]c.R_CallMethodDef = undefined;
    inline for (exports, 0..) |entry, index| {
        comptime boundary.validateSignature(entry.func, entry.name);
        const visible_arity = visibleArity(entry.func);
        definitions[index] = .{
            .name = entry.name,
            .fun = if (builtin.is_test) null else wrapper: {
                const Wrapper = wrapperForArity(visible_arity, entry.func, entry.name, entryParameters(entry));
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
        .@"fn" => |info| compat.paramCount(info) - @intFromBool(
            compat.paramCount(info) > 0 and
                compat.paramType(info, 0) != null and
                compat.paramType(info, 0).? == *Ctx,
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
