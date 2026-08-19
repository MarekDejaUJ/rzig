//! Conversion tests with a minimal in-process stand-in for R.

const std = @import("std");
const c = @import("c/abi.zig");
const convert = @import("convert.zig");
const es = @import("error_state.zig");
const protect = @import("protect.zig");
const sexp = @import("sexp.zig");
const Ctx = @import("alloc.zig").Ctx;

const FakeSexp = extern struct {
    kind: c.SEXPTYPE,
    length: c.R_xlen_t,
    reals: [2]f64 = .{ 0, 0 },
    integers: [2]c_int = .{ 0, 0 },
    strings: [2]?*FakeSexp = .{ null, null },
    text: ?[*:0]const u8 = null,
};

const mock_na_real: f64 = @bitCast(@as(u64, 0x7ff8_0000_0000_07a2));
var mock_nil = FakeSexp{ .kind = c.NILSXP, .length = 0 };
var mock_na_string = FakeSexp{ .kind = c.CHARSXP, .length = 0 };
export var R_NilValue: c.SEXP = @ptrCast(&mock_nil);
export var R_NaString: c.SEXP = @ptrCast(&mock_na_string);
var vmax_get_count: usize = 0;
var vmax_set_count: usize = 0;
var mock_objects: [32]FakeSexp = undefined;
var mock_char_buffers: [32][64]u8 = undefined;
var mock_object_count: usize = 0;
var mock_protect_count: usize = 0;
var mock_last_encoding: c_uint = c.CE_NATIVE;

fn raw(value: *FakeSexp) c.SEXP {
    return @ptrCast(value);
}

fn mutableFake(value: c.SEXP) *FakeSexp {
    return @ptrCast(@alignCast(value));
}

fn resetOutputMock() void {
    mock_object_count = 0;
    mock_protect_count = 0;
    mock_last_encoding = c.CE_NATIVE;
}

fn nextObject(kind: c.SEXPTYPE, length: c.R_xlen_t) *FakeSexp {
    std.debug.assert(mock_object_count < mock_objects.len);
    const result = &mock_objects[mock_object_count];
    mock_object_count += 1;
    result.* = .{ .kind = kind, .length = length };
    return result;
}

export fn TYPEOF(value: c.SEXP) c_int {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return @intCast(fake.kind);
}

export fn Rf_xlength(value: c.SEXP) c.R_xlen_t {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return fake.length;
}

export fn Rf_isNull(value: c.SEXP) c.Rboolean {
    return if (TYPEOF(value) == c.NILSXP) c.TRUE else c.FALSE;
}

export fn REAL_ELT(value: c.SEXP, index: c.R_xlen_t) f64 {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return fake.reals[@intCast(index)];
}

export fn INTEGER_ELT(value: c.SEXP, index: c.R_xlen_t) c_int {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return fake.integers[@intCast(index)];
}

export fn LOGICAL_ELT(value: c.SEXP, index: c.R_xlen_t) c_int {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return fake.integers[@intCast(index)];
}

export fn REAL_RO(value: c.SEXP) [*]const f64 {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return &fake.reals;
}

export fn INTEGER_RO(value: c.SEXP) [*]const c_int {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return &fake.integers;
}

export fn LOGICAL_RO(value: c.SEXP) [*]const c_int {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return &fake.integers;
}

export fn STRING_ELT(value: c.SEXP, index: c.R_xlen_t) c.SEXP {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return raw(fake.strings[@intCast(index)].?);
}

export fn Rf_translateCharUTF8(value: c.SEXP) [*:0]const u8 {
    const fake: *const FakeSexp = @ptrCast(@alignCast(value));
    return fake.text.?;
}

export fn vmaxget() ?*anyopaque {
    vmax_get_count += 1;
    return @ptrFromInt(1);
}

export fn vmaxset(mark: ?*const anyopaque) void {
    std.debug.assert(@intFromPtr(mark.?) == 1);
    vmax_set_count += 1;
}

export fn Rf_allocVector(kind: c.SEXPTYPE, length: c.R_xlen_t) c.SEXP {
    std.debug.assert(length >= 0 and length <= 2);
    return raw(nextObject(kind, length));
}

export fn Rf_protect(value: c.SEXP) c.SEXP {
    mock_protect_count += 1;
    return value;
}

