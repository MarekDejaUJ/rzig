const registration = @import("registration");

fn tooMany() void {}

comptime {
    _ = registration.wrapperForArity(33, tooMany, "too_many");
}
