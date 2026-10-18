const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

/// Route ReleaseSafe failures through R while retaining the Zig test runner.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

var unwind_cleanup_count_value: i32 = 0;

const UnwindProbe = struct {
    memory: []u8,
    cleaned: bool = false,
    jumped: bool = false,

    fn returnNil(state: *UnwindProbe) rzig.internal.c.SEXP {
        _ = state;
        return rzig.internal.c.R_NilValue;
    }

    fn stopInR(state: *UnwindProbe) rzig.internal.c.SEXP {
        _ = state;
        const c = rzig.internal.c;
        const stop_symbol = c.Rf_install("stop");
        var stack = rzig.internal.protect.Stack.init();
        const call = stack.push(c.Rf_lang1(stop_symbol));
        const result = c.Rf_eval(call, c.R_BaseEnv);
        stack.unwindAll();
        stack.deinit();
        return result;
    }

    fn cleanup(state: *UnwindProbe, jumped: bool) void {
        std.heap.c_allocator.free(state.memory);
        state.cleaned = true;
        state.jumped = jumped;
        unwind_cleanup_count_value +|= 1;
    }
};

fn newUnwindProbe() rzig.Error!UnwindProbe {
    const memory = std.heap.c_allocator.alloc(u8, 4096) catch
        return rzig.raise("unable to allocate unwind test resource", .{});
    return .{ .memory = memory };
}

/// Add one to every value in a numeric vector.
/// @export
pub fn add_one(ctx: *rzig.Ctx, values: []const f64) rzig.Error![]f64 {
    const result = try ctx.alloc(f64, values.len);
    for (values, result) |value, *slot| slot.* = value + 1.0;
    return result;
}

/// Return a scalar double unchanged.
/// @export
pub fn echo_f64(value: f64) f64 {
    return value;
}

/// Return a scalar integer unchanged.
/// @export
pub fn echo_i32(value: i32) i32 {
    return value;
}

/// Return a scalar logical unchanged.
/// @export
pub fn echo_bool(value: bool) bool {
    return value;
}

/// Convert a non-negative Zig-sized integer to an R integer.
/// @export
pub fn echo_usize(value: usize) i32 {
    return @intCast(value);
}

/// Return an optional scalar double unchanged.
/// @export
pub fn echo_optional(value: ?f64) ?f64 {
    return value;
}

/// Return a borrowed numeric vector for copying to R.
/// @export
pub fn echo_reals(values: []const f64) []const f64 {
    return values;
}

/// Return a borrowed integer vector for copying to R.
/// @export
pub fn echo_integers(values: []const i32) []const i32 {
    return values;
}

/// Return an arena-backed logical vector for copying to R.
/// @export
pub fn echo_logicals(values: []const bool) []const bool {
    return values;
}

/// Count values in an integer vector.
/// @export
pub fn integer_length(values: []const i32) rzig.Error!i32 {
    if (values.len > std.math.maxInt(i32)) {
        return rzig.raise("integer vector is too long", .{});
    }
    return @intCast(values.len);
}

/// Count true values in a logical vector.
/// @export
pub fn logical_count(values: []const bool) rzig.Error!i32 {
    var count: usize = 0;
    for (values) |value| count += @intFromBool(value);
    if (count > std.math.maxInt(i32)) return rzig.raise("logical vector is too long", .{});
    return @intCast(count);
}

/// Return one UTF-8 string unchanged.
/// @export
pub fn echo_string(value: []const u8) []const u8 {
    return value;
}

/// Return an arena-backed UTF-8 character vector for copying to R.
/// @export
pub fn echo_strings(values: []const []const u8) []const []const u8 {
    return values;
}

/// Count strings in a character vector.
/// @export
pub fn string_count(values: []const []const u8) rzig.Error!i32 {
    if (values.len > std.math.maxInt(i32)) return rzig.raise("string vector is too long", .{});
    return @intCast(values.len);
}

/// Return an arbitrary borrowed R value unchanged.
/// @export
pub fn identity_sexp(value: rzig.Sexp) rzig.Sexp {
    return value;
}

/// Add two numeric vectors elementwise.
/// @export
pub fn add_vectors(ctx: *rzig.Ctx, a: []const f64, b: []const f64) rzig.Error![]f64 {
    if (a.len != b.len) return rzig.raise("lengths differ: {d} vs {d}", .{ a.len, b.len });
    const result = try ctx.alloc(f64, a.len);
    for (a, b, result) |left, right, *slot| slot.* = left + right;
    return result;
}