export fn Rf_unprotect(count: c_int) void {
    std.debug.assert(count >= 0);
    const amount: usize = @intCast(count);
    std.debug.assert(amount <= mock_protect_count);
    mock_protect_count -= amount;
}

export fn REAL(value: c.SEXP) [*]f64 {
    return &mutableFake(value).reals;
}

export fn INTEGER(value: c.SEXP) [*]c_int {
    return &mutableFake(value).integers;
}

export fn LOGICAL(value: c.SEXP) [*]c_int {
    return &mutableFake(value).integers;
}

export fn Rf_mkCharLenCE(bytes: [*]const u8, length: c_int, encoding: c_uint) c.SEXP {
    std.debug.assert(length >= 0);
    std.debug.assert(mock_protect_count > 0);
    const count: usize = @intCast(length);
    std.debug.assert(count < mock_char_buffers[0].len);
    const index = mock_object_count;
    const result = nextObject(c.CHARSXP, length);
    @memcpy(mock_char_buffers[index][0..count], bytes[0..count]);
    mock_char_buffers[index][count] = 0;
    result.text = mock_char_buffers[index][0..count :0].ptr;
    mock_last_encoding = encoding;
    return raw(result);
}

export fn SET_STRING_ELT(value: c.SEXP, index: c.R_xlen_t, element: c.SEXP) void {
    mutableFake(value).strings[@intCast(index)] = mutableFake(element);
}

export fn R_IsNA(value: f64) c_int {
    return @intFromBool(@as(u64, @bitCast(value)) == @as(u64, @bitCast(mock_na_real)));
}

export fn Rf_type2char(kind: c.SEXPTYPE) [*:0]const u8 {
    return switch (kind) {
        c.NILSXP => "NULL",
        c.LGLSXP => "logical",
        c.INTSXP => "integer",
        c.REALSXP => "double",
        c.STRSXP => "character",
        else => "unknown",
    };
}

fn expectConversion(comptime T: type, value: *FakeSexp, expected: T) !void {
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    try std.testing.expectEqual(expected, try convert.fromSexp(T, &ctx, raw(value), "x"));
}

fn expectConversionError(comptime T: type, value: *FakeSexp, expected: []const u8) !void {
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(T, &ctx, raw(value), "x"));
    try std.testing.expectEqualStrings(expected, es.take());
}

test "f64 accepts scalar doubles, integers, and logicals" {
    var real = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 1.25, 0 } };
    var integer = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ -7, 0 } };
    var logical = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ c.TRUE, 0 } };
    try expectConversion(f64, &real, 1.25);
    try expectConversion(f64, &integer, -7.0);
    try expectConversion(f64, &logical, 1.0);
}

test "i32 accepts integral scalar values and rejects lossy conversion" {
    var integer = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ -7, 0 } };
    var logical = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ c.FALSE, 0 } };
    var real = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 42.0, 0 } };
    var fraction = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 1.5, 0 } };
    var too_large = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 2147483648.0, 0 } };
    try expectConversion(i32, &integer, -7);
    try expectConversion(i32, &logical, 0);
    try expectConversion(i32, &real, 42);
    try expectConversionError(i32, &fraction, "rzig: `x` must be a whole number representable as i32; got 1.5");
    try expectConversionError(i32, &too_large, "rzig: `x` must be a whole number representable as i32; got 2147483648");
}

test "bool accepts only a scalar logical" {
    var yes = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ c.TRUE, 0 } };
    var no = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ c.FALSE, 0 } };
    var integer = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ 1, 0 } };
    try expectConversion(bool, &yes, true);
    try expectConversion(bool, &no, false);
    try expectConversionError(bool, &integer, "rzig: `x` must be a logical vector of length 1; got integer");
}

test "usize rejects negative scalar values" {
    var positive = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 17.0, 0 } };
    var negative = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ -1, 0 } };
    var too_large = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 2147483648.0, 0 } };
    try expectConversion(usize, &positive, 17);
    try expectConversionError(usize, &negative, "rzig: `x` must be non-negative; got -1");
    try expectConversionError(usize, &too_large, "rzig: `x` must be a whole number from 0 to 2147483647; got 2147483648");
}

