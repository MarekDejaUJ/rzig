//! Parallel execution for pure Zig computation.
//!
//! The callback receives only a compile-time-validated plain-data state pointer
//! and an index. It never runs on the thread that entered R.

const std = @import("std");
const compat = @import("compat.zig");
const Ctx = @import("alloc.zig").Ctx;
const attributes = @import("attributes.zig");
const convert = @import("convert.zig");
const es = @import("error_state.zig");
const list = @import("list.zig");
const matrix = @import("matrix.zig");
const rng = @import("rng.zig");
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

    const thread_count = try threadCount(count);
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

/// The number of worker threads `parallelFor` uses for `count` indices: one per
/// core, at most 32 and at most `count`. The environment variable
/// `RZIG_NUM_THREADS` lowers the limit, `OMP_THREAD_LIMIT` is respected as
/// well, and while `R CMD check` limits the cores (`_R_CHECK_LIMIT_CORES_` set
/// to anything but "false", as for CRAN submissions) at most two threads run.
/// Read the variables only on the thread that entered R.
pub fn threadCount(count: usize) es.Error!usize {
    if (count == 0) return 0;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    var limit: usize = @min(cpu_count, max_worker_threads);
    if (environmentValue("RZIG_NUM_THREADS")) |value| {
        const requested = parseThreadLimit(value) orelse return es.raise(
            "rzig: RZIG_NUM_THREADS must be a positive whole number, got '{s}'",
            .{value},
        );
        limit = @min(limit, requested);
    }
    if (environmentValue("OMP_THREAD_LIMIT")) |value| {
        if (parseThreadLimit(value)) |omp_limit| limit = @min(limit, omp_limit);
    }
    if (environmentValue("_R_CHECK_LIMIT_CORES_")) |value| {
        if (checkLimitsCores(value)) limit = @min(limit, 2);
    }
    return @max(1, @min(count, limit));
}

fn environmentValue(comptime name: [:0]const u8) ?[]const u8 {
    const value = std.c.getenv(name.ptr) orelse return null;
    const text = std.mem.span(value);
    return if (text.len == 0) null else text;
}

/// A positive whole number of threads, or null for anything else.
pub fn parseThreadLimit(text: []const u8) ?usize {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    const value = std.fmt.parseUnsigned(usize, trimmed, 10) catch return null;
    return if (value == 0) null else value;
}

/// R's parallel package treats every value of `_R_CHECK_LIMIT_CORES_` except
/// "false" as an active limit.
pub fn checkLimitsCores(text: []const u8) bool {
    return !std.ascii.eqlIgnoreCase(std.mem.trim(u8, text, " \t\r\n"), "false");
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
    if (compat.paramCount(function) != 2 or
        compat.paramType(function, 0) == null or compat.paramType(function, 0).? != StatePointer or
        compat.paramType(function, 1) == null or compat.paramType(function, 1).? != usize or
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
        .@"struct" => |info| inline for (compat.fieldTypes(info)) |Field| {
            validatePlainType(Field, depth + 1);
        },
        .@"union" => |info| inline for (compat.fieldTypes(info)) |Field| {
            validatePlainType(Field, depth + 1);
        },
        else => @compileError(
            "rzig.parallelFor: worker state contains unsupported type '" ++ @typeName(T) ++ "'",
        ),
    }
}

fn isRCapability(comptime T: type) bool {
    if (T == Ctx or T == rng.Rng or T == sexp.Sexp or T == matrix.Matrix or T == list.List) return true;
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
