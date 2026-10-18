//! Conversion tests with a minimal in-process stand-in for R.

const std = @import("std");
const attributes = @import("attributes.zig");
const complex = @import("complex.zig");
const c = @import("c/abi.zig");
const convert = @import("convert.zig");
const es = @import("error_state.zig");
const list = @import("list.zig");
const matrix = @import("matrix.zig");
const na = @import("na.zig");
const protect = @import("protect.zig");
const sexp = @import("sexp.zig");
const Ctx = @import("alloc.zig").Ctx;

const FakeSexp = extern struct {
    kind: c.SEXPTYPE,
    length: c.R_xlen_t,
    reals: [2]f64 = .{ 0, 0 },
    integers: [2]c_int = .{ 0, 0 },
    strings: [2]?*FakeSexp = .{ null, null },
    vectors: [2]?*FakeSexp = .{ null, null },
    names: ?*FakeSexp = null,
    dim: ?*FakeSexp = null,
    class: ?*FakeSexp = null,
    text: ?[*:0]const u8 = null,
    dimnames: ?*FakeSexp = null,
    complexes: [2]c.Rcomplex = .{ .{ .r = 0, .i = 0 }, .{ .r = 0, .i = 0 } },
    bytes: [4]u8 = .{ 0, 0, 0, 0 },
};

const mock_na_real: f64 = @bitCast(@as(u64, 0x7ff8_0000_0000_07a2));
var mock_nil = FakeSexp{ .kind = c.NILSXP, .length = 0 };
var mock_na_string = FakeSexp{ .kind = c.CHARSXP, .length = 0 };
var mock_names_symbol = FakeSexp{ .kind = c.SYMSXP, .length = 0 };
var mock_dim_symbol = FakeSexp{ .kind = c.SYMSXP, .length = 0 };
var mock_class_symbol = FakeSexp{ .kind = c.SYMSXP, .length = 0 };
var mock_dimnames_symbol = FakeSexp{ .kind = c.SYMSXP, .length = 0 };
export var R_NilValue: c.SEXP = @ptrCast(&mock_nil);
export var R_NaString: c.SEXP = @ptrCast(&mock_na_string);
export var R_NamesSymbol: c.SEXP = @ptrCast(&mock_names_symbol);
export var R_DimSymbol: c.SEXP = @ptrCast(&mock_dim_symbol);
export var R_ClassSymbol: c.SEXP = @ptrCast(&mock_class_symbol);
export var R_DimNamesSymbol: c.SEXP = @ptrCast(&mock_dimnames_symbol);
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

