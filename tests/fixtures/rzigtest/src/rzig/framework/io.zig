//! Console output on the R thread. Text goes through Rprintf and REprintf,
//! never the process's stdout or stderr, so it reaches Rgui, RStudio and
//! sink() (CRAN policy). R's printing can transfer control: Rprintf checks
//! for a user interrupt every 100 calls. Every write therefore runs inside
//! R_ToplevelExec, and a caught transfer becomes an interrupt that the
//! boundary delivers after Zig cleanup.

const std = @import("std");
const builtin = @import("builtin");
const compat = @import("compat.zig");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");

/// R's standard output (`Rprintf`) or its message stream (`REprintf`).
pub const Stream = enum { out, err };

/// The function that hands NUL-terminated text to R. Tests replace it.
pub var sink: *const fn (Stream, [*:0]const u8) void = &rConsole;

fn rConsole(stream: Stream, text: [*:0]const u8) void {
    // Test binaries have no R; they replace `sink`.
    if (builtin.is_test) return;
    // "%s" keeps user text from being read as a format string.
    switch (stream) {
        .out => c.Rprintf("%s", text),
        .err => c.REprintf("%s", text),
    }
}

const Pending = struct {
    stream: Stream,
    text: [*:0]const u8,
};

fn emit(data: ?*anyopaque) callconv(.c) void {
    const pending: *const Pending = @ptrCast(@alignCast(data.?));
    sink(pending.stream, pending.text);
}

/// Write text to the R console. Text after an embedded NUL byte is not shown.
pub fn write(stream: Stream, text: [:0]const u8) es.Error!void {
    var pending = Pending{ .stream = stream, .text = text.ptr };
    if (c.R_ToplevelExec(emit, @ptrCast(&pending)) == c.FALSE) return es.interrupt();
}

/// Format with `std.fmt` and write the result to the R console. Text of more
/// than 4095 bytes is formatted into memory from the C allocator, which is
/// released before the function returns.
pub fn print(stream: Stream, comptime format: []const u8, args: anytype) es.Error!void {
    var buffer: [4096]u8 = undefined;
    const length = std.fmt.count(format, args);
    if (length < buffer.len) {
        const text = compat.bufPrintZ(&buffer, format, args) catch unreachable;
        return write(stream, text);
    }
    const memory = std.heap.c_allocator.allocSentinel(u8, length, 0) catch
        return es.raise("out of memory formatting {d} bytes of console output", .{length});
    defer std.heap.c_allocator.free(memory);
    _ = std.fmt.bufPrint(memory, format, args) catch unreachable;
    return write(stream, memory);
}
