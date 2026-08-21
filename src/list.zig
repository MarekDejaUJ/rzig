//! Arena-backed builder for named R lists.
//!
//! Building a List performs no R API calls. The boundary materializes all
//! entries into one named VECSXP after the user function has returned.

const std = @import("std");
const Ctx = @import("alloc.zig").Ctx;
const es = @import("error_state.zig");
const sexp = @import("sexp.zig");

/// One value accepted by `List.put` and materialized at the R boundary.
pub const Value = union(enum) {
    nil,
    real: f64,
    integer: i32,
    logical: bool,
    reals: []const f64,
    integers: []const i32,
    logicals: []const bool,
    string: []const u8,
    strings: []const []const u8,
    sexp: sexp.Sexp,

    fn from(value: anytype) Value {
        const T = @TypeOf(value);
        if (comptime T == f64) return .{ .real = value };
        if (comptime T == i32) return .{ .integer = value };
        if (comptime T == bool) return .{ .logical = value };
        if (comptime T == []const f64 or T == []f64) return .{ .reals = value };
        if (comptime T == []const i32 or T == []i32) return .{ .integers = value };
        if (comptime T == []const bool or T == []bool) return .{ .logicals = value };
        if (comptime T == []const u8) return .{ .string = value };
        if (comptime T == []const []const u8 or T == [][]const u8) return .{ .strings = value };
        if (comptime T == sexp.Sexp) return .{ .sexp = value };
        if (comptime isStringLiteral(T)) return .{ .string = value[0..] };
        if (comptime T == comptime_float) return .{ .real = @as(f64, value) };
        if (comptime T == comptime_int) return .{ .integer = @as(i32, value) };

        return switch (@typeInfo(T)) {
            .optional => if (value) |present| from(present) else .nil,
            .null => .nil,
            else => @compileError(
                "rzig.List.put: unsupported value type '" ++ @typeName(T) ++ "'.\n" ++
                    "  supported: f64, i32, bool, atomic vector slices, []const u8, ?T, rzig.Sexp",
            ),
        };
    }
};

/// One named value retained in a `List` until boundary conversion.
pub const Entry = struct {
    name: []const u8,
    value: Value,
};

/// Builds a named R list without allocating or calling into R.
pub const List = struct {
    ctx: *Ctx,
    entries: std.ArrayList(Entry) = .empty,

    /// Start an empty list whose bookkeeping is owned by `ctx`.
    pub fn init(ctx: *Ctx) List {
        return .{ .ctx = ctx };
    }

    /// Append a named value supported by RZig's return-value marshaller.
    pub fn put(self: *List, name: []const u8, value: anytype) es.Error!void {
        try validateName(name, self.entries.items.len + 1);
        const owned_name = try self.ctx.dupe(u8, name);
        self.entries.append(self.ctx.allocator(), .{
            .name = owned_name,
            .value = Value.from(value),
        }) catch return es.raise("rzig: out of memory adding list entry `{s}`", .{name});
    }

    /// Return the ordered entries for boundary materialization.
    pub fn items(self: *const List) []const Entry {
        return self.entries.items;
    }
};

fn validateName(name: []const u8, position: usize) es.Error!void {
    if (!std.unicode.utf8ValidateSlice(name)) {
        return es.raise("rzig: list name at position {d} is not valid UTF-8", .{position});
    }
    if (std.mem.indexOfScalar(u8, name, 0) != null) {
        return es.raise("rzig: list name at position {d} contains an embedded NUL byte", .{position});
    }
    if (name.len > std.math.maxInt(c_int)) {
        return es.raise("rzig: list name at position {d} exceeds R's string limit", .{position});
    }
}

fn isStringLiteral(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |pointer| pointer.size == .one and switch (@typeInfo(pointer.child)) {
            .array => |array| array.child == u8,
            else => false,
        },
        else => false,
    };
}

test "List copies names and keeps entries in insertion order" {
    var ctx = Ctx.init();
    defer ctx.deinit();
    var result = List.init(&ctx);
    var mutable_name = [_]u8{ 'v', 'a', 'l', 'u', 'e' };

    try result.put(&mutable_name, @as(f64, 2.5));
    try result.put("label", "ready");
    mutable_name[0] = 'x';

    try std.testing.expectEqual(@as(usize, 2), result.items().len);
    try std.testing.expectEqualStrings("value", result.items()[0].name);
    try std.testing.expectEqual(@as(f64, 2.5), result.items()[0].value.real);
    try std.testing.expectEqualStrings("ready", result.items()[1].value.string);
}
