//! Allocation-free error storage and warning delivery state.
//!
//! R errors and warnings can longjmp, so computation records them here and the
//! outer boundary emits them only after Zig cleanup. Every buffer is fixed-size
//! and thread-local; an error path never asks an allocator for memory.

const std = @import("std");

/// The single recoverable error value exposed by RZig.
pub const Error = error{RZigError};

const MESSAGE_CAPACITY = 1024;
const MAX_WARNINGS = 8;
const ELLIPSIS = "...";

threadlocal var error_buffer: [MESSAGE_CAPACITY]u8 = [_]u8{0} ** MESSAGE_CAPACITY;
threadlocal var error_length: usize = 0;

threadlocal var warning_buffers: [MAX_WARNINGS][MESSAGE_CAPACITY]u8 =
    [_][MESSAGE_CAPACITY]u8{[_]u8{0} ** MESSAGE_CAPACITY} ** MAX_WARNINGS;
threadlocal var warning_lengths: [MAX_WARNINGS]usize = [_]usize{0} ** MAX_WARNINGS;
threadlocal var warning_count: usize = 0;
threadlocal var warning_read: usize = 0;
threadlocal var warning_dropped: usize = 0;
threadlocal var overflow_buffer: [MESSAGE_CAPACITY]u8 = [_]u8{0} ** MESSAGE_CAPACITY;

/// Clear state at the beginning of an outer R call.
pub fn reset() void {
    error_length = 0;
    warning_count = 0;
    warning_read = 0;
    warning_dropped = 0;
}

/// Record an error message and return the single RZig error value.
///
/// One error value is deliberate: R errors are strings, and a richer Zig error
/// set would invite additional error exits. Messages longer than 1023 bytes are
/// truncated and end in an ellipsis.
pub fn raise(comptime format: []const u8, args: anytype) Error {
    error_length = writeMessage(&error_buffer, format, args);
    return Error.RZigError;
}

/// Take the current NUL-terminated error message and clear its logical slot.
///
/// The returned bytes remain valid until the next `raise` on this thread.
pub fn take() [:0]const u8 {
    if (error_length == 0) return "";
    const message = error_buffer[0..error_length :0];
    error_length = 0;
    return message;
}

/// Queue a warning without allocating or calling R.
///
/// At most eight full messages are retained per call. Further warnings are
/// counted and represented by one final summary message when the queue drains.
pub fn warn(comptime format: []const u8, args: anytype) void {
    if (warning_count == MAX_WARNINGS) {
        warning_dropped +|= 1;
        return;
    }

    warning_lengths[warning_count] = writeMessage(&warning_buffers[warning_count], format, args);
    warning_count += 1;
}

/// Take the next queued warning, or `null` once the queue is empty.
///
/// The returned bytes remain valid until the corresponding slot is reused by a
/// later `warn` call. Queue metadata advances before the boundary calls R, so a
/// warning promoted to an error cannot cause the same message to be re-emitted.
pub fn takeWarning() ?[:0]const u8 {
    if (warning_read < warning_count) {
        const index = warning_read;
        warning_read += 1;
        const message = warning_buffers[index][0..warning_lengths[index] :0];
        if (warning_read == warning_count and warning_dropped == 0) clearWarnings();
        return message;
    }

    if (warning_dropped > 0) {
        const dropped = warning_dropped;
        const length = writeMessage(&overflow_buffer, "additional warnings omitted: {d}", .{dropped});
        clearWarnings();
        return overflow_buffer[0..length :0];
    }

    clearWarnings();
    return null;
}

fn writeMessage(
    storage: *[MESSAGE_CAPACITY]u8,
    comptime format: []const u8,
    args: anytype,
) usize {
    const content = storage[0 .. MESSAGE_CAPACITY - 1];
    const written = std.fmt.bufPrint(content, format, args) catch {
        const suffix_start = content.len - ELLIPSIS.len;
        @memcpy(content[suffix_start..], ELLIPSIS);
        storage[content.len] = 0;
        return content.len;
    };
    storage[written.len] = 0;
    return written.len;
}

fn clearWarnings() void {
    warning_count = 0;
    warning_read = 0;
    warning_dropped = 0;
}

test "a four KiB error truncates with an ellipsis without allocation" {
    reset();
    const long = "x" ** 4096;
    try std.testing.expectEqual(error.RZigError, raise("{s}", .{long}));
    const message = take();
    try std.testing.expectEqual(@as(usize, MESSAGE_CAPACITY - 1), message.len);
    try std.testing.expectEqualStrings(ELLIPSIS, message[message.len - ELLIPSIS.len ..]);
    try std.testing.expectEqualStrings("", take());
}

test "warnings drain in insertion order" {
    reset();
    warn("first {d}", .{1});
    warn("second", .{});
    try std.testing.expectEqualStrings("first 1", takeWarning().?);
    try std.testing.expectEqualStrings("second", takeWarning().?);
    try std.testing.expectEqual(@as(?[:0]const u8, null), takeWarning());
}

test "warning overflow is summarized without allocation" {
    reset();
    var index: usize = 0;
    while (index < MAX_WARNINGS + 2) : (index += 1) warn("warning {d}", .{index});
    index = 0;
    while (index < MAX_WARNINGS) : (index += 1) {
        try std.testing.expect(takeWarning() != null);
    }
    try std.testing.expectEqualStrings("additional warnings omitted: 2", takeWarning().?);
    try std.testing.expect(takeWarning() == null);
}