test "required scalars reject NA while optionals map NULL and NA to null" {
    var nil = FakeSexp{ .kind = c.NILSXP, .length = 0 };
    var na_real = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ mock_na_real, 0 } };
    var na_integer = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ c.NA_INTEGER, 0 } };
    var na_logical = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ c.NA_LOGICAL, 0 } };
    try expectConversionError(f64, &na_real, "rzig: `x` cannot be NA; use ?f64 to accept missing values");
    try expectConversionError(i32, &na_integer, "rzig: `x` cannot be NA; use ?i32 to accept missing values");
    try expectConversionError(bool, &na_logical, "rzig: `x` cannot be NA; use ?bool to accept missing values");
    try expectConversionError(usize, &na_integer, "rzig: `x` cannot be NA; use ?usize to accept missing values");
    try expectConversion(?f64, &nil, null);
    try expectConversion(?f64, &na_real, null);
    try expectConversion(?i32, &na_integer, null);
    try expectConversion(?bool, &na_logical, null);
    try expectConversion(?usize, &na_integer, null);
}

test "ordinary NaN remains a valid f64" {
    var value = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ std.math.nan(f64), 0 } };
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    const converted = try convert.fromSexp(f64, &ctx, raw(&value), "x");
    try std.testing.expect(std.math.isNan(converted));
}

test "length errors name the parameter and actual length" {
    var empty = FakeSexp{ .kind = c.REALSXP, .length = 0 };
    var pair = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 1, 2 } };
    try expectConversionError(f64, &empty, "rzig: `x` must have length 1; got length 0");
    try expectConversionError(i32, &pair, "rzig: `x` must have length 1; got length 2");
}

test "Sexp input uses the explicit low-level escape hatch unchanged" {
    var value = FakeSexp{ .kind = c.VECSXP, .length = 2 };
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    const converted = try convert.fromSexp(sexp.Sexp, &ctx, raw(&value), "x");
    try std.testing.expect(sexp.toRaw(converted) == raw(&value));
}

test "numeric slices borrow read-only R storage and preserve NA" {
    var reals = FakeSexp{ .kind = c.REALSXP, .length = 2, .reals = .{ 1.25, mock_na_real } };
    var integers = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 7, c.NA_INTEGER } };
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();

    const real_values = try convert.fromSexp([]const f64, &ctx, raw(&reals), "values");
    const integer_values = try convert.fromSexp([]const i32, &ctx, raw(&integers), "indices");
    try std.testing.expectEqual(@as(f64, 1.25), real_values[0]);
    try std.testing.expectEqual(@as(u64, @bitCast(mock_na_real)), @as(u64, @bitCast(real_values[1])));
    try std.testing.expectEqualSlices(i32, &.{ 7, c.NA_INTEGER }, integer_values);
    try std.testing.expectEqual(@intFromPtr(&reals.reals[0]), @intFromPtr(real_values.ptr));
    try std.testing.expectEqual(@intFromPtr(&integers.integers[0]), @intFromPtr(integer_values.ptr));
}

test "numeric slices reject implicit promotion with an R-side remedy" {
    var integer = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 1, 2 } };
    var real = FakeSexp{ .kind = c.REALSXP, .length = 2, .reals = .{ 1, 2 } };
    try expectConversionError(
        []const f64,
        &integer,
        "rzig: `x` must be a numeric vector; got integer; use as.numeric() in R",
    );
    try expectConversionError(
        []const i32,
        &real,
        "rzig: `x` must be an integer vector; got double; use as.integer() in R",
    );
}

test "logical slices copy into the arena" {
    var logical = FakeSexp{ .kind = c.LGLSXP, .length = 2, .integers = .{ c.TRUE, c.FALSE } };
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();

    const values = try convert.fromSexp([]const bool, &ctx, raw(&logical), "flags");
    try std.testing.expectEqualSlices(bool, &.{ true, false }, values);
}

test "logical slices reject NA without silently changing it" {
    var logical = FakeSexp{ .kind = c.LGLSXP, .length = 2, .integers = .{ c.FALSE, c.NA_LOGICAL } };
    try expectConversionError(
        []const bool,
        &logical,
        "rzig: `x` cannot contain NA; found NA at position 2",
    );
}