export fn Rf_duplicate(value: c.SEXP) c.SEXP {
    const source = mutableFake(value);
    const result = nextObject(source.kind, source.length);
    result.reals = source.reals;
    result.integers = source.integers;
    result.strings = source.strings;
    result.vectors = source.vectors;
    result.names = source.names;
    result.dim = source.dim;
    result.class = source.class;
    result.text = source.text;
    result.dimnames = source.dimnames;
    result.complexes = source.complexes;
    result.bytes = source.bytes;
    return raw(result);
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

export fn COMPLEX_RO(value: c.SEXP) [*]const c.Rcomplex {
    return &mutableFake(value).complexes;
}

export fn COMPLEX(value: c.SEXP) [*]c.Rcomplex {
    return &mutableFake(value).complexes;
}

export fn RAW_RO(value: c.SEXP) [*]const u8 {
    return &mutableFake(value).bytes;
}

export fn RAW(value: c.SEXP) [*]u8 {
    return &mutableFake(value).bytes;
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

export fn SET_VECTOR_ELT(value: c.SEXP, index: c.R_xlen_t, element: c.SEXP) c.SEXP {
    mutableFake(value).vectors[@intCast(index)] = mutableFake(element);
    return element;
}

export fn Rf_setAttrib(value: c.SEXP, symbol: c.SEXP, attribute: c.SEXP) c.SEXP {
    if (symbol == R_NamesSymbol) {
        mutableFake(value).names = mutableFake(attribute);
    } else if (symbol == R_DimSymbol) {
        mutableFake(value).dim = mutableFake(attribute);
    } else if (symbol == R_ClassSymbol) {
        mutableFake(value).class = mutableFake(attribute);
    } else if (symbol == R_DimNamesSymbol) {
        mutableFake(value).dimnames = mutableFake(attribute);
    } else {
        std.debug.assert(false);
    }
    return value;
}

export fn Rf_getAttrib(value: c.SEXP, symbol: c.SEXP) c.SEXP {
    const fake = mutableFake(value);
    if (symbol == R_NamesSymbol) return if (fake.names) |attribute| raw(attribute) else R_NilValue;
    if (symbol == R_DimSymbol) return if (fake.dim) |attribute| raw(attribute) else R_NilValue;
    if (symbol == R_ClassSymbol) return if (fake.class) |attribute| raw(attribute) else R_NilValue;
    std.debug.assert(false);
    return R_NilValue;
}

export fn Rf_isMatrix(value: c.SEXP) c.Rboolean {
    return if (mutableFake(value).dim != null) c.TRUE else c.FALSE;
}

export fn R_IsNA(value: f64) c_int {
    return @intFromBool(@as(u64, @bitCast(value)) == @as(u64, @bitCast(mock_na_real)));
}

export fn R_IsNaN(value: f64) c_int {
    return @intFromBool(std.math.isNan(value) and R_IsNA(value) == 0);
}

export fn Rf_type2char(kind: c.SEXPTYPE) [*:0]const u8 {
    return switch (kind) {
        c.NILSXP => "NULL",
        c.LGLSXP => "logical",
        c.INTSXP => "integer",
        c.REALSXP => "double",
        c.STRSXP => "character",
        c.CPLXSXP => "complex",
        c.RAWSXP => "raw",
        else => "unknown",
    };
}

fn expectConversion(comptime T: type, value: *FakeSexp, expected: T) !void {
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    try std.testing.expectEqual(expected, try convert.fromSexp(T, &ctx, raw(value), "`x`"));
}

fn expectConversionError(comptime T: type, value: *FakeSexp, expected: []const u8) !void {
    var ctx = Ctx.init();
    defer ctx.deinit();
    es.reset();
    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(T, &ctx, raw(value), "`x`"));
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
    const converted = try convert.fromSexp(f64, &ctx, raw(&value), "`x`");
    try std.testing.expect(std.math.isNan(converted));
}

test "NA predicates distinguish R missing values from ordinary NaN" {
    const ordinary_nan = std.math.nan(f64);
    try std.testing.expect(na.isNaReal(mock_na_real));
    try std.testing.expect(!na.isNaNNotNa(mock_na_real));
    try std.testing.expect(!na.isNaReal(ordinary_nan));
    try std.testing.expect(na.isNaNNotNa(ordinary_nan));
    try std.testing.expect(na.isNaInt(c.NA_INTEGER));
    try std.testing.expect(na.isNaLogical(c.NA_LOGICAL));
    try std.testing.expect(!na.isNaInt(0));
    try std.testing.expect(!na.isNaLogical(c.TRUE));
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
    const converted = try convert.fromSexp(sexp.Sexp, &ctx, raw(&value), "`x`");
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

    try std.testing.expectEqual(@as(usize, 0), (try convert.fromSexp([]const f64, &ctx, raw(&real), "`x`")).len);
    try std.testing.expectEqual(@as(usize, 0), (try convert.fromSexp([]const i32, &ctx, raw(&integer), "`x`")).len);
    try std.testing.expectEqual(@as(usize, 0), (try convert.fromSexp([]const bool, &ctx, raw(&logical), "`x`")).len);
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

test "toSexp copies integer and logical slices into matching R vectors" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();

    const integers: []const i32 = &.{ 7, c.NA_INTEGER };
    var logical_storage = [_]bool{ true, false };
    const integer_result = try convert.toSexp(&stack, &ctx, integers);
    const logical_slice: []bool = logical_storage[0..];
    const logical_result = try convert.toSexp(&stack, &ctx, logical_slice);

    try std.testing.expectEqual(@as(c_int, c.INTSXP), TYPEOF(integer_result));
    try std.testing.expectEqual(@as(c_int, c.LGLSXP), TYPEOF(logical_result));
    try std.testing.expectEqualSlices(c_int, &.{ 7, c.NA_INTEGER }, &mutableFake(integer_result).integers);
    try std.testing.expectEqualSlices(c_int, &.{ c.TRUE, c.FALSE }, &mutableFake(logical_result).integers);

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

test "toSexp creates multi-element UTF-8 character vectors" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();
    const source: []const []const u8 = &.{ "alpha", "\xf0\x9f\x98\x80" };

    const result = try convert.toSexp(&stack, &ctx, source);
    const fake = mutableFake(result);
    try std.testing.expectEqual(@as(c_int, c.STRSXP), TYPEOF(result));
    try std.testing.expectEqual(@as(c.R_xlen_t, 2), Rf_xlength(result));
    try std.testing.expectEqualStrings(source[0], std.mem.span(fake.strings[0].?.text.?));
    try std.testing.expectEqualStrings(source[1], std.mem.span(fake.strings[1].?.text.?));
    try std.testing.expectEqual(c.CE_UTF8, mock_last_encoding);

    stack.unwindAll();
    stack.deinit();
}

test "toSexp validates every returned character-vector element before allocating" {
    resetOutputMock();
    es.reset();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();
    defer stack.deinit();
    const invalid: []const u8 = &.{ 0xff, 0xfe };
    const source: []const []const u8 = &.{ "valid", invalid };

    try std.testing.expectError(es.Error.RZigError, convert.toSexp(&stack, &ctx, source));
    try std.testing.expectEqualStrings("rzig: returned string at position 2 is not valid UTF-8", es.take());
    try std.testing.expectEqual(@as(usize, 0), mock_object_count);
    try std.testing.expectEqual(@as(usize, 0), mock_protect_count);
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

test "List defers R allocation and materializes a named VECSXP in one pass" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var result = list.List.init(&ctx);
    const estimate: []const f64 = &.{ 1.5, 2.5 };

    try result.put("estimate", estimate);
    try result.put("iterations", @as(i32, 7));
    try std.testing.expectEqual(@as(usize, 0), mock_object_count);

    var stack = protect.Stack.init();
    const converted = try convert.toSexp(&stack, &ctx, result);
    const converted_fake = mutableFake(converted);
    try std.testing.expectEqual(@as(c_int, c.VECSXP), TYPEOF(converted));
    try std.testing.expectEqual(@as(c.R_xlen_t, 2), Rf_xlength(converted));
    try std.testing.expectEqualStrings("estimate", std.mem.span(converted_fake.names.?.strings[0].?.text.?));
    try std.testing.expectEqualStrings("iterations", std.mem.span(converted_fake.names.?.strings[1].?.text.?));
    try std.testing.expectEqualSlices(f64, estimate, converted_fake.vectors[0].?.reals[0..2]);
    try std.testing.expectEqual(@as(c_int, 7), converted_fake.vectors[1].?.integers[0]);
    try std.testing.expectEqual(@as(usize, 1), mock_protect_count);

    stack.unwindAll();
    stack.deinit();
}

test "List validates every string before allocating an R object" {
    resetOutputMock();
    es.reset();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var result = list.List.init(&ctx);
    const invalid: []const u8 = &.{ 0xff, 0xfe };
    try result.put("label", invalid);

    var stack = protect.Stack.init();
    defer stack.deinit();
    try std.testing.expectError(es.Error.RZigError, convert.toSexp(&stack, &ctx, result));
    try std.testing.expectEqualStrings("rzig: list string at position 1 is not valid UTF-8", es.take());
    try std.testing.expectEqual(@as(usize, 0), mock_object_count);
    try std.testing.expectEqual(@as(usize, 0), mock_protect_count);
}

test "Mut duplicates and protects numeric inputs before exposing writable storage" {
    resetOutputMock();
    var source = FakeSexp{ .kind = c.REALSXP, .length = 2, .reals = .{ 2, 3 } };
    var stack = protect.Stack.init();
    var mutable_result: ?c.SEXP = null;

    const mutable = try convert.fromMutableSexp(
        convert.Mut([]f64),
        &stack,
        raw(&source),
        "values",
        &mutable_result,
    );
    mutable.data[0] = 11;

    try std.testing.expectEqualSlices(f64, &.{ 2, 3 }, &source.reals);
    try std.testing.expectEqualSlices(f64, &.{ 11, 3 }, mutableFake(mutable_result.?).reals[0..2]);
    try std.testing.expectEqual(@as(usize, 1), mock_protect_count);

    stack.unwindAll();
    stack.deinit();
}

test "Mut rejects non-numeric vectors before duplicating" {
    resetOutputMock();
    es.reset();
    var source = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 2, 3 } };
    var stack = protect.Stack.init();
    defer stack.deinit();
    var mutable_result: ?c.SEXP = null;

    try std.testing.expectError(
        es.Error.RZigError,
        convert.fromMutableSexp(
            convert.Mut([]f64),
            &stack,
            raw(&source),
            "`values`",
            &mutable_result,
        ),
    );
    try std.testing.expectEqualStrings(
        "rzig: `values` must be a numeric vector for rzig.Mut([]f64); got integer; use as.numeric() in R",
        es.take(),
    );
    try std.testing.expectEqual(@as(usize, 0), mock_object_count);
    try std.testing.expectEqual(@as(usize, 0), mock_protect_count);
}

