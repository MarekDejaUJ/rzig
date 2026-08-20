//! Borrowed view of an R double matrix.

/// Column-major numeric matrix borrowed for the duration of one R call.
pub const Matrix = struct {
    /// Column-major elements borrowed from the R matrix.
    data: []const f64,
    /// Number of rows.
    nrow: usize,
    /// Number of columns.
    ncol: usize,
};
