//! Compile-time reflection helpers for the type descriptions of Zig 0.16
//! (`std.builtin.Type`) and Zig 0.17 (`std.lang.Type`).
//!
//! Zig 0.17 moves the type descriptions to `std.lang.Type` and stores the
//! parameters of a function and the fields of a struct or union in
//! struct-of-arrays style. The helpers below read either layout, so the
//! framework compiles with both release series.
const std = @import("std");

/// The type-description namespace of the running compiler.
pub const Type = if (@hasDecl(std, "lang")) std.lang.Type else std.builtin.Type;

/// Format into `buf` and terminate the result with a zero byte.
///
/// `std.fmt.bufPrintZ` exists in Zig 0.16 and not in Zig 0.17.
pub fn bufPrintZ(buf: []u8, comptime fmt: []const u8, args: anytype) std.fmt.BufPrintError![:0]u8 {
    const written = try std.fmt.bufPrint(buf[0 .. buf.len - 1], fmt, args);
    buf[written.len] = 0;
    return buf[0..written.len :0];
}

/// Number of parameters of a function description.
pub fn paramCount(comptime info: Type.Fn) usize {
    return if (@hasField(Type.Fn, "param_types")) info.param_types.len else info.params.len;
}

/// Type of parameter `index` of a function description, `null` for a generic parameter.
pub fn paramType(comptime info: Type.Fn, comptime index: usize) ?type {
    return if (@hasField(Type.Fn, "param_types")) info.param_types[index] else info.params[index].type;
}

/// Whether a pointer description is `const`.
pub fn pointerIsConst(comptime info: Type.Pointer) bool {
    return if (@hasField(Type.Pointer, "attrs")) info.attrs.@"const" else info.is_const;
}

/// Whether a pointer description is `allowzero`.
pub fn pointerIsAllowzero(comptime info: Type.Pointer) bool {
    return if (@hasField(Type.Pointer, "attrs")) info.attrs.@"allowzero" else info.is_allowzero;
}

/// Number of fields of a struct or union description.
pub fn fieldCount(comptime info: anytype) usize {
    return if (@hasField(@TypeOf(info), "field_names")) info.field_names.len else info.fields.len;
}

/// Field types of a struct or union description, in declaration order.
pub fn fieldTypes(comptime info: anytype) []const type {
    if (@hasField(@TypeOf(info), "field_types")) return info.field_types;
    comptime var types: [info.fields.len]type = undefined;
    inline for (info.fields, 0..) |field, index| types[index] = field.type;
    const result = types;
    return &result;
}

test "function descriptions" {
    const F = fn (*u8, usize) void;
    const info = @typeInfo(F).@"fn";
    try std.testing.expectEqual(@as(usize, 2), paramCount(info));
    try std.testing.expectEqual(@as(?type, *u8), paramType(info, 0));
    try std.testing.expectEqual(@as(?type, usize), paramType(info, 1));
}

test "pointer descriptions" {
    try std.testing.expect(pointerIsConst(@typeInfo(*const u8).pointer));
    try std.testing.expect(!pointerIsConst(@typeInfo(*u8).pointer));
    try std.testing.expect(pointerIsAllowzero(@typeInfo(*allowzero u8).pointer));
    try std.testing.expect(!pointerIsAllowzero(@typeInfo(*u8).pointer));
}

test "field descriptions" {
    const S = struct { a: u8, b: f64 };
    const info = @typeInfo(S).@"struct";
    try std.testing.expectEqual(@as(usize, 2), fieldCount(info));
    try std.testing.expect(comptime fieldTypes(info)[0] == u8);
    try std.testing.expect(comptime fieldTypes(info)[1] == f64);
    const U = union { a: u8, b: f64 };
    try std.testing.expectEqual(@as(usize, 2), fieldCount(@typeInfo(U).@"union"));
    try std.testing.expect(comptime fieldTypes(@typeInfo(U).@"union")[1] == f64);
}

test "zero-terminated formatting" {
    var buf: [16]u8 = undefined;
    const text = try bufPrintZ(&buf, "{d}-{s}", .{ 7, "ab" });
    try std.testing.expectEqualStrings("7-ab", text);
    try std.testing.expectEqual(@as(u8, 0), buf[text.len]);
    try std.testing.expectError(error.NoSpaceLeft, bufPrintZ(&buf, "{s}", .{"0123456789abcdef"}));
}