test "Matrix borrows numeric data and validates its dimensions" {
    var dimensions = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 2, 1 } };
    var source = FakeSexp{
        .kind = c.REALSXP,
        .length = 2,
        .reals = .{ 1.5, 2.5 },
        .dim = &dimensions,
    };
    var ctx = Ctx.init();
    defer ctx.deinit();

    const converted = try convert.fromSexp(matrix.Matrix, &ctx, raw(&source), "values");
    try std.testing.expectEqual(@as(usize, 2), converted.nrow);
    try std.testing.expectEqual(@as(usize, 1), converted.ncol);
    try std.testing.expectEqualSlices(f64, &.{ 1.5, 2.5 }, converted.data);
    try std.testing.expectEqual(@intFromPtr(&source.reals[0]), @intFromPtr(converted.data.ptr));
}

test "Matrix rejects vectors and inconsistent dimensions" {
    es.reset();
    var vector = FakeSexp{ .kind = c.REALSXP, .length = 2, .reals = .{ 1, 2 } };
    var bad_dimensions = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 2, 2 } };
    var malformed = FakeSexp{
        .kind = c.REALSXP,
        .length = 2,
        .reals = .{ 1, 2 },
        .dim = &bad_dimensions,
    };
    var ctx = Ctx.init();
    defer ctx.deinit();

    try std.testing.expectError(
        es.Error.RZigError,
        convert.fromSexp(matrix.Matrix, &ctx, raw(&vector), "`values`"),
    );
    try std.testing.expectEqualStrings("rzig: `values` must be a numeric matrix; got a double vector without dimensions", es.take());
    try std.testing.expectError(
        es.Error.RZigError,
        convert.fromSexp(matrix.Matrix, &ctx, raw(&malformed), "`values`"),
    );
    try std.testing.expectEqualStrings("rzig: `values` has dimensions 2 x 2 but contains 2 values", es.take());
}

