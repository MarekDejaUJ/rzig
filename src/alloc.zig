//! Per-call context. This is deliberately not backed by R_alloc.
//!
//! Short version: R_alloc signals an R error on failure instead of returning
//! null, which violates std.mem.Allocator's contract and would make every `try`
//! in the codebase a hidden longjmp past Zig `defer` blocks.

const std = @import("std");
const es = @import("error_state.zig");

pub const Ctx = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init() Ctx {
        return .{ .arena = std.heap.ArenaAllocator.init(std.heap.c_allocator) };
    }

    pub fn deinit(self: *Ctx) void {
        self.arena.deinit();
    }

    pub fn allocator(self: *Ctx) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Allocate scratch or result memory. Result slices are copied into fresh R
    /// memory by the boundary before this arena is released, so ownership never
    /// crosses the boundary.
    pub fn alloc(self: *Ctx, comptime T: type, n: usize) es.Error![]T {
        return self.allocator().alloc(T, n) catch
            es.raise("out of memory allocating {d} elements", .{n});
    }

    pub fn dupe(self: *Ctx, comptime T: type, src: []const T) es.Error![]T {
        return self.allocator().dupe(T, src) catch
            es.raise("out of memory copying {d} elements", .{src.len});
    }
};

test "arena frees on deinit" {
    var ctx = Ctx.init();
    defer ctx.deinit();
    const s = try ctx.alloc(f64, 128);
    try std.testing.expectEqual(@as(usize, 128), s.len);
}
