//! Parallel execution for pure Zig computation.
//!
//! The callback receives only a compile-time-validated plain-data state pointer
//! and an index. It never runs on the thread that entered R.

const std = @import("std");
const Ctx = @import("alloc.zig").Ctx;
const attributes = @import("attributes.zig");
const convert = @import("convert.zig");
const es = @import("error_state.zig");
const list = @import("list.zig");
const matrix = @import("matrix.zig");
const sexp = @import("sexp.zig");

const max_worker_threads = 32;
const max_state_depth = 8;

/// Run `worker(state, index)` once for every index in `[0, count)`.
///
/// `state` must be a single-item pointer to plain Zig data. R-facing types,
/// opaque pointers, function pointers, and error-bearing types are rejected at
/// compile time. The worker must return `void`, must not call RZig or R APIs,
/// and must not panic. Use atomics in `state` to report worker failures, then
/// call `raise` on the calling thread after `parallelFor` returns.
pub fn parallelFor(
    ctx: *Ctx,
    count: usize,
    state: anytype,
    comptime worker: anytype,
) es.Error!void {
    comptime validateWorker(@TypeOf(state), worker);

    if (count == 0) return;
    if (count == std.math.maxInt(usize)) {
        return es.raise("rzig: parallelFor item count exceeds its safe limit", .{});
    }

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const thread_count = @min(count, @min(cpu_count, max_worker_threads));
    const threads = try ctx.alloc(std.Thread, thread_count);
    const Runner = RunnerType(@TypeOf(state), worker);
    var runner = Runner{
        .next = std.atomic.Value(usize).init(0),
        .count = count,
        .state = state,
    };

    var spawned: usize = 0;
    while (spawned < thread_count) : (spawned += 1) {
        threads[spawned] = std.Thread.spawn(.{}, Runner.run, .{&runner}) catch {
            for (threads[0..spawned]) |thread| thread.join();
            return es.raise("rzig: unable to start a parallel worker", .{});
        };
    }
    for (threads[0..spawned]) |thread| thread.join();
}

fn RunnerType(comptime StatePointer: type, comptime worker: anytype) type {
    return struct {
        next: std.atomic.Value(usize),
        count: usize,
        state: StatePointer,

        fn run(self: *@This()) void {
            while (true) {
                const index = self.next.fetchAdd(1, .monotonic);
                if (index >= self.count) return;
                worker(self.state, index);
            }
        }
    };
}

/// Validate the callback contract while state and function types are available.
pub fn validateWorker(comptime StatePointer: type, comptime worker: anytype) void {
    const state_pointer = switch (@typeInfo(StatePointer)) {
        .pointer => |info| info,
        else => @compileError(
            "rzig.parallelFor: state must be a single-item pointer to plain Zig data",
        ),
    };
    if (state_pointer.size != .one) {
        @compileError(
            "rzig.parallelFor: state must be a single-item pointer to plain Zig data",
        );
    }
    validatePlainType(state_pointer.child, 0);

    const function = switch (@typeInfo(@TypeOf(worker))) {
        .@"fn" => |info| info,
        else => @compileError(
            "rzig.parallelFor: worker must be a function with signature fn(" ++
                @typeName(StatePointer) ++ ", usize) void",
        ),
    };
    if (function.params.len != 2 or
        function.params[0].type == null or function.params[0].type.? != StatePointer or
        function.params[1].type == null or function.params[1].type.? != usize or
        function.return_type == null or function.return_type.? != void)
    {
        @compileError(
            "rzig.parallelFor: worker must have signature fn(" ++
                @typeName(StatePointer) ++ ", usize) void",
        );
    }
}

fn validatePlainType(comptime T: type, comptime depth: usize) void {
    if (depth > max_state_depth) {
        @compileError(
            "rzig.parallelFor: worker state is nested too deeply to validate safely",
        );
    }
    if (isRCapability(T)) {
        @compileError(
            "rzig.parallelFor: worker state contains R-facing type '" ++ @typeName(T) ++
                "'; pass only plain Zig data and call R APIs on the calling thread",
        );
    }

    switch (@typeInfo(T)) {
        .void, .bool, .int, .float, .@"enum" => {},
        .array => |info| validatePlainType(info.child, depth + 1),
        .vector => |info| validatePlainType(info.child, depth + 1),
        .optional => |info| validatePlainType(info.child, depth + 1),
        .pointer => |info| {
            if (@typeInfo(info.child) == .@"opaque" or @typeInfo(info.child) == .@"fn") {
                @compileError(
                    "rzig.parallelFor: worker state contains an opaque or function pointer '" ++
                        @typeName(T) ++ "'",
                );
            }
            validatePlainType(info.child, depth + 1);
        },
        .@"struct" => |info| inline for (info.fields) |field| {
            validatePlainType(field.type, depth + 1);
        },
        .@"union" => |info| inline for (info.fields) |field| {
            validatePlainType(field.type, depth + 1);
        },
        else => @compileError(
            "rzig.parallelFor: worker state contains unsupported type '" ++ @typeName(T) ++ "'",
        ),
    }
}

fn isRCapability(comptime T: type) bool {
    if (T == Ctx or T == sexp.Sexp or T == matrix.Matrix or T == list.List) return true;
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "rzig_mut_inner") or @hasDecl(T, "rzig_attributed_inner"),
        else => false,
    };
}

test "worker validation accepts nested plain state and atomics" {
    const State = struct {
        values: []f64,
        failed: std.atomic.Value(bool),
        options: ?[2]u16,
    };
    const Worker = struct {
        fn run(state: *State, index: usize) void {
            _ = state;
            _ = index;
        }
    };
    comptime validateWorker(*State, Worker.run);
}