test "Attributed numeric vectors materialize names, dimensions, and class safely" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    const values: []const f64 = &.{ 1.5, 2.5 };
    const labels: []const []const u8 = &.{ "left", "right" };
    const dimensions: []const i32 = &.{ 1, 2 };
    var result = attributes.Attributed([]const f64).init(&ctx, values);
    try result.setNames(labels);
    try result.setDim(dimensions);
    try result.setClass("rzig_values");

    try std.testing.expectEqual(@as(usize, 0), mock_object_count);
    var stack = protect.Stack.init();
    const converted = try convert.toSexp(&stack, &ctx, result);
    const fake = mutableFake(converted);
    try std.testing.expectEqualStrings("left", std.mem.span(fake.names.?.strings[0].?.text.?));
    try std.testing.expectEqualStrings("right", std.mem.span(fake.names.?.strings[1].?.text.?));
    try std.testing.expectEqualSlices(c_int, &.{ 1, 2 }, &fake.dim.?.integers);
    try std.testing.expectEqualStrings("rzig_values", std.mem.span(fake.class.?.strings[0].?.text.?));
    try std.testing.expectEqual(@as(usize, 1), mock_protect_count);

    stack.unwindAll();
    stack.deinit();
}

test "Attributed logical vectors materialize as logical matrices" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    const values: []const bool = &.{ true, false };
    const dimensions: []const i32 = &.{ 1, 2 };
    var result = attributes.Attributed([]const bool).init(&ctx, values);
    try result.setDim(dimensions);

    var stack = protect.Stack.init();
    const converted = try convert.toSexp(&stack, &ctx, result);
    const fake = mutableFake(converted);
    try std.testing.expectEqual(@as(c_int, c.LGLSXP), TYPEOF(converted));
    try std.testing.expectEqualSlices(c_int, &.{ c.TRUE, c.FALSE }, &fake.integers);
    try std.testing.expectEqualSlices(c_int, &.{ 1, 2 }, &fake.dim.?.integers);

    stack.unwindAll();
    stack.deinit();
}

test "Attributed validates metadata before allocating an R result" {
    resetOutputMock();
    es.reset();
    var ctx = Ctx.init();
    defer ctx.deinit();
    const values: []const f64 = &.{ 1.5, 2.5 };
    const labels: []const []const u8 = &.{"only_one"};
    var result = attributes.Attributed([]const f64).init(&ctx, values);
    try result.setNames(labels);

    var stack = protect.Stack.init();
    defer stack.deinit();
    try std.testing.expectError(es.Error.RZigError, convert.toSexp(&stack, &ctx, result));
    try std.testing.expectEqualStrings(
        "rzig: `names` has length 1, but the returned vector has length 2",
        es.take(),
    );
    try std.testing.expectEqual(@as(usize, 0), mock_object_count);
    try std.testing.expectEqual(@as(usize, 0), mock_protect_count);
}

