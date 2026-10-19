//! Zig values owned by R objects (external pointers), kept across calls.
//!
//! A value lives in memory from the C allocator, preceded by nothing R can
//! see. The R object is an external pointer whose tag is a symbol naming the
//! Zig type and the address of a variable of this shared library for that
//! type, so an external pointer of another type or another package is
//! recognized before its memory is read. R's garbage collector runs the
//! finalizer, which calls `deinit` when the type declares one and releases
//! the memory, on the R thread.

const std = @import("std");
const compat = @import("compat.zig");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const Ctx = @import("alloc.zig").Ctx;

/// A Zig value of type `T` owned by an R object. As a result, `create`
/// moves a value into memory the returned R object owns; as an input, `ptr`
/// points to that value, which the function may read and modify. The R
/// object has the classes `c("<T>", "rzig_external")`. An external pointer
/// saved with `saveRDS()` or in a workspace loses its value; using it is an
/// error. `T.deinit(self: *T)`, when declared, must not call R.
pub fn External(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const rzig_external_inner = T;

        /// The value, valid while the R object is reachable.
        ptr: *T,

        /// Move `value` into memory owned by the R object this call returns.
        /// If the call ends with an error, the call context releases the value.
        pub fn create(ctx: *Ctx, value: T) es.Error!Self {
            const holder = std.heap.c_allocator.create(Holder(T)) catch
                return es.raise("rzig: out of memory creating a " ++ shortName(T), .{});
            holder.* = .{ .value = value };
            ctx.trackExternal(holder, Holder(T).destroyErased) catch {
                holder.destroy();
                return es.raise("rzig: out of memory creating a " ++ shortName(T), .{});
            };
            return .{ .ptr = &holder.value };
        }
    };
}

/// Report whether `T` is created by `External`.
pub fn isExternal(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "rzig_external_inner"),
        else => false,
    };
}

pub fn Holder(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,

        /// One variable per type and shared library; its address identifies
        /// the external pointers this library made for `T`.
        var identity: u8 = 0;

        pub fn destroy(self: *Self) void {
            if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "deinit")) self.value.deinit();
            std.heap.c_allocator.destroy(self);
        }

        pub fn destroyErased(pointer: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(pointer));
            self.destroy();
        }

        pub fn finalize(object: c.SEXP) callconv(.c) void {
            const address = c.R_ExternalPtrAddr(object) orelse return;
            c.R_ClearExternalPtr(object);
            const self: *Self = @ptrCast(@alignCast(address));
            self.destroy();
        }

        /// The tag symbol of this library's external pointers for `T`.
        pub fn tag() c.SEXP {
            var buffer: [512]u8 = undefined;
            const name = compat.bufPrintZ(&buffer, "rzig_external:{s}:{x}", .{
                @typeName(T)[0..@min(@typeName(T).len, 400)],
                @intFromPtr(&identity),
            }) catch unreachable;
            return c.Rf_install(name.ptr);
        }
    };
}

/// The last component of the type's name, used as its R class.
pub fn shortName(comptime T: type) []const u8 {
    const full = @typeName(T);
    const base = if (std.mem.indexOfScalar(u8, full, '(')) |open| full[0..open] else full;
    return if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| base[dot + 1 ..] else base;
}

test "short names drop the namespace" {
    const Model = struct { x: f64 };
    try std.testing.expect(std.mem.endsWith(u8, @typeName(Model), "Model"));
    try std.testing.expect(std.mem.indexOfScalar(u8, shortName(Model), '.') == null);
    try std.testing.expectEqualStrings("u8", shortName(u8));
}