/// Return a named list containing a vector and its length.
/// @export
pub fn named_summary(ctx: *rzig.Ctx, values: []const f64) rzig.Error!rzig.List {
    if (values.len > std.math.maxInt(i32)) return rzig.raise("numeric vector is too long", .{});
    var result = rzig.List.init(ctx);
    try result.put("values", values);
    try result.put("count", @as(i32, @intCast(values.len)));
    return result;
}

/// Return every supported vector kind inside a named R list.
/// @export
pub fn vector_summary(
    ctx: *rzig.Ctx,
    integers: []const i32,
    logicals: []const bool,
    strings: []const []const u8,
) rzig.Error!rzig.List {
    var result = rzig.List.init(ctx);
    try result.put("integers", integers);
    try result.put("logicals", logicals);
    try result.put("strings", strings);
    return result;
}

/// Attach matrix dimensions to a logical vector.
/// @export
pub fn reshape_logicals(
    ctx: *rzig.Ctx,
    values: []const bool,
    nrow: usize,
) rzig.Error!rzig.Attributed([]const bool) {
    const ncol = if (nrow == 0) blk: {
        if (values.len != 0) return rzig.raise("zero rows require an empty vector", .{});
        break :blk @as(usize, 0);
    } else blk: {
        if (values.len % nrow != 0) {
            return rzig.raise("length {d} is not divisible by {d} rows", .{ values.len, nrow });
        }
        break :blk values.len / nrow;
    };
    if (nrow > std.math.maxInt(i32) or ncol > std.math.maxInt(i32)) {
        return rzig.raise("matrix dimensions exceed R's integer limit", .{});
    }

    const dimensions = [_]i32{ @intCast(nrow), @intCast(ncol) };
    var result = rzig.Attributed([]const bool).init(ctx, values);
    try result.setDim(&dimensions);
    return result;
}

/// Scale a duplicated numeric vector without mutating the caller's input.
/// @export
pub fn scale_in_place(values: rzig.Mut([]f64), factor: f64) void {
    for (values.data) |*value| value.* *= factor;
}

/// Attach names and a class to a numeric vector.
/// @export
pub fn decorate_values(
    ctx: *rzig.Ctx,
    values: []const f64,
    labels: []const []const u8,
) rzig.Error!rzig.Attributed([]const f64) {
    var result = rzig.Attributed([]const f64).init(ctx, values);
    try result.setNames(labels);
    try result.setClass("rzig_values");
    return result;
}

/// Give a numeric vector two-dimensional matrix dimensions.
/// @export
pub fn reshape_values(
    ctx: *rzig.Ctx,
    values: []const f64,
    nrow: usize,
) rzig.Error!rzig.Attributed([]const f64) {
    const ncol = if (nrow == 0) blk: {
        if (values.len != 0) return rzig.raise("zero rows require an empty vector", .{});
        break :blk @as(usize, 0);
    } else blk: {
        if (values.len % nrow != 0) {
            return rzig.raise("length {d} is not divisible by {d} rows", .{ values.len, nrow });
        }
        break :blk values.len / nrow;
    };
    if (nrow > std.math.maxInt(i32) or ncol > std.math.maxInt(i32)) {
        return rzig.raise("matrix dimensions exceed R's integer limit", .{});
    }

    const dimensions = [_]i32{ @intCast(nrow), @intCast(ncol) };
    var result = rzig.Attributed([]const f64).init(ctx, values);
    try result.setDim(&dimensions);
    return result;
}

/// Sum the diagonal of a borrowed numeric matrix.
/// @export
pub fn matrix_trace(values: rzig.Matrix) rzig.Error!f64 {
    if (values.nrow != values.ncol) {
        return rzig.raise("matrix must be square; got {d} x {d}", .{ values.nrow, values.ncol });
    }
    var result: f64 = 0;
    for (0..values.nrow) |index| result += values.data[index + index * values.nrow];
    return result;
}

/// Draw uniforms from R's random-number stream.
/// @export
pub fn draw_uniforms(ctx: *rzig.Ctx, count: usize) rzig.Error![]f64 {
    const random = try ctx.rng();
    const result = try ctx.alloc(f64, count);
    for (result) |*value| value.* = random.uniform();
    return result;
}