test "IntMatrix borrows integer data and BoolMatrix copies logical data without NA" {
    es.reset();
    var dimensions = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 1, 2 } };
    var integers = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 7, -3 }, .dim = &dimensions };
    var logicals = FakeSexp{ .kind = c.LGLSXP, .length = 2, .integers = .{ c.TRUE, c.FALSE }, .dim = &dimensions };
    var missing = FakeSexp{
        .kind = c.LGLSXP,
        .length = 2,
        .integers = .{ c.TRUE, std.math.minInt(c_int) },
        .dim = &dimensions,
    };
    var ctx = Ctx.init();
    defer ctx.deinit();

    const int_view = try convert.fromSexp(matrix.IntMatrix, &ctx, raw(&integers), "`x`");
    try std.testing.expectEqual(@as(usize, 1), int_view.nrow);
    try std.testing.expectEqual(@as(usize, 2), int_view.ncol);
    try std.testing.expectEqual(@as(i32, -3), int_view.at(0, 1));
    try std.testing.expectEqual(@intFromPtr(&integers.integers[0]), @intFromPtr(int_view.data.ptr));

    const bool_view = try convert.fromSexp(matrix.BoolMatrix, &ctx, raw(&logicals), "`x`");
    try std.testing.expectEqualSlices(bool, &.{ true, false }, bool_view.data);
    try std.testing.expectEqualSlices(bool, &.{false}, bool_view.column(1));

    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(matrix.BoolMatrix, &ctx, raw(&missing), "`x`"));
    try std.testing.expectEqualStrings("rzig: `x` cannot contain NA; found NA at position 2", es.take());
}

test "matrices of one storage mode reject the others with a storage.mode hint" {
    es.reset();
    var dimensions = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 2, 1 } };
    var doubles = FakeSexp{ .kind = c.REALSXP, .length = 2, .reals = .{ 1, 2 }, .dim = &dimensions };
    var integers = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 1, 2 } };
    var ctx = Ctx.init();
    defer ctx.deinit();

    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(matrix.IntMatrix, &ctx, raw(&doubles), "`x`"));
    try std.testing.expectEqualStrings(
        "rzig: `x` must store integer values; got a double matrix; use storage.mode(x) <- \"integer\" in R",
        es.take(),
    );
    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(matrix.BoolMatrix, &ctx, raw(&doubles), "`x`"));
    try std.testing.expectEqualStrings(
        "rzig: `x` must store logical values; got a double matrix; use storage.mode(x) <- \"logical\" in R",
        es.take(),
    );
    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(matrix.IntMatrix, &ctx, raw(&integers), "`x`"));
    try std.testing.expectEqualStrings("rzig: `x` must be an integer matrix; got an integer vector without dimensions", es.take());
}

test "Mut(Matrix) duplicates a numeric matrix and exposes a writable view" {
    resetOutputMock();
    var dimensions = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 1, 2 } };
    var source = FakeSexp{ .kind = c.REALSXP, .length = 2, .reals = .{ 2, 3 }, .dim = &dimensions };
    var stack = protect.Stack.init();
    var mutable_result: ?c.SEXP = null;

    const mutable = try convert.fromMutableSexp(
        convert.Mut(matrix.Matrix),
        &stack,
        raw(&source),
        "`m`",
        &mutable_result,
    );
    try std.testing.expectEqual(@as(usize, 1), mutable.data.nrow);
    try std.testing.expectEqual(@as(usize, 2), mutable.data.ncol);
    mutable.data.set(0, 1, 30);

    try std.testing.expectEqualSlices(f64, &.{ 2, 3 }, &source.reals);
    try std.testing.expectEqualSlices(f64, &.{ 2, 30 }, mutableFake(mutable_result.?).reals[0..2]);
    try std.testing.expect(mutableFake(mutable_result.?).dim != null);
    try std.testing.expectEqual(@as(usize, 1), mock_protect_count);

    stack.unwindAll();
    stack.deinit();
}

