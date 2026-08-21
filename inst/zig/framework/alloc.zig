//! Per-call context. This is deliberately not backed by R_alloc.
//!
//! Short version: R_alloc signals an R error on failure instead of returning
//! null, which violates std.mem.Allocator's contract and would make every `try`
//! in the codebase a hidden longjmp past Zig `defer` blocks.

const std = @import("std");
const es = @import("error_state.zig");
const rng_api = @import("rng.zig");

/// Per-call storage for Zig-owned scratch memory and intermediate results.
///
/// The outer boundary creates one context for each R call and releases it after
/// conversion has copied the result into R-owned memory.
pub const Ctx = struct {
    arena: std.heap.ArenaAllocator,
    rng_active: bool,

    /// Create an empty context backed by Zig's C allocator.
    pub fn init() Ctx {
        return .{
            .arena = std.heap.ArenaAllocator.init(std.heap.c_allocator),
            .rng_active = false,
        };
    }

    /// Release every allocation owned by this context.
    pub fn deinit(self: *Ctx) void {
        self.arena.deinit();
    }

    /// Return the arena allocator for advanced Zig-only operations.
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

    /// Copy a slice into memory owned by this context.
    pub fn dupe(self: *Ctx, comptime T: type, src: []const T) es.Error![]T {
        return self.allocator().dupe(T, src) catch
            es.raise("out of memory copying {d} elements", .{src.len});
    }

    /// Enter R's random-number stream for reproducible draws under `set.seed()`.
    /// Repeated calls during one exported invocation reuse the same RNG state.
    pub fn rng(self: *Ctx) es.Error!rng_api.Rng {
        return rng_api.begin(&self.rng_active);
    }
};

test "context serves multiple allocations from one arena" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const reals = try ctx.alloc(f64, 128);
    const integers = try ctx.alloc(i32, 64);
    try std.testing.expectEqual(@as(usize, 128), reals.len);
    try std.testing.expectEqual(@as(usize, 64), integers.len);
}

test "dupe creates an independent context-owned copy" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const source = [_]i32{ 2, 3, 5, 7 };
    const copy = try ctx.dupe(i32, &source);
    copy[0] = 11;
    try std.testing.expectEqualSlices(i32, &.{ 11, 3, 5, 7 }, copy);
    try std.testing.expectEqual(@as(i32, 2), source[0]);
}
