//! Per-call context. This is deliberately not backed by R_alloc.
//!
//! Short version: R_alloc signals an R error on failure instead of returning
//! null, which violates std.mem.Allocator's contract and would make every `try`
//! in the codebase a hidden longjmp past Zig `defer` blocks.

const std = @import("std");
const es = @import("error_state.zig");
const io = @import("io.zig");
const progress_api = @import("progress.zig");
const rng_api = @import("rng.zig");
const matrix_api = @import("matrix.zig");

/// Per-call storage for Zig-owned scratch memory and intermediate results.
///
/// The outer boundary creates one context for each R call and releases it after
/// conversion has copied the result into R-owned memory.
pub const Ctx = struct {
    arena: std.heap.ArenaAllocator,
    rng_active: bool,
    externals: std.ArrayList(ExternalEntry),
    /// R objects that stay allocated until the call ends (results of
    /// rzig.Function calls), a spare continuation token of R_UnwindProtect,
    /// and the function that releases them; this file calls no R function.
    r_objects: std.ArrayList(*anyopaque),
    spare_token: ?*anyopaque,
    release_r_object: ?*const fn (*anyopaque) void,

    /// Create an empty context backed by Zig's C allocator.
    pub fn init() Ctx {
        return .{
            .arena = std.heap.ArenaAllocator.init(std.heap.c_allocator),
            .rng_active = false,
            .externals = .empty,
            .r_objects = .empty,
            .spare_token = null,
            .release_r_object = null,
        };
    }

    /// Release every allocation owned by this context, including the values of
    /// `rzig.External` created during the call that no R object owns.
    pub fn deinit(self: *Ctx) void {
        for (self.externals.items) |entry| {
            if (entry.destroy) |destroy| destroy(entry.holder);
        }
        if (self.release_r_object) |release| {
            var index = self.r_objects.items.len;
            while (index > 0) {
                index -= 1;
                release(self.r_objects.items[index]);
            }
            if (self.spare_token) |token| release(token);
            self.spare_token = null;
        }
        self.arena.deinit();
    }

    /// Internal (rzig.External): the call owns `holder` until R does.
    pub fn trackExternal(self: *Ctx, holder: *anyopaque, destroy: *const fn (*anyopaque) void) error{OutOfMemory}!void {
        try self.externals.append(self.arena.allocator(), .{ .holder = holder, .destroy = destroy, .object = null });
    }

    /// Internal (rzig.External): hand `holder` to an R object; false when the
    /// call does not own it.
    pub fn releaseExternal(self: *Ctx, holder: *anyopaque) bool {
        for (self.externals.items) |*entry| {
            if (entry.holder == holder and entry.destroy != null) {
                entry.destroy = null;
                return true;
            }
        }
        return false;
    }

    /// Internal (rzig.External): remember the R object of an input value.
    pub fn noteExternalInput(self: *Ctx, holder: *anyopaque, object: *anyopaque) error{OutOfMemory}!void {
        try self.externals.append(self.arena.allocator(), .{ .holder = holder, .destroy = null, .object = object });
    }

    /// Internal (rzig.External): the R object an input value came from.
    pub fn externalObject(self: *Ctx, holder: *anyopaque) ?*anyopaque {
        for (self.externals.items) |entry| {
            if (entry.holder == holder) return entry.object;
        }
        return null;
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

    /// A zero-filled `nrow` x `ncol` double matrix in memory owned by this
    /// context, for example as the result of `rzig.Blas.gemm`.
    pub fn matrix(self: *Ctx, nrow: usize, ncol: usize) es.Error!matrix_api.MutableMatrixOf(f64) {
        const count = std.math.mul(usize, nrow, ncol) catch
            return es.raise("out of memory allocating a {d} x {d} matrix", .{ nrow, ncol });
        const data = try self.alloc(f64, count);
        @memset(data, 0);
        return .{ .data = data, .nrow = nrow, .ncol = ncol };
    }

    /// Copy a slice into memory owned by this context.
    pub fn dupe(self: *Ctx, comptime T: type, src: []const T) es.Error![]T {
        return self.allocator().dupe(T, src) catch
            es.raise("out of memory copying {d} elements", .{src.len});
    }

    /// Random streams for `rzig.parallelFor` workers, seeded with two draws
    /// from R's stream, so they follow `set.seed()`.
    pub fn rngStreams(self: *Ctx) es.Error!rng_api.Streams {
        const generator = try self.rng();
        const high: u64 = @intFromFloat(@floor(generator.uniform() * 4294967296.0));
        const low: u64 = @intFromFloat(@floor(generator.uniform() * 4294967296.0));
        return .{ .seed = (high << 32) | low };
    }

    /// Enter R's random-number stream for reproducible draws under `set.seed()`.
    /// Repeated calls during one exported invocation reuse the same RNG state.
    pub fn rng(self: *Ctx) es.Error!rng_api.Rng {
        return rng_api.begin(&self.rng_active);
    }

    /// Print formatted text to R's standard output, as `Rprintf` does, so it
    /// reaches the console, RStudio and `sink()`. A user interrupt that R
    /// notices while printing ends the call with an R interrupt.
    pub fn print(self: *Ctx, comptime format: []const u8, args: anytype) es.Error!void {
        _ = self;
        return io.print(.out, format, args);
    }

    /// Print formatted text to R's message stream, as `REprintf` does.
    pub fn eprint(self: *Ctx, comptime format: []const u8, args: anytype) es.Error!void {
        _ = self;
        return io.print(.err, format, args);
    }

    /// A progress bar for `total` steps on R's message stream, drawn only when
    /// `show` is true; its updates also check for a user interrupt.
    pub fn progress(self: *Ctx, total: usize, show: bool) progress_api.Progress {
        _ = self;
        return progress_api.Progress.init(total, show);
    }
};

/// A value of `rzig.External` that a call created or received.
const ExternalEntry = struct {
    holder: *anyopaque,
    /// Set while the call owns the value; null once an R object owns it.
    destroy: ?*const fn (*anyopaque) void,
    /// The R object of an input value.
    object: ?*anyopaque,
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