test "Mut([]i32) and Mut(IntMatrix) duplicate integer inputs and reject other types first" {
    resetOutputMock();
    es.reset();
    var dimensions = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 2, 1 } };
    var vector = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 4, 5 } };
    var int_matrix = FakeSexp{ .kind = c.INTSXP, .length = 2, .integers = .{ 6, 7 }, .dim = &dimensions };
    var doubles = FakeSexp{ .kind = c.REALSXP, .length = 2, .reals = .{ 1, 2 } };

    var stack = protect.Stack.init();
    var mutable_result: ?c.SEXP = null;
    const mutable_vector = try convert.fromMutableSexp(convert.Mut([]i32), &stack, raw(&vector), "`v`", &mutable_result);
    mutable_vector.data[1] = 50;
    try std.testing.expectEqualSlices(c_int, &.{ 4, 5 }, &vector.integers);
    try std.testing.expectEqualSlices(c_int, &.{ 4, 50 }, mutableFake(mutable_result.?).integers[0..2]);
    stack.unwindAll();

    mutable_result = null;
    const mutable_matrix = try convert.fromMutableSexp(convert.Mut(matrix.IntMatrix), &stack, raw(&int_matrix), "`m`", &mutable_result);
    try std.testing.expectEqual(@as(usize, 2), mutable_matrix.data.nrow);
    mutable_matrix.data.column(0)[1] = 70;
    try std.testing.expectEqualSlices(c_int, &.{ 6, 70 }, mutableFake(mutable_result.?).integers[0..2]);
    stack.unwindAll();

    resetOutputMock();
    mutable_result = null;
    try std.testing.expectError(
        es.Error.RZigError,
        convert.fromMutableSexp(convert.Mut([]i32), &stack, raw(&doubles), "`v`", &mutable_result),
    );
    try std.testing.expectEqualStrings(
        "rzig: `v` must be an integer vector for rzig.Mut([]i32); got double; use as.integer() in R",
        es.take(),
    );
    try std.testing.expectError(
        es.Error.RZigError,
        convert.fromMutableSexp(convert.Mut(matrix.IntMatrix), &stack, raw(&vector), "`m`", &mutable_result),
    );
    try std.testing.expectEqualStrings("rzig: `m` must be an integer matrix; got an integer vector without dimensions", es.take());
    try std.testing.expectEqual(@as(usize, 0), mock_object_count);
    try std.testing.expectEqual(@as(usize, 0), mock_protect_count);
    stack.deinit();
}

test "Attributed matrices carry row and column names" {
    resetOutputMock();
    var ctx = Ctx.init();
    defer ctx.deinit();
    const values: []const f64 = &.{ 1.5, 2.5 };
    var result = attributes.Attributed([]const f64).init(&ctx, values);
    try result.setMatrix(1, 2);
    try result.setDimnames(&.{"only"}, &.{ "left", "right" });

    var stack = protect.Stack.init();
    const converted = try convert.toSexp(&stack, &ctx, result);
    const fake = mutableFake(converted);
    try std.testing.expectEqualSlices(c_int, &.{ 1, 2 }, &fake.dim.?.integers);
    const dimnames = fake.dimnames.?;
    try std.testing.expectEqual(@as(c_int, c.VECSXP), TYPEOF(raw(dimnames)));
    try std.testing.expectEqualStrings("only", std.mem.span(dimnames.vectors[0].?.strings[0].?.text.?));
    try std.testing.expectEqualStrings("right", std.mem.span(dimnames.vectors[1].?.strings[1].?.text.?));
    try std.testing.expectEqual(@as(usize, 1), mock_protect_count);
    stack.unwindAll();

    resetOutputMock();
    var columns_only = attributes.Attributed([]const f64).init(&ctx, values);
    try columns_only.setMatrix(2, 1);
    try columns_only.setDimnames(null, &.{"value"});
    const named = try convert.toSexp(&stack, &ctx, columns_only);
    try std.testing.expect(mutableFake(named).dimnames.?.vectors[0] == null);
    stack.unwindAll();
    stack.deinit();
}

test "dimnames are checked against dim before allocating" {
    resetOutputMock();
    es.reset();
    var ctx = Ctx.init();
    defer ctx.deinit();
    const values: []const f64 = &.{ 1.5, 2.5 };
    var stack = protect.Stack.init();
    defer stack.deinit();

    var wrong_rows = attributes.Attributed([]const f64).init(&ctx, values);
    try wrong_rows.setMatrix(1, 2);
    try wrong_rows.setDimnames(&.{ "a", "b" }, null);
    try std.testing.expectError(es.Error.RZigError, convert.toSexp(&stack, &ctx, wrong_rows));
    try std.testing.expectEqualStrings("rzig: 2 row names for 1 rows", es.take());

    var without_dim = attributes.Attributed([]const f64).init(&ctx, values);
    try without_dim.setDimnames(null, &.{ "a", "b" });
    try std.testing.expectError(es.Error.RZigError, convert.toSexp(&stack, &ctx, without_dim));
    try std.testing.expectEqualStrings("rzig: `dimnames` needs `dim`; call setMatrix() or setDim() first", es.take());

    var large = attributes.Attributed([]const f64).init(&ctx, values);
    try std.testing.expectError(es.Error.RZigError, large.setMatrix(@as(usize, std.math.maxInt(i32)) + 1, 1));
    try std.testing.expectEqual(@as(usize, 0), mock_object_count);
    try std.testing.expectEqual(@as(usize, 0), mock_protect_count);
}

