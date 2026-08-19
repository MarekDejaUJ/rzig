const std = @import("std");
const builtin = @import("builtin");
const rzig = @import("rzig");

/// Route ReleaseSafe failures through R while retaining Zig test behavior.
pub const panic = if (builtin.is_test)
    std.debug.FullPanic(std.debug.defaultPanic)
else
    rzig.Panic;

/// Return a friendly greeting.
/// @export
pub fn hello_zig(ctx: *rzig.Ctx, name: []const u8) rzig.Error![]const u8 {
    return std.fmt.allocPrint(ctx.allocator(), "Hello, {s}!", .{name}) catch
        rzig.raise("out of memory while building the greeting", .{});
}

comptime {
    rzig.registerModule(@This());
}
