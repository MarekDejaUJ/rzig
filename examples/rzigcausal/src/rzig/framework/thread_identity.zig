//! The identity of the calling thread, the end of a worker thread, and the
//! signal of finished workers, without Zig's thread-local storage (which a
//! static archive in a Windows DLL does not initialize reliably).

const std = @import("std");
const builtin = @import("builtin");

const windows = builtin.os.tag == .windows;

extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
extern "kernel32" fn ExitThread(code: u32) callconv(.winapi) noreturn;
extern "kernel32" fn Sleep(milliseconds: u32) callconv(.winapi) void;
extern "kernel32" fn AcquireSRWLockExclusive(lock: *WindowsLock) callconv(.winapi) void;
extern "kernel32" fn ReleaseSRWLockExclusive(lock: *WindowsLock) callconv(.winapi) void;
extern "kernel32" fn SleepConditionVariableSRW(
    condition: *WindowsCondition,
    lock: *WindowsLock,
    milliseconds: u32,
    flags: u32,
) callconv(.winapi) i32;
extern "kernel32" fn WakeAllConditionVariable(condition: *WindowsCondition) callconv(.winapi) void;

const WindowsLock = extern struct { ptr: ?*anyopaque = null };
const WindowsCondition = extern struct { ptr: ?*anyopaque = null };

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

/// The number of worker threads that have finished, which the calling thread
/// waits on. A worker calls `finish()` as its last action; `wait()` returns as
/// soon as the count reaches its target, or after about `milliseconds`, so
/// the calling thread neither oversleeps the workers nor misses an interrupt.
pub const Completion = struct {
    lock: Lock = .{},
    condition: Condition = .{},
    count: usize = 0,

    const Lock = if (windows) WindowsLock else std.c.pthread_mutex_t;
    const Condition = if (windows) WindowsCondition else std.c.pthread_cond_t;

    /// Count one finished worker and wake the waiting thread.
    pub fn finish(self: *Completion) void {
        self.acquire();
        self.count += 1;
        if (comptime windows) {
            WakeAllConditionVariable(&self.condition);
        } else {
            _ = std.c.pthread_cond_broadcast(&self.condition);
        }
        self.release();
    }

    /// Wait until `target` workers have finished or about `milliseconds`
    /// have passed, and return the number of finished workers.
    pub fn wait(self: *Completion, target: usize, milliseconds: u32) usize {
        self.acquire();
        defer self.release();
        if (self.count < target) {
            if (comptime windows) {
                _ = SleepConditionVariableSRW(&self.condition, &self.lock, milliseconds, 0);
            } else {
                var deadline = std.mem.zeroes(std.c.timespec);
                _ = std.c.clock_gettime(.REALTIME, &deadline);
                addMilliseconds(&deadline, milliseconds);
                _ = std.c.pthread_cond_timedwait(&self.condition, &self.lock, &deadline);
            }
        }
        return self.count;
    }

    fn acquire(self: *Completion) void {
        if (comptime windows) {
            AcquireSRWLockExclusive(&self.lock);
        } else {
            _ = std.c.pthread_mutex_lock(&self.lock);
        }
    }

    fn release(self: *Completion) void {
        if (comptime windows) {
            ReleaseSRWLockExclusive(&self.lock);
        } else {
            _ = std.c.pthread_mutex_unlock(&self.lock);
        }
    }
};

fn addMilliseconds(time: *std.c.timespec, milliseconds: u32) void {
    const per_second: i64 = 1_000_000_000;
    if (comptime @hasField(std.c.timespec, "sec")) {
        const nanoseconds = @as(i64, @intCast(time.nsec)) + @as(i64, milliseconds) * 1_000_000;
        time.sec += @intCast(@divFloor(nanoseconds, per_second));
        time.nsec = @intCast(@mod(nanoseconds, per_second));
    } else {
        const nanoseconds = @as(i64, @intCast(time.tv_nsec)) + @as(i64, milliseconds) * 1_000_000;
        time.tv_sec += @intCast(@divFloor(nanoseconds, per_second));
        time.tv_nsec = @intCast(@mod(nanoseconds, per_second));
    }
}

test "a completion returns at its target and after its timeout" {
    var completion: Completion = .{};
    try std.testing.expectEqual(@as(usize, 0), completion.wait(1, 1));
    completion.finish();
    try std.testing.expectEqual(@as(usize, 1), completion.wait(1, 1000));
    const Worker = struct {
        fn run(target: *Completion) void {
            pause(2000);
            target.finish();
        }
    };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&completion});
    var finished = completion.wait(2, 10_000);
    while (finished < 2) finished = completion.wait(2, 10_000);
    thread.join();
    try std.testing.expectEqual(@as(usize, 2), finished);
}

test "the calling thread has a stable identity" {
    try std.testing.expectEqual(current(), current());
    pause(10);
}
