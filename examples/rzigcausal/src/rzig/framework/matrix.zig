//! Column-major views of R matrices.

const std = @import("std");

/// Read-only column-major view of an R matrix whose elements have type `T`:
/// `f64` (double), `i32` (integer, with NA as `std.math.minInt(i32)`) or
/// `bool` (logical, without NA). Double and integer data are borrowed from R
/// for the duration of one call; logical data are copied, because R stores
/// them as integers.
pub fn MatrixOf(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The element type, which also marks the type as an R matrix view.
        pub const rzig_matrix_element = T;

        /// Column-major elements.
        data: []const T,
        /// Number of rows.
        nrow: usize,
        /// Number of columns.
        ncol: usize,

        /// The element in zero-based row `row_index` and column `column_index`.
        pub fn at(self: Self, row_index: usize, column_index: usize) T {
            std.debug.assert(row_index < self.nrow and column_index < self.ncol);
            return self.data[column_index * self.nrow + row_index];
        }

        /// Zero-based column `index`: a slice of `nrow` elements.
        pub fn column(self: Self, index: usize) []const T {
            std.debug.assert(index < self.ncol);
            return self.data[index * self.nrow ..][0..self.nrow];
        }
    };
}

/// Writable column-major view of the duplicate that `rzig.Mut` makes of an
/// R matrix. The duplicate keeps the attributes of the input (`dim`,
/// `dimnames`, `class`) and is the value the R function returns.
pub fn MutableMatrixOf(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Column-major elements of the duplicate.
        data: []T,
        /// Number of rows.
        nrow: usize,
        /// Number of columns.
        ncol: usize,

        /// The element in zero-based row `row_index` and column `column_index`.
        pub fn at(self: Self, row_index: usize, column_index: usize) T {
            std.debug.assert(row_index < self.nrow and column_index < self.ncol);
            return self.data[column_index * self.nrow + row_index];
        }

        /// Store `value` in zero-based row `row_index` and column `column_index`.
        pub fn set(self: Self, row_index: usize, column_index: usize, value: T) void {
            std.debug.assert(row_index < self.nrow and column_index < self.ncol);
            self.data[column_index * self.nrow + row_index] = value;
        }

        /// Zero-based column `index`: a writable slice of `nrow` elements.
        pub fn column(self: Self, index: usize) []T {
            std.debug.assert(index < self.ncol);
            return self.data[index * self.nrow ..][0..self.nrow];
        }

        /// The same elements as a read-only view.
        pub fn view(self: Self) MatrixOf(T) {
            return .{ .data = self.data, .nrow = self.nrow, .ncol = self.ncol };
        }
    };
}

/// Borrowed view of an R double matrix.
pub const Matrix = MatrixOf(f64);
/// Borrowed view of an R integer matrix.
pub const IntMatrix = MatrixOf(i32);
/// Copied view of an R logical matrix without NA.
pub const BoolMatrix = MatrixOf(bool);

/// Report whether `T` is one of the matrix views created by `MatrixOf`.
pub fn isMatrix(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "rzig_matrix_element"),
        else => false,
    };
}

test "views index column-major data by row and column" {
    const values = [_]f64{ 1, 2, 3, 4, 5, 6 };
    const view = Matrix{ .data = &values, .nrow = 2, .ncol = 3 };
    try std.testing.expectEqual(@as(f64, 1), view.at(0, 0));
    try std.testing.expectEqual(@as(f64, 2), view.at(1, 0));
    try std.testing.expectEqual(@as(f64, 5), view.at(0, 2));
    try std.testing.expectEqualSlices(f64, &.{ 3, 4 }, view.column(1));

    var writable = [_]i32{ 1, 2, 3, 4 };
    const mutable = MutableMatrixOf(i32){ .data = &writable, .nrow = 2, .ncol = 2 };
    mutable.set(1, 1, 40);
    mutable.column(0)[0] = 10;
    try std.testing.expectEqualSlices(i32, &.{ 10, 2, 3, 40 }, &writable);
    try std.testing.expect(isMatrix(Matrix) and isMatrix(IntMatrix) and isMatrix(BoolMatrix));
    try std.testing.expect(!isMatrix(MutableMatrixOf(f64)) and !isMatrix([]const f64));
}