/// Draw standard normals from R's random-number stream.
/// @export
pub fn draw_normals(ctx: *rzig.Ctx, count: usize) rzig.Error![]f64 {
    const random = try ctx.rng();
    const result = try ctx.alloc(f64, count);
    for (result) |*value| value.* = random.normal();
    return result;
}

/// Draw once, then fail so boundary cleanup must save the advanced RNG state.
/// @export
pub fn draw_then_error(ctx: *rzig.Ctx) rzig.Error!void {
    const random = try ctx.rng();
    _ = random.uniform();
    return rzig.raise("intentional error after an R RNG draw", .{});
}

/// Evaluate Rmath's normal cumulative distribution function.
/// @export
pub fn normal_cdf(value: f64) rzig.Error!f64 {
    return rzig.Rmath.normalCdf(value, 0.0, 1.0, true, false);
}

/// Evaluate Rmath's normal quantile function.
/// @export
pub fn normal_quantile(probability: f64) rzig.Error!f64 {
    return rzig.Rmath.normalQuantile(probability, 0.0, 1.0, true, false);
}

/// Count iterations while periodically checking for Ctrl-C.
/// @export
pub fn interruptible_count(iterations: usize) rzig.Error!i32 {
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        if (index % 100_000 == 0) try rzig.checkInterrupt();
    }
    return @intCast(index);
}

/// Allocate a resource, then request fixture-only interrupt delivery.
/// @export
pub fn simulate_interrupt(ctx: *rzig.Ctx) rzig.Error!void {
    const memory = try ctx.alloc(u8, 1024 * 1024);
    memory[0] = 1;
    memory[memory.len - 1] = 1;
    return rzig.internal.interrupt.request();
}

/// Sum a bit64::integer64 vector, stopping on overflow; NA is skipped.
/// @export
pub fn int64_sum(values: []const i64) rzig.Error!i64 {
    var total: i64 = 0;
    for (values) |value| {
        if (value == rzig.NA.integer64) continue;
        total = std.math.add(i64, total, value) catch return rzig.raise("integer64 overflow", .{});
    }
    return total;
}

/// Double every element of a bit64::integer64 vector.
/// @export
pub fn int64_double(ctx: *rzig.Ctx, values: []const i64) rzig.Error![]i64 {
    const result = try ctx.alloc(i64, values.len);
    for (values, result) |value, *slot| {
        slot.* = if (value == rzig.NA.integer64) value else std.math.mul(i64, value, 2) catch
            return rzig.raise("integer64 overflow", .{});
    }
    return result;
}

/// Return an i64 scalar unchanged, or -1 for NA and NULL.
/// @export
pub fn int64_or_default(value: ?i64) i64 {
    return value orelse -1;
}

/// Return `count` as a double, for counts beyond 2^31 - 1.
/// @export
pub fn long_count(count: i64) f64 {
    return @floatFromInt(count);
}

/// The modulus of each element of a complex vector.
/// @export
pub fn complex_modulus(ctx: *rzig.Ctx, values: []const rzig.Complex) rzig.Error![]f64 {
    const result = try ctx.alloc(f64, values.len);
    for (values, result) |value, *slot| slot.* = std.math.complex.abs(value.toStd());
    return result;
}

/// The complex conjugate of each element.
/// @export
pub fn complex_conjugate(ctx: *rzig.Ctx, values: []const rzig.Complex) rzig.Error![]rzig.Complex {
    const result = try ctx.alloc(rzig.Complex, values.len);
    for (values, result) |value, *slot| slot.* = .{ .re = value.re, .im = -value.im };
    return result;
}

/// Multiply two complex scalars.
/// @export
pub fn complex_product(a: rzig.Complex, b: rzig.Complex) rzig.Complex {
    return rzig.Complex.fromStd(a.toStd().mul(b.toStd()));
}

/// XOR every byte of a raw vector with `key`.
/// @export
pub fn raw_xor(ctx: *rzig.Ctx, bytes: rzig.Raw, key: i32) rzig.Error!rzig.Raw {
    if (key < 0 or key > 255) return rzig.raise("`key` must be from 0 to 255; got {d}", .{key});
    const result = try ctx.alloc(u8, bytes.data.len);
    for (bytes.data, result) |byte, *slot| slot.* = byte ^ @as(u8, @intCast(key));
    return .{ .data = result };
}