test "empty numeric and logical slices are valid" {
    var real = FakeSexp{ .kind = c.REALSXP, .length = 0 };
    var integer = FakeSexp{ .kind = c.INTSXP, .length = 0 };
    var logical = FakeSexp{ .kind = c.LGLSXP, .length = 0 };
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();

    try std.testing.expectEqual(@as(usize, 0), (try convert.fromSexp([]const f64, &ctx, raw(&real), "x")).len);
    try std.testing.expectEqual(@as(usize, 0), (try convert.fromSexp([]const i32, &ctx, raw(&integer), "x")).len);
    try std.testing.expectEqual(@as(usize, 0), (try convert.fromSexp([]const bool, &ctx, raw(&logical), "x")).len);
}

test "a scalar string is translated to UTF-8 and copied before vmax reset" {
    var text = FakeSexp{ .kind = c.CHARSXP, .length = 5, .text = "caf\xc3\xa9" };
    var value = FakeSexp{ .kind = c.STRSXP, .length = 1, .strings = .{ &text, null } };
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    vmax_get_count = 0;
    vmax_set_count = 0;

    const converted = try convert.fromSexp([]const u8, &ctx, raw(&value), "label");
    try std.testing.expectEqualStrings("caf\xc3\xa9", converted);
    try std.testing.expect(@intFromPtr(converted.ptr) != @intFromPtr(text.text.?));
    try std.testing.expectEqual(@as(usize, 1), vmax_get_count);
    try std.testing.expectEqual(@as(usize, 1), vmax_set_count);
}

test "a string vector copies its pointer array and every UTF-8 value" {
    var first = FakeSexp{ .kind = c.CHARSXP, .length = 5, .text = "alpha" };
    var second = FakeSexp{ .kind = c.CHARSXP, .length = 4, .text = "\xf0\x9f\x98\x80" };
    var value = FakeSexp{ .kind = c.STRSXP, .length = 2, .strings = .{ &first, &second } };
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    vmax_get_count = 0;
    vmax_set_count = 0;

    const converted = try convert.fromSexp([]const []const u8, &ctx, raw(&value), "labels");
    try std.testing.expectEqual(@as(usize, 2), converted.len);
    try std.testing.expectEqualStrings("alpha", converted[0]);
    try std.testing.expectEqualStrings("\xf0\x9f\x98\x80", converted[1]);
    try std.testing.expect(@intFromPtr(converted[0].ptr) != @intFromPtr(first.text.?));
    try std.testing.expect(@intFromPtr(converted[1].ptr) != @intFromPtr(second.text.?));
    try std.testing.expectEqual(@as(usize, 1), vmax_get_count);
    try std.testing.expectEqual(@as(usize, 1), vmax_set_count);
}

test "string inputs reject NA with an exact position" {
    var scalar = FakeSexp{ .kind = c.STRSXP, .length = 1, .strings = .{ &mock_na_string, null } };
    var text = FakeSexp{ .kind = c.CHARSXP, .length = 2, .text = "ok" };
    var vector = FakeSexp{ .kind = c.STRSXP, .length = 2, .strings = .{ &text, &mock_na_string } };
    try expectConversionError([]const u8, &scalar, "rzig: `x` cannot be NA");
    try expectConversionError(
        []const []const u8,
        &vector,
        "rzig: `x` cannot contain NA; found NA at position 2",
    );
}

test "scalar strings enforce character type and length" {
    var integer = FakeSexp{ .kind = c.INTSXP, .length = 1, .integers = .{ 1, 0 } };
    var pair = FakeSexp{ .kind = c.STRSXP, .length = 2 };
    try expectConversionError(
        []const u8,
        &integer,
        "rzig: `x` must be a character vector of length 1; got integer",
    );
    try expectConversionError(
        []const u8,
        &pair,
        "rzig: `x` must have length 1; got length 2",
    );
}

test "empty string vectors are valid" {
    var value = FakeSexp{ .kind = c.STRSXP, .length = 0 };
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    vmax_get_count = 0;
    vmax_set_count = 0;
    const converted = try convert.fromSexp([]const []const u8, &ctx, raw(&value), "labels");
    try std.testing.expectEqual(@as(usize, 0), converted.len);
    try std.testing.expectEqual(@as(usize, 1), vmax_get_count);
    try std.testing.expectEqual(@as(usize, 1), vmax_set_count);
}

