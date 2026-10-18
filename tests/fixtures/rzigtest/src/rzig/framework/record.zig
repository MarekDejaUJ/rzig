//! Named R lists and data frames read into Zig structs, and factors.

const std = @import("std");
const compat = @import("compat.zig");

/// A named R list read into the struct `T` (as an input) or built from it (as
/// a result). Each field takes the list entry of the same name; a field with
/// a default value or an optional type may be missing from the list. Field
/// names that are not Zig identifiers are written `@"max.iter"`. Unknown
/// entries of an input list are reported as a warning and ignored.
pub fn Record(comptime T: type) type {
    comptime validateFields(T, "rzig.Record");
    return struct {
        pub const rzig_record_inner = T;

        /// The fields read from, or written to, the R list.
        value: T,
    };
}

/// A data frame read into the struct `T`, whose fields are columns (slices,
/// `rzig.Factor`, or optional slices for columns that may be absent), or
/// built from it as a result, with `nrow` rows. Columns of an input that `T`
/// does not name are ignored.
pub fn DataFrame(comptime T: type) type {
    comptime validateFields(T, "rzig.DataFrame");
    return struct {
        pub const rzig_record_inner = T;
        pub const rzig_data_frame = {};

        /// The columns.
        value: T,
        /// The number of rows; ignored for a result, whose columns define it.
        nrow: usize = 0,
    };
}

/// An R factor: 1-based `codes` into `levels`, with NA as
/// `std.math.minInt(i32)`. As an input the codes are borrowed and the levels
/// copied; a result needs every code to be NA or from 1 to `levels.len`.
pub const Factor = struct {
    codes: []const i32,
    levels: []const []const u8,

    /// The level of element `index`, or `null` for NA.
    pub fn level(self: Factor, index: usize) ?[]const u8 {
        const code = self.codes[index];
        if (code == std.math.minInt(i32)) return null;
        return self.levels[@intCast(code - 1)];
    }
};

/// Report whether `T` is created by `Record` or `DataFrame`.
pub fn isRecord(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "rzig_record_inner"),
        else => false,
    };
}

/// Report whether `T` is created by `DataFrame`.
pub fn isDataFrame(comptime T: type) bool {
    return isRecord(T) and @hasDecl(T, "rzig_data_frame");
}

fn validateFields(comptime T: type, comptime what: []const u8) void {
    const info = switch (@typeInfo(T)) {
        .@"struct" => |info| info,
        else => @compileError(what ++ " needs a struct type; got '" ++ @typeName(T) ++ "'"),
    };
    if (info.is_tuple) @compileError(what ++ " needs a struct with named fields; got a tuple");
    if (compat.fieldCount(info) == 0) @compileError(what ++ " needs a struct with at least one field");
}

test "factor levels follow the codes" {
    const factor = Factor{ .codes = &.{ 2, std.math.minInt(i32), 1 }, .levels = &.{ "low", "high" } };
    try std.testing.expectEqualStrings("high", factor.level(0).?);
    try std.testing.expect(factor.level(1) == null);
    try std.testing.expectEqualStrings("low", factor.level(2).?);
    const Options = Record(struct { tolerance: f64 = 1e-8 });
    try std.testing.expect(isRecord(Options) and !isDataFrame(Options));
    try std.testing.expect(isDataFrame(DataFrame(struct { x: []const f64 })));
}
