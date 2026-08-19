const std = @import("std");

fn identity(value: c_int) callconv(.c) c_int {
    return value;
}

comptime {
    const fn_info = @typeInfo(@TypeOf(identity)).@"fn";
    if (fn_info.params.len != 1) {
        @compileError("syntax probe: function reflection returned wrong arity");
    }
    if (!fn_info.calling_convention.eql(.c)) {
        @compileError("syntax probe: expected the C calling convention");
    }
    @export(&identity, .{
        .name = "rzig_syntax_probe",
        .linkage = .strong,
    });
}

test "exported function remains callable from Zig" {
    try std.testing.expectEqual(@as(c_int, 7), identity(7));
}
