//! The identity of the calling thread and the end of a worker thread, without
//! Zig's thread-local storage (which a static archive in a Windows DLL does
//! not initialize reliably).

const std = @import("std");
const builtin = @import("builtin");

const windows = builtin.os.tag == .windows;

extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
extern "kernel32" fn ExitThread(code: u32) callconv(.winapi) noreturn;
extern "kernel32" fn Sleep(milliseconds: u32) callconv(.winapi) void;

/// A number that identifies the calling thread while it runs.
pub fn current() usize {
    if (comptime windows) return GetCurrentThreadId();
    const self = std.c.pthread_self();
    return switch (@typeInfo(@TypeOf(self))) {
        .pointer => @intFromPtr(self),
        .optional => @intFromPtr(self),
        .int => @intCast(self),
        else => @compileError("unsupported pthread_t"),
    };
}

/// End the calling thread. Its deferred cleanup does not run.
pub fn exit() noreturn {
    if (comptime windows) ExitThread(1);
    std.c.pthread_exit(null);
}

/// Wait about `microseconds` on the calling thread.
pub fn pause(microseconds: u32) void {
    if (comptime windows) {
        Sleep(@max(1, microseconds / 1000));
        return;
    }
    var request = std.mem.zeroes(std.c.timespec);
    const seconds = microseconds / 1_000_000;
    const nanoseconds = (microseconds % 1_000_000) * 1000;
    if (comptime @hasField(std.c.timespec, "sec")) {
        request.sec = @intCast(seconds);
        request.nsec = @intCast(nanoseconds);
    } else {
        request.tv_sec = @intCast(seconds);
        request.tv_nsec = @intCast(nanoseconds);
    }
    _ = std.c.nanosleep(&request, null);
}

test "the calling thread has a stable identity" {
    try std.testing.expectEqual(current(), current());
    pause(10);
}