test "logical vectors that keep NA are borrowed, character vectors map NA to null" {
    es.reset();
    var logicals = FakeSexp{ .kind = c.LGLSXP, .length = 2, .integers = .{ c.TRUE, std.math.minInt(c_int) } };
    var strings = FakeSexp{ .kind = c.STRSXP, .length = 2 };
    var text = FakeSexp{ .kind = c.CHARSXP, .length = 1, .text = "z" };
    strings.strings = .{ &text, &mock_na_string };
    var numbers = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 1, 0 } };
    var ctx = Ctx.init();
    defer ctx.deinit();

    const flags = try convert.fromSexp([]const na.Logical, &ctx, raw(&logicals), "`x`");
    try std.testing.expectEqual(na.Logical.TRUE, flags[0]);
    try std.testing.expect(flags[1].isNa());
    try std.testing.expectEqual(@intFromPtr(&logicals.integers[0]), @intFromPtr(flags.ptr));

    const labels = try convert.fromSexp([]const ?[]const u8, &ctx, raw(&strings), "`x`");
    try std.testing.expectEqualStrings("z", labels[0].?);
    try std.testing.expect(labels[1] == null);

    try std.testing.expectError(es.Error.RZigError, convert.fromSexp([]const na.Logical, &ctx, raw(&numbers), "`x`"));
    try std.testing.expectEqualStrings("rzig: `x` must be a logical vector; got double", es.take());
}

test "optional strings accept NA and NULL as null" {
    es.reset();
    var na_string = FakeSexp{ .kind = c.STRSXP, .length = 1 };
    na_string.strings = .{ &mock_na_string, null };
    var na_logical = FakeSexp{ .kind = c.LGLSXP, .length = 1, .integers = .{ std.math.minInt(c_int), 0 } };
    var text = FakeSexp{ .kind = c.CHARSXP, .length = 1, .text = "ok" };
    var present = FakeSexp{ .kind = c.STRSXP, .length = 1 };
    present.strings = .{ &text, null };
    var number = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 1, 0 } };
    var ctx = Ctx.init();
    defer ctx.deinit();

    try std.testing.expect((try convert.fromSexp(?[]const u8, &ctx, raw(&mock_nil), "`x`")) == null);
    try std.testing.expect((try convert.fromSexp(?[]const u8, &ctx, raw(&na_string), "`x`")) == null);
    try std.testing.expect((try convert.fromSexp(?[]const u8, &ctx, raw(&na_logical), "`x`")) == null);
    try std.testing.expectEqualStrings("ok", (try convert.fromSexp(?[]const u8, &ctx, raw(&present), "`x`")).?);
    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(?[]const u8, &ctx, raw(&number), "`x`"));
    try std.testing.expectEqualStrings("rzig: `x` must be a character vector of length 1; got double", es.take());
}

test "logical and character results can contain NA" {
    resetOutputMock();
    es.reset();
    var ctx = Ctx.init();
    defer ctx.deinit();
    var stack = protect.Stack.init();
    defer stack.deinit();

    const pair: []const na.Logical = &.{ .FALSE, .NA };
    const logical_result = try convert.toSexp(&stack, &ctx, pair);
    try std.testing.expectEqual(@as(c_int, c.LGLSXP), TYPEOF(logical_result));
    try std.testing.expectEqualSlices(c_int, &.{ c.FALSE, std.math.minInt(c_int) }, &mutableFake(logical_result).integers);
    stack.unwindAll();

    const labels: []const ?[]const u8 = &.{ "a", null };
    const string_result = try convert.toSexp(&stack, &ctx, labels);
    const fake = mutableFake(string_result);
    try std.testing.expectEqualStrings("a", std.mem.span(fake.strings[0].?.text.?));
    try std.testing.expect(raw(fake.strings[1].?) == R_NaString);
    stack.unwindAll();

    resetOutputMock();
    const invalid: []const ?[]const u8 = &.{ null, "\xff" };
    try std.testing.expectError(es.Error.RZigError, convert.toSexp(&stack, &ctx, invalid));
    try std.testing.expectEqualStrings("rzig: returned string at position 2 is not valid UTF-8", es.take());
    try std.testing.expectEqual(@as(usize, 0), mock_object_count);
}