/// Count the TRUE, FALSE and NA values of a logical vector.
/// @export
pub fn logical_tally(ctx: *rzig.Ctx, values: []const rzig.Logical) rzig.Error![]i32 {
    const counts = try ctx.alloc(i32, 3);
    @memset(counts, 0);
    for (values) |value| {
        if (value.isNa()) {
            counts[2] += 1;
        } else if (value.isTrue()) {
            counts[0] += 1;
        } else {
            counts[1] += 1;
        }
    }
    return counts;
}

/// Negate a logical vector, keeping NA.
/// @export
pub fn logical_not(ctx: *rzig.Ctx, values: []const rzig.Logical) rzig.Error![]rzig.Logical {
    const result = try ctx.alloc(rzig.Logical, values.len);
    for (values, result) |value, *slot| {
        slot.* = if (value.isNa()) rzig.NA.logical else rzig.Logical.fromBool(!value.isTrue());
    }
    return result;
}

/// Upper-case the ASCII letters of each string, keeping NA.
/// @export
pub fn upper_or_na(ctx: *rzig.Ctx, values: []const ?[]const u8) rzig.Error![]?[]const u8 {
    const result = try ctx.alloc(?[]const u8, values.len);
    for (values, result) |value, *slot| {
        const text = value orelse {
            slot.* = null;
            continue;
        };
        const copy = try ctx.dupe(u8, text);
        for (copy) |*byte| byte.* = std.ascii.toUpper(byte.*);
        slot.* = copy;
    }
    return result;
}

/// Return the label, or "(none)" when it is NA or NULL.
/// @export
pub fn label_or_default(label: ?[]const u8) []const u8 {
    return label orelse "(none)";
}

/// R's missing double.
/// @export
pub fn na_real() f64 {
    return rzig.NA.real;
}

/// R's missing integer.
/// @export
pub fn na_integer() i32 {
    return rzig.NA.integer;
}

/// R's missing logical, as a vector of length 1.
/// @export
pub fn na_logical() []const rzig.Logical {
    return &.{rzig.NA.logical};
}

/// Sum the entries of an integer matrix, column by column.
/// @export
pub fn int_matrix_sum(values: rzig.IntMatrix) rzig.Error!f64 {
    var total: f64 = 0;
    for (0..values.ncol) |column| {
        for (values.column(column)) |value| total += @floatFromInt(value);
    }
    return total;
}

/// Count the TRUE entries in each row of a logical matrix.
/// @export
pub fn bool_matrix_row_counts(ctx: *rzig.Ctx, values: rzig.BoolMatrix) rzig.Error![]i32 {
    const counts = try ctx.alloc(i32, values.nrow);
    @memset(counts, 0);
    for (0..values.nrow) |row| {
        for (0..values.ncol) |column| {
            if (values.at(row, column)) counts[row] += 1;
        }
    }
    return counts;
}

/// Add `step` times the column index to each column of a numeric matrix.
/// @export
pub fn matrix_add_column_index(values: rzig.Mut(rzig.Matrix), step: f64) void {
    for (0..values.data.ncol) |column| {
        for (values.data.column(column)) |*value| value.* += step * @as(f64, @floatFromInt(column));
    }
}

/// Negate the diagonal of an integer matrix in place.
/// @export
pub fn int_matrix_negate_diagonal(values: rzig.Mut(rzig.IntMatrix)) void {
    const count = @min(values.data.nrow, values.data.ncol);
    for (0..count) |index| values.data.set(index, index, -values.data.at(index, index));
}

/// Add `step` to each element of an integer vector in place.
/// @export
pub fn int_add_in_place(values: rzig.Mut([]i32), step: i32) rzig.Error!void {
    for (values.data) |*value| {
        value.* = std.math.add(i32, value.*, step) catch return rzig.raise("integer overflow", .{});
    }
}

/// Return an nrow x ncol matrix of row-major positions with dimnames.
/// @export
pub fn named_matrix(
    ctx: *rzig.Ctx,
    nrow: usize,
    ncol: usize,
    row_names: []const []const u8,
    column_names: []const []const u8,
) rzig.Error!rzig.Attributed([]f64) {
    const values = try ctx.alloc(f64, nrow * ncol);
    for (0..ncol) |column| {
        for (0..nrow) |row| values[column * nrow + row] = @floatFromInt(row * ncol + column + 1);
    }
    var result = rzig.Attributed([]f64).init(ctx, values);
    try result.setMatrix(nrow, ncol);
    try result.setDimnames(if (row_names.len > 0) row_names else null, if (column_names.len > 0) column_names else null);
    return result;
}

