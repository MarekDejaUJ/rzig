//! Arena-backed metadata for attributes on returned numeric vectors.

const std = @import("std");
const Ctx = @import("alloc.zig").Ctx;
const es = @import("error_state.zig");

/// Attribute metadata copied into the per-call arena.
pub const Metadata = struct {
    names: ?[]const []const u8 = null,
    dim: ?[]const i32 = null,
    class: ?[]const []const u8 = null,
};

/// Wrap a numeric return value with optional `names`, `dim`, and `class`.
pub fn Attributed(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const rzig_attributed_inner = T;

        ctx: *Ctx,
        value: T,
        metadata_value: Metadata = .{},

        /// Start an attributed return value without calling the R API.
        pub fn init(ctx: *Ctx, value: T) Self {
            return .{ .ctx = ctx, .value = value };
        }

        /// Copy vector names into the call context.
        pub fn setNames(self: *Self, names: []const []const u8) es.Error!void {
            self.metadata_value.names = try copyStrings(self.ctx, names, "names");
        }

        /// Copy non-negative dimensions into the call context.
        pub fn setDim(self: *Self, dimensions: []const i32) es.Error!void {
            if (dimensions.len == 0) {
                return es.raise("rzig: `dim` must contain at least one dimension", .{});
            }
            for (dimensions, 0..) |dimension, index| {
                if (dimension < 0) {
                    return es.raise(
                        "rzig: `dim` value at position {d} must be non-negative; got {d}",
                        .{ index + 1, dimension },
                    );
                }
            }
            self.metadata_value.dim = try self.ctx.dupe(i32, dimensions);
        }

        /// Set one class string, copied into the call context.
        pub fn setClass(self: *Self, class_name: []const u8) es.Error!void {
            try validateString(class_name, "class", 1);
            const classes = try self.ctx.alloc([]const u8, 1);
            classes[0] = try self.ctx.dupe(u8, class_name);
            self.metadata_value.class = classes;
        }

        /// Copy an ordered class vector into the call context.
        pub fn setClasses(self: *Self, classes: []const []const u8) es.Error!void {
            if (classes.len == 0) {
                return es.raise("rzig: `class` must contain at least one string", .{});
            }
            self.metadata_value.class = try copyStrings(self.ctx, classes, "class");
        }

        /// Return copied metadata for boundary materialization.
        pub fn metadata(self: *const Self) Metadata {
            return self.metadata_value;
        }
    };
}

/// Report whether `T` is an attributed wrapper created by `Attributed`.
pub fn isAttributed(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "rzig_attributed_inner"),
        else => false,
    };
}

fn copyStrings(
    ctx: *Ctx,
    values: []const []const u8,
    comptime attribute_name: []const u8,
) es.Error![]const []const u8 {
    for (values, 0..) |value, index| try validateString(value, attribute_name, index + 1);
    const copied = try ctx.alloc([]const u8, values.len);
    for (values, copied) |value, *slot| slot.* = try ctx.dupe(u8, value);
    return copied;
}

fn validateString(value: []const u8, comptime attribute_name: []const u8, position: usize) es.Error!void {
    if (!std.unicode.utf8ValidateSlice(value)) {
        return es.raise(
            "rzig: `{s}` string at position {d} is not valid UTF-8",
            .{ attribute_name, position },
        );
    }
    if (std.mem.indexOfScalar(u8, value, 0) != null) {
        return es.raise(
            "rzig: `{s}` string at position {d} contains an embedded NUL byte",
            .{ attribute_name, position },
        );
    }
    if (value.len > std.math.maxInt(c_int)) {
        return es.raise(
            "rzig: `{s}` string at position {d} exceeds R's string limit",
            .{ attribute_name, position },
        );
    }
}

test "Attributed copies local metadata into the call context" {
    var ctx = Ctx.init();
    defer ctx.deinit();
    const values: []const f64 = &.{ 1, 2 };
    var result = Attributed([]const f64).init(&ctx, values);
    var first_name = [_]u8{ 'l', 'e', 'f', 't' };
    const names: []const []const u8 = &.{ &first_name, "right" };
    var dimensions = [_]i32{ 1, 2 };

    try result.setNames(names);
    try result.setDim(&dimensions);
    try result.setClass("rzig_values");
    first_name[0] = 'x';
    dimensions[0] = 2;

    try std.testing.expectEqualStrings("left", result.metadata().names.?[0]);
    try std.testing.expectEqualSlices(i32, &.{ 1, 2 }, result.metadata().dim.?);
    try std.testing.expectEqualStrings("rzig_values", result.metadata().class.?[0]);
}
