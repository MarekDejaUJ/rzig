const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

/// Add "values".
/// Preserves \ paths and "quotes".
/// @param left The left-hand value.
/// @param `right` The right-hand value, documented with backticks.
/// @return The sum.
/// @export
pub fn add_values(ctx: *rzig.Ctx, left: f64, right: f64) f64 {
    _ = ctx;
    return left + right;
}

/// @export
fn private_helper() void {}

/// Ordinary public helper without an export marker.
pub fn helper() void {}

pub fn undocumented() void {}

/// @export
pub fn @"r-name"(@"x-value": f64, @"if": f64) f64 {
    return @"x-value" + @"if";
}

/// Tag-first documentation after a blank doc line.
///
/// @export
pub fn tag_first(value: ?i32) ?i32 {
    return value;
}

/// @param values Documented without a description sentence.
/// @export
pub fn only_tags(values: []const f64) []const f64 {
    return values;
}

/// Documented across a plain comment and a blank line.
/// @export
// a plain comment between the documentation and the declaration

pub fn spaced(ctx: *rzig.Ctx, n: usize) rzig.Error![]f64 {
    return ctx.alloc(f64, n);
}

/// Multi-line parameters with comments inside the list.
/// @param data Observations in rows.
/// @export
pub fn multi(
    ctx: *rzig.Ctx,
    // a comment inside the parameter list
    data: rzig.Matrix,
    labels: []const []const u8, // trailing comment
    flag: bool,
) rzig.Error!rzig.Attributed([]const f64) {
    _ = flag;
    var result = rzig.Attributed([]const f64).init(ctx, data.data);
    try result.setNames(labels);
    return result;
}

/// Zero parameters and unicode: Łojasiewicz ż ∑.
/// @export
pub fn nothing() void {}

/// Name whose preferred alias collides with another export.
/// @export
pub fn foo(values: rzig.Mut([]f64), factor: f64) void {
    for (values.data) |*value| value.* *= factor;
}

/// Export named like the alias of `foo`.
/// @export
pub fn foo_(x: i32) i32 {
    return x;
}

/// Inline declaration.
/// @export
pub inline fn twice(value: f64) f64 {
    return 2 * value;
}

/// Returns a list.
/// @return A named list.
/// @export
pub fn summarize(ctx: *rzig.Ctx, values: []const f64) rzig.Error!rzig.List {
    var result = rzig.List.init(ctx);
    try result.put("count", @as(i32, @intCast(values.len)));
    return result;
}

comptime {
    rzig.registerModule(@This());
}