/// Print `count` numbered lines to R's output and a summary to its message stream.
/// @export
pub fn console_lines(ctx: *rzig.Ctx, count: usize) rzig.Error!void {
    var line: usize = 1;
    while (line <= count) : (line += 1) try ctx.print("line {d}\n", .{line});
    try ctx.eprint("printed {d} lines\n", .{count});
}

/// Print one line of `width` characters, longer than any fixed buffer.
/// @export
pub fn console_wide(ctx: *rzig.Ctx, width: usize) rzig.Error!void {
    const text = try ctx.alloc(u8, width);
    @memset(text, 'z');
    try ctx.print("{s}\n", .{text});
}

/// Run `total` steps with a progress bar shown when `show` is true.
/// @export
pub fn progress_steps(ctx: *rzig.Ctx, total: usize, show: bool) rzig.Error!i32 {
    var progress = ctx.progress(total, show);
    var step: usize = 0;
    while (step < total) : (step += 1) try progress.add(1);
    try progress.finish();
    return @intCast(step);
}

/// Report how many worker threads parallelFor uses for `count` indices.
/// @export
pub fn parallel_thread_count(count: usize) rzig.Error!i32 {
    return @intCast(try rzig.parallelThreadCount(count));
}

/// Square a numeric vector using only pure Zig worker threads.
/// @export
pub fn parallel_square(ctx: *rzig.Ctx, values: []const f64) rzig.Error![]f64 {
    const Work = struct {
        input: []const f64,
        output: []f64,

        fn run(work: *@This(), index: usize) void {
            work.output[index] = work.input[index] * work.input[index];
        }
    };

    const result = try ctx.alloc(f64, values.len);
    var work = Work{ .input = values, .output = result };
    try rzig.parallelFor(ctx, values.len, &work, Work.run);
    return result;
}

/// Return the number of resources released by unwind cleanup.
/// @export
pub fn unwind_cleanup_count() i32 {
    return unwind_cleanup_count_value;
}

/// Exercise unwind cleanup after an ordinary R callback return.
/// @export
pub fn unwind_cleanup_normal() rzig.Error!i32 {
    var state = try newUnwindProbe();
    _ = rzig.internal.unwind.protect(&state, UnwindProbe.returnNil, UnwindProbe.cleanup);
    if (!state.cleaned or state.jumped) {
        return rzig.raise("unwind cleanup did not report an ordinary return", .{});
    }
    return unwind_cleanup_count_value;
}

/// Exercise unwind cleanup when evaluation in R raises an error.
/// @export
pub fn unwind_cleanup_error() rzig.Error!void {
    var state = try newUnwindProbe();
    _ = rzig.internal.unwind.protect(&state, UnwindProbe.stopInR, UnwindProbe.cleanup);
    return rzig.raise("R evaluation unexpectedly returned", .{});
}

/// Trigger an intentional ReleaseSafe bounds failure.
/// @export
pub fn panic_bounds(values: []const f64) void {
    const one = [_]u8{0};
    if (one[values.len] == 0) return;
}

/// Allocate scratch memory and then return an intentional error.
/// @export
pub fn allocate_then_error(ctx: *rzig.Ctx) rzig.Error!void {
    const memory = try ctx.alloc(u8, 10 * 1024 * 1024);
    memory[0] = 1;
    memory[memory.len - 1] = 1;
    return rzig.raise("intentional error after allocating 10 MiB", .{});
}

/// Exercise a generated wrapper with no R-visible arguments.
/// @export
pub fn arity_zero() i32 {
    return 0;
}

/// Exercise a generated wrapper with three R-visible arguments.
/// @export
pub fn sum_three(a: f64, b: f64, c: f64) f64 {
    return a + b + c;
}

/// Exercise a generated wrapper with eight R-visible arguments.
/// @export
pub fn sum_eight(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64, g: f64, h: f64) f64 {
    return a + b + c + d + e + f + g + h;
}

/// Verify that Zig's C variadic ABI matches the R toolchain.
/// @export
pub fn ucrt_smoke(value: i32) i32 {
    rzig.internal.c.Rprintf("%s %d\n", "rzig-ucrt", @as(c_int, value));
    return value;
}

comptime {
    rzig.registerModule(@This());
}
