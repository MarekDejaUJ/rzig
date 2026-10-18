//! Last-resort handling for Zig panics reached from R.
//!
//! The default Zig handler terminates the process. RZig instead reports the
//! safety failure through R and raises an R error, allowing the surrounding R
//! evaluation context to recover. This path is allocation-free and deliberately
//! minimal because program state may already be compromised.

const std = @import("std");
const compat = @import("compat.zig");
const c = @import("c/abi.zig");
const thread_identity = @import("thread_identity.zig");

const MESSAGE_CAPACITY = 1024;

/// Zig 0.16 panic namespace installed by the RZig root module.
pub const Panic = std.debug.FullPanic(report);

// The thread that entered R through the boundary, and the panic of a worker
// thread of rzig.parallelFor: a worker cannot call R, so it records its
// message, ends its own thread, and the calling thread raises the R error.
var r_thread = std.atomic.Value(usize).init(0);
var worker_exits = std.atomic.Value(usize).init(0);
var worker_state = std.atomic.Value(u8).init(0);
var worker_message: [MESSAGE_CAPACITY]u8 = undefined;
var worker_message_len: usize = 0;

/// Remember the R thread; called when the boundary is entered.
pub fn noteRThread() void {
    r_thread.store(thread_identity.current(), .monotonic);
}

/// Whether the calling thread is the one that entered R (true before any call).
pub fn onRThread() bool {
    const r_id = r_thread.load(.monotonic);
    return r_id == 0 or thread_identity.current() == r_id;
}

/// Forget earlier worker panics; called before workers start.
pub fn beginWorkers() void {
    worker_exits.store(0, .monotonic);
    worker_state.store(0, .release);
}

/// The number of workers that ended because of a panic.
pub fn workerExits() usize {
    return worker_exits.load(.acquire);
}

/// The message of the first worker panic since `beginWorkers`, if any.
pub fn workerPanicked() ?[]const u8 {
    if (worker_state.load(.acquire) != 2) return null;
    return worker_message[0..worker_message_len];
}

fn report(message: []const u8, first_trace_addr: ?usize) noreturn {
    @branchHint(.cold);

    const r_id = r_thread.load(.monotonic);
    if (r_id != 0 and thread_identity.current() != r_id) {
        if (worker_state.cmpxchgStrong(0, 1, .acq_rel, .monotonic) == null) {
            const length = @min(message.len, worker_message.len);
            @memcpy(worker_message[0..length], message[0..length]);
            worker_message_len = length;
            worker_state.store(2, .release);
        }
        _ = worker_exits.fetchAdd(1, .acq_rel);
        thread_identity.exit();
    }

    var storage: [MESSAGE_CAPACITY]u8 = undefined;
    const rendered: [:0]const u8 = if (first_trace_addr) |address|
        compat.bufPrintZ(
            &storage,
            "rzig: internal Zig safety failure: {s}\ntrace origin: 0x{x}",
            .{ message, address },
        ) catch "rzig: internal Zig safety failure"
    else
        compat.bufPrintZ(
            &storage,
            "rzig: internal Zig safety failure: {s}",
            .{message},
        ) catch "rzig: internal Zig safety failure";

    c.REprintf("%s\n", rendered.ptr);
    c.Rf_error("%s", rendered.ptr);
}
