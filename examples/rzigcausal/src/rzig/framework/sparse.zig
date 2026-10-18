//! Borrowed views of sparse matrices of the Matrix package.

const std = @import("std");

/// A column-compressed sparse double matrix (`Matrix::dgCMatrix`), borrowed
/// for the duration of one call. The values of column `j` are
/// `values[col_pointers[j]..col_pointers[j + 1]]` in the rows
/// `row_indices[...]` (0-based, increasing within a column). Every index is
/// checked when the matrix arrives, so the slices can be read without
/// further checks.
pub const CscMatrix = struct {
    /// Row of each stored value (slot `i`).
    row_indices: []const i32,
    /// Start of each column in `row_indices` and `values`, plus the end (slot `p`).
    col_pointers: []const i32,
    /// The stored values (slot `x`).
    values: []const f64,
    /// Number of rows.
    nrow: usize,
    /// Number of columns.
    ncol: usize,

    /// The stored rows and values of zero-based column `index`.
    pub fn column(self: CscMatrix, index: usize) struct { rows: []const i32, values: []const f64 } {
        std.debug.assert(index < self.ncol);
        const start: usize = @intCast(self.col_pointers[index]);
        const end: usize = @intCast(self.col_pointers[index + 1]);
        return .{ .rows = self.row_indices[start..end], .values = self.values[start..end] };
    }

    /// The number of stored values.
    pub fn nnz(self: CscMatrix) usize {
        return self.values.len;
    }
};

/// Check the structure of the slots; returns a description of the first
/// problem, or `null`.
pub fn problem(row_indices: []const i32, col_pointers: []const i32, values_len: usize, nrow: usize, ncol: usize) ?[]const u8 {
    if (col_pointers.len != ncol + 1) return "slot p must have ncol + 1 entries";
    if (col_pointers[0] != 0) return "slot p must start at 0";
    if (row_indices.len != values_len) return "slots i and x must have the same length";
    const total = col_pointers[ncol];
    if (total < 0 or @as(usize, @intCast(total)) != values_len) return "the last entry of slot p must equal the number of values";
    for (0..ncol) |column_index| {
        const start = col_pointers[column_index];
        const end = col_pointers[column_index + 1];
        if (end < start) return "slot p must not decrease";
        var previous: i64 = -1;
        for (row_indices[@intCast(start)..@intCast(end)]) |row| {
            if (row < 0 or @as(usize, @intCast(row)) >= nrow) return "a row index in slot i is outside the matrix";
            if (row <= previous) return "the row indices of a column in slot i must increase";
            previous = row;
        }
    }
    return null;
}

test "slot checks find each kind of corruption" {
    const p = [_]i32{ 0, 2, 3 };
    const i = [_]i32{ 0, 2, 1 };
    try std.testing.expect(problem(&i, &p, 3, 3, 2) == null);
    try std.testing.expect(problem(&i, &.{ 0, 2 }, 3, 3, 2) != null);
    try std.testing.expect(problem(&.{ 0, 3, 1 }, &p, 3, 3, 2) != null);
    try std.testing.expect(problem(&.{ 2, 0, 1 }, &p, 3, 3, 2) != null);
    try std.testing.expect(problem(&i, &.{ 0, 3, 2 }, 3, 3, 2) != null);
    const view = CscMatrix{ .row_indices = &i, .col_pointers = &p, .values = &.{ 1, 2, 3 }, .nrow = 3, .ncol = 2 };
    try std.testing.expectEqualSlices(i32, &.{ 0, 2 }, view.column(0).rows);
    try std.testing.expectEqual(@as(usize, 3), view.nnz());
}