test "toSexp maps void and null optionals to R NULL" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();
    defer stack.deinit();

    try std.testing.expect((try convert.toSexp(&stack, &ctx, {})) == c.R_NilValue);
    const missing: ?f64 = null;
    try std.testing.expect((try convert.toSexp(&stack, &ctx, missing)) == c.R_NilValue);
    try std.testing.expectEqual(@as(usize, 0), mock_protect_count);
}

test "toSexp allocates protected scalar vectors" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();

    const real = try convert.toSexp(&stack, &ctx, @as(f64, 1.25));
    const integer = try convert.toSexp(&stack, &ctx, @as(i32, -7));
    const logical = try convert.toSexp(&stack, &ctx, true);
    try std.testing.expectEqual(@as(c_int, c.REALSXP), TYPEOF(real));
    try std.testing.expectEqual(@as(c_int, c.INTSXP), TYPEOF(integer));
    try std.testing.expectEqual(@as(c_int, c.LGLSXP), TYPEOF(logical));
    try std.testing.expectEqual(@as(f64, 1.25), mutableFake(real).reals[0]);
    try std.testing.expectEqual(@as(c_int, -7), mutableFake(integer).integers[0]);
    try std.testing.expectEqual(@as(c_int, c.TRUE), mutableFake(logical).integers[0]);
    try std.testing.expectEqual(@as(usize, 3), mock_protect_count);

    stack.unwindAll();
    stack.deinit();
    try std.testing.expectEqual(@as(usize, 0), mock_protect_count);
}

test "toSexp copies const and mutable real slices" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();

    const const_source: []const f64 = &.{ 2.0, 3.0 };
    var mutable_source = [_]f64{ 5.0, 7.0 };
    const mutable_slice: []f64 = mutable_source[0..];
    const const_result = try convert.toSexp(&stack, &ctx, const_source);
    const mutable_result = try convert.toSexp(&stack, &ctx, mutable_slice);
    mutable_source[0] = 11.0;
    try std.testing.expectEqualSlices(f64, &.{ 2.0, 3.0 }, mutableFake(const_result).reals[0..2]);
    try std.testing.expectEqualSlices(f64, &.{ 5.0, 7.0 }, mutableFake(mutable_result).reals[0..2]);

    stack.unwindAll();
    stack.deinit();
}

test "toSexp creates a UTF-8 character vector" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();
    const source: []const u8 = "caf\xc3\xa9";

    const result = try convert.toSexp(&stack, &ctx, source);
    try std.testing.expectEqual(@as(c_int, c.STRSXP), TYPEOF(result));
    try std.testing.expectEqual(@as(c.R_xlen_t, 1), Rf_xlength(result));
    try std.testing.expectEqualStrings(source, std.mem.span(mutableFake(result).strings[0].?.text.?));
    try std.testing.expectEqual(c.CE_UTF8, mock_last_encoding);

    stack.unwindAll();
    stack.deinit();
}

test "toSexp rejects invalid UTF-8 before calling R" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();
    defer stack.deinit();
    const invalid: []const u8 = &.{ 0xff, 0xfe };
    es.reset();

    try std.testing.expectError(es.Error.RZigError, convert.toSexp(&stack, &ctx, invalid));
    try std.testing.expectEqualStrings("rzig: returned string is not valid UTF-8", es.take());
    try std.testing.expectEqual(@as(usize, 0), mock_object_count);
    try std.testing.expectEqual(@as(usize, 0), mock_protect_count);
}

test "toSexp protects a returned borrowed Sexp" {
    resetOutputMock();
    var value = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 9, 0 } };
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();

    const result = try convert.toSexp(&stack, &ctx, sexp.fromRaw(raw(&value)));
    try std.testing.expect(result == raw(&value));
    try std.testing.expectEqual(@as(usize, 1), mock_protect_count);

    stack.unwindAll();
    stack.deinit();
}

test "toSexp recursively marshals present optionals" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();
    const present: ?i32 = 13;

    const result = try convert.toSexp(&stack, &ctx, present);
    try std.testing.expectEqual(@as(c_int, c.INTSXP), TYPEOF(result));
    try std.testing.expectEqual(@as(c_int, 13), mutableFake(result).integers[0]);

    stack.unwindAll();
    stack.deinit();
}
