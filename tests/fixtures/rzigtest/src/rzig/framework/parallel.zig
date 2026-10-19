//! Parallel execution for pure Zig computation.
//!
//! The callback receives only a compile-time-validated plain-data state pointer
//! and an index. It never runs on the thread that entered R.

const std = @import("std");
const builtin = @import("builtin");
const compat = @import("compat.zig");
const Ctx = @import("alloc.zig").Ctx;
const attributes = @import("attributes.zig");
const convert = @import("convert.zig");
const es = @import("error_state.zig");
const list = @import("list.zig");
const matrix = @import("matrix.zig");
const rng = @import("rng.zig");
const sexp = @import("sexp.zig");
const interrupt = @import("interrupt.zig");
const panic = @import("panic.zig");
const thread_identity = @import("thread_identity.zig");

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
    return runIndexed(ctx, count, state, worker);
}

/// Reduce `map(state, index)` over `[0, count)` with `combine`, starting from
/// `identity`. The indices are split into at most 1024 chunks that depend
/// only on `count`; each chunk is reduced in index order on a worker, and the
/// chunk results in chunk order on the calling thread, so the result is the
/// same for every number of threads (also for floating-point sums).
pub fn parallelReduce(
    ctx: *Ctx,
    comptime T: type,
    count: usize,
    state: anytype,
    identity: T,
    comptime map: anytype,
    comptime combine: fn (T, T) T,
) es.Error!T {
    const StatePointer = @TypeOf(state);
    comptime validateState(StatePointer, "rzig.parallelReduce");
    comptime validatePlainType(T, 0);
    if (count == 0) return identity;
    const chunks = @min(count, 1024);
    const results = try ctx.alloc(T, chunks);
    const Chunks = struct {
        state: StatePointer,
        results: []T,
        count: usize,
        chunks: usize,
        identity: T,

        fn run(self: *const @This(), chunk: usize) void {
            const start = chunk * self.count / self.chunks;
            const end = (chunk + 1) * self.count / self.chunks;
            var accumulated = self.identity;
            var index = start;
            while (index < end) : (index += 1) accumulated = combine(accumulated, map(self.state, index));
            self.results[chunk] = accumulated;
        }
    };
    const plan = Chunks{ .state = state, .results = results, .count = count, .chunks = chunks, .identity = identity };
    try runIndexed(ctx, chunks, &plan, Chunks.run);
    var total = identity;
    for (results) |value| total = combine(total, value);
    return total;
}

fn RunnerType(comptime Context: type, comptime body: anytype) type {
    return struct {
        next: std.atomic.Value(usize),
        count: usize,
        context: Context,
        cancel: std.atomic.Value(bool) = .init(false),
        completion: thread_identity.Completion = .{},

        fn run(self: *@This()) void {
            defer self.completion.finish();
            while (!self.cancel.load(.monotonic) and panic.workerPanicked() == null) {
                const index = self.next.fetchAdd(1, .monotonic);
                if (index >= self.count) return;
                body(self.context, index);
            }
        }
    };
}

/// Run `body(context, index)` for every index in `[0, count)` on worker
/// threads. The calling thread waits until the workers finish, checks for a
/// user interrupt at least every `interrupt_probe_ms` milliseconds (and then
/// lets the workers stop after their current index), and turns a panic of a
/// worker into an R error.
fn runIndexed(ctx: *Ctx, count: usize, context: anytype, comptime body: anytype) es.Error!void {
    if (count == 0) return;
    if (count == std.math.maxInt(usize)) {
        return es.raise("rzig: parallelFor item count exceeds its safe limit", .{});
    }
    if (comptime builtin.single_threaded) {
        // A single-threaded build (WebAssembly for webR) runs the indices in
        // order on the calling thread, checking for interrupts in between.
        var index: usize = 0;
        while (index < count) : (index += 1) {
            body(context, index);
            if (index % 4096 == 4095) try interrupt.checkInterrupt();
        }
        return;
    }
    const thread_count = try threadCount(count);
    const threads = try ctx.alloc(std.Thread, thread_count);
    const Runner = RunnerType(@TypeOf(context), body);
    var runner = Runner{
        .next = std.atomic.Value(usize).init(0),
        .count = count,
        .context = context,
    };
    panic.beginWorkers();
    var spawned: usize = 0;
    var spawn_failed = false;
    while (spawned < thread_count) : (spawned += 1) {
        threads[spawned] = std.Thread.spawn(.{}, Runner.run, .{&runner}) catch {
            spawn_failed = true;
            runner.cancel.store(true, .monotonic);
            break;
        };
    }
    var interrupted = false;
    while (true) {
        // A worker that panicked ends without counting itself as finished, so
        // the wait for it ends at the timeout.
        const finished = runner.completion.wait(spawned -| panic.workerExits(), interrupt_probe_ms);
        if (finished + panic.workerExits() >= spawned) break;
        if (!interrupted and !spawn_failed) {
            interrupt.checkInterrupt() catch {
                interrupted = true;
                runner.cancel.store(true, .monotonic);
            };
        }
    }
    releaseThreads(threads[0..spawned]);
    if (spawn_failed) return es.raise("rzig: unable to start a parallel worker", .{});
    if (panic.workerPanicked()) |message| {
        return es.raise("rzig: a parallel worker failed and its work was abandoned: {s}", .{message});
    }
    if (interrupted) return es.Error.RZigError;
}

/// Release the worker threads once every worker has finished or ended after a
/// panic. A worker that panicked ended its thread inside the panic handler,
/// before its thread function returned, and std.Thread.join() asserts that
/// return on Windows, so the threads are detached there after a panic; no
/// worker touches the shared state any more.
fn releaseThreads(threads: []const std.Thread) void {
    const detach = builtin.os.tag == .windows and panic.workerExits() > 0;
    for (threads) |thread| {
        if (detach) thread.detach() else thread.join();
    }
}

/// The longest time the calling thread waits for worker threads without
/// checking for a user interrupt.
const interrupt_probe_ms: u32 = 10;

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

/// Validate the callback contract while state and function types are available.
pub fn validateWorker(comptime StatePointer: type, comptime worker: anytype) void {
    validateState(StatePointer, "rzig.parallelFor");

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

fn validateState(comptime StatePointer: type, comptime what: []const u8) void {
    const state_pointer = switch (@typeInfo(StatePointer)) {
        .pointer => |info| info,
        else => @compileError(what ++ ": state must be a single-item pointer to plain Zig data"),
    };
    if (state_pointer.size != .one) {
        @compileError(what ++ ": state must be a single-item pointer to plain Zig data");
    }
    validatePlainType(state_pointer.child, 0);
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
    if (T == Ctx or T == rng.Rng or T == sexp.Sexp or matrix.isMatrix(T) or T == list.List) return true;
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "rzig_mut_inner") or @hasDecl(T, "rzig_attributed_inner") or
            @hasDecl(T, "rzig_r_thread_only"),
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
