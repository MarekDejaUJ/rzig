//! Element types of R complex and raw vectors.

const std = @import("std");

/// One element of an R complex vector, with the memory layout of R's
/// `Rcomplex` (`std.math.Complex(f64)` is not an extern struct, so its layout
/// is not guaranteed). Slices of it borrow R complex vectors without a copy.
pub const Complex = extern struct {
    re: f64,
    im: f64,

    /// Convert from `std.math.Complex(f64)`.
    pub fn fromStd(value: std.math.Complex(f64)) Complex {
        return .{ .re = value.re, .im = value.im };
    }

    /// Convert to `std.math.Complex(f64)`, which provides complex arithmetic.
    pub fn toStd(self: Complex) std.math.Complex(f64) {
        return std.math.Complex(f64).init(self.re, self.im);
    }

    /// Whether either part is NaN, which is when R's `is.na()` is TRUE.
    pub fn isNa(self: Complex) bool {
        return std.math.isNan(self.re) or std.math.isNan(self.im);
    }
};

/// The bytes of an R raw vector. `[]const u8` means a UTF-8 string, so raw
/// vectors have their own type; as an input the bytes are borrowed.
pub const Raw = struct {
    data: []const u8,
};

test "Complex converts to and from std.math.Complex" {
    const value = Complex{ .re = 3, .im = -4 };
    const doubled = Complex.fromStd(value.toStd().mul(std.math.Complex(f64).init(2, 0)));
    try std.testing.expectEqual(@as(f64, 6), doubled.re);
    try std.testing.expectEqual(@as(f64, -8), doubled.im);
    try std.testing.expectEqual(@as(f64, 5), std.math.complex.abs(value.toStd()));
    try std.testing.expect((Complex{ .re = std.math.nan(f64), .im = 0 }).isNa());
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Complex));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Complex, "im"));
}