test "complex scalars and vectors are read in R's layout" {
    es.reset();
    var values = FakeSexp{ .kind = c.CPLXSXP, .length = 2 };
    values.complexes = .{ .{ .r = 1, .i = -2 }, .{ .r = 3, .i = 4 } };
    var one = FakeSexp{ .kind = c.CPLXSXP, .length = 1 };
    one.complexes = .{ .{ .r = 0.5, .i = 1.5 }, .{ .r = 0, .i = 0 } };
    var real = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ 2.5, 0 } };
    var missing = FakeSexp{ .kind = c.REALSXP, .length = 1, .reals = .{ mock_na_real, 0 } };
    var text = FakeSexp{ .kind = c.STRSXP, .length = 1 };
    var ctx = Ctx.init();
    defer ctx.deinit();

    const slice = try convert.fromSexp([]const complex.Complex, &ctx, raw(&values), "`z`");
    try std.testing.expectEqual(@as(usize, 2), slice.len);
    try std.testing.expectEqual(@as(f64, -2), slice[0].im);
    try std.testing.expectEqual(@as(f64, 3), slice[1].re);
    try std.testing.expectEqual(@intFromPtr(&values.complexes[0]), @intFromPtr(slice.ptr));

    const scalar = try convert.fromSexp(complex.Complex, &ctx, raw(&one), "`z`");
    try std.testing.expectEqual(@as(f64, 1.5), scalar.im);
    const promoted = try convert.fromSexp(complex.Complex, &ctx, raw(&real), "`z`");
    try std.testing.expectEqual(@as(f64, 2.5), promoted.re);
    try std.testing.expectEqual(@as(f64, 0), promoted.im);

    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(complex.Complex, &ctx, raw(&missing), "`z`"));
    try std.testing.expectEqualStrings("rzig: `z` cannot be NA", es.take());
    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(complex.Complex, &ctx, raw(&values), "`z`"));
    try std.testing.expectEqualStrings("rzig: `z` must have length 1; got length 2", es.take());
    try std.testing.expectError(es.Error.RZigError, convert.fromSexp([]const complex.Complex, &ctx, raw(&real), "`z`"));
    try std.testing.expectEqualStrings("rzig: `z` must be a complex vector; got double; use as.complex() in R", es.take());
    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(complex.Complex, &ctx, raw(&text), "`z`"));
    try std.testing.expectEqualStrings(
        "rzig: `z` must be a complex, double, or integer vector of length 1; got character",
        es.take(),
    );
}

test "raw vectors are borrowed and returned as raw" {
    resetOutputMock();
    es.reset();
    var bytes = FakeSexp{ .kind = c.RAWSXP, .length = 3, .bytes = .{ 0x01, 0xfe, 0x7f, 0 } };
    var text = FakeSexp{ .kind = c.STRSXP, .length = 1 };
    var ctx = Ctx.init();
    defer ctx.deinit();

    const value = try convert.fromSexp(complex.Raw, &ctx, raw(&bytes), "`b`");
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0xfe, 0x7f }, value.data);
    try std.testing.expectEqual(@intFromPtr(&bytes.bytes[0]), @intFromPtr(value.data.ptr));
    try std.testing.expectError(es.Error.RZigError, convert.fromSexp(complex.Raw, &ctx, raw(&text), "`b`"));
    try std.testing.expectEqualStrings(
        "rzig: `b` must be a raw vector; got character; use as.raw() or charToRaw() in R",
        es.take(),
    );

    var stack = protect.Stack.init();
    defer stack.deinit();
    const returned = try convert.toSexp(&stack, &ctx, complex.Raw{ .data = &.{ 9, 8 } });
    try std.testing.expectEqual(@as(c_int, c.RAWSXP), TYPEOF(returned));
    try std.testing.expectEqualSlices(u8, &.{ 9, 8 }, mutableFake(returned).bytes[0..2]);
    stack.unwindAll();

    const scalar = try convert.toSexp(&stack, &ctx, complex.Complex{ .re = 1, .im = 2 });
    try std.testing.expectEqual(@as(c_int, c.CPLXSXP), TYPEOF(scalar));
    try std.testing.expectEqual(@as(f64, 2), mutableFake(scalar).complexes[0].i);
    stack.unwindAll();
}
