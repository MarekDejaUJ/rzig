//! Classes: a struct marked `/// @class` becomes an R constructor and methods.
//!
//! `document()` registers `Constructor(T).call` as the R function `<T>`, which
//! runs `T.init` and returns an `rzig.External(T)`, and `Method(T, name).call`
//! as `<T>_<name>`, which receives that object and runs the method on its
//! value. The adapters for each number of arguments are generated in
//! `generated/arity.zig`, because Zig cannot build a function body with a
//! comptime-computed parameter count.

const std = @import("std");
const compat = @import("compat.zig");
const arity = @import("generated/arity.zig");
const es = @import("error_state.zig");
const Ctx = @import("alloc.zig").Ctx;
const External = @import("external.zig").External;

/// The registered function that creates an object of class `T` with `T.init`.
pub fn Constructor(comptime T: type) type {
    if (!@hasDecl(T, "init")) {
        @compileError("rzig: class " ++ @typeName(T) ++ " needs `pub fn init` to create its objects");
    }
    const info = fnInfo(@TypeOf(T.init), @typeName(T) ++ ".init");
    return arity.Constructor(compat.paramCount(info) - constructorOffset(info), T);
}

/// The registered function that runs the method `name` on an object of class `T`.
pub fn Method(comptime T: type, comptime name: []const u8) type {
    const info = fnInfo(@TypeOf(@field(T, name)), @typeName(T) ++ "." ++ name);
    return arity.Method(compat.paramCount(info) - methodOffset(T, info, name), T, name);
}

pub fn fnInfo(comptime F: type, comptime what: []const u8) compat.Type.Fn {
    return switch (@typeInfo(F)) {
        .@"fn" => |info| info,
        else => @compileError("rzig: " ++ what ++ " is not a function"),
    };
}

/// The parameters of `T.init` before its R arguments: `ctx: *rzig.Ctx`, if any.
pub fn constructorOffset(comptime info: compat.Type.Fn) usize {
    return if (compat.paramCount(info) > 0 and compat.paramType(info, 0) == *Ctx) 1 else 0;
}

/// The parameters of a method before its R arguments: the receiver, and
/// `ctx: *rzig.Ctx` when it follows the receiver.
pub fn methodOffset(comptime T: type, comptime info: compat.Type.Fn, comptime name: []const u8) usize {
    const what = @typeName(T) ++ "." ++ name;
    if (compat.paramCount(info) == 0) {
        @compileError("rzig: method " ++ what ++ " needs a receiver: `self: *" ++ @typeName(T) ++ "`");
    }
    const Self = compat.paramType(info, 0) orelse @compileError("rzig: the receiver of " ++ what ++ " is generic");
    if (Self != *T and Self != *const T and Self != T) {
        @compileError("rzig: the first parameter of method " ++ what ++ " must be `self: *" ++
            @typeName(T) ++ "`, `self: *const " ++ @typeName(T) ++ "` or `self: " ++ @typeName(T) ++ "`");
    }
    return if (compat.paramCount(info) > 1 and compat.paramType(info, 1) == *Ctx) 2 else 1;
}

/// The receiver of a method, from the value of the R object.
pub inline fn receiver(comptime T: type, comptime info: compat.Type.Fn, object: External(T)) Param(info, 0) {
    return if (comptime Param(info, 0) == T) object.ptr.* else object.ptr;
}

/// Parameter `index` of a function description.
pub fn Param(comptime info: compat.Type.Fn, comptime index: usize) type {
    return compat.paramType(info, index) orelse @compileError("rzig: methods of classes cannot have generic parameters");
}

/// The return type of a function description.
pub fn Return(comptime info: compat.Type.Fn) type {
    return info.return_type orelse @compileError("rzig: methods of classes need a concrete return type");
}

/// The value made by `T.init`, which returns `T` or `rzig.Error!T`.
pub inline fn initialized(comptime T: type, made: anytype) es.Error!T {
    const Made = @TypeOf(made);
    if (comptime Made == T) return made;
    if (comptime @typeInfo(Made) == .error_union and @typeInfo(Made).error_union.payload == T) return made;
    @compileError("rzig: " ++ @typeName(T) ++ ".init must return " ++ @typeName(T) ++ " or rzig.Error!" ++ @typeName(T));
}

test "constructor and method adapters run init and the methods on the value" {
    const Counter = struct {
        count: i32 = 0,
        step: i32,

        pub fn init(step: i32) @This() {
            return .{ .step = step };
        }

        pub fn add(self: *@This(), times: i32) i32 {
            self.count += self.step * times;
            return self.count;
        }

        pub fn total(self: @This()) i32 {
            return self.count;
        }

        pub fn scaled(self: *const @This(), ctx: *Ctx, factor: i32) es.Error!i32 {
            _ = ctx;
            return self.count * factor;
        }
    };
    var ctx = Ctx.init();
    defer ctx.deinit();
    const object = try Constructor(Counter).call(&ctx, 3);
    try std.testing.expectEqual(@as(i32, 6), Method(Counter, "add").call(&ctx, object, 2));
    try std.testing.expectEqual(@as(i32, 6), Method(Counter, "total").call(&ctx, object));
    try std.testing.expectEqual(@as(i32, 12), try Method(Counter, "scaled").call(&ctx, object, 2));
}
