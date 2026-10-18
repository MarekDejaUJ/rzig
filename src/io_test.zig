//! Console output and progress tests with an in-process stand-in for R.

const std = @import("std");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const io = @import("io.zig");
const Progress = @import("progress.zig").Progress;

var allow_callback = true;
var interrupt_probes: usize = 0;
var out_text: [16384]u8 = undefined;
var out_length: usize = 0;
var err_text: [16384]u8 = undefined;
var err_length: usize = 0;
var writes: usize = 0;

export fn R_ToplevelExec(
    callback: *const fn (?*anyopaque) callconv(.c) void,
    data: ?*anyopaque,
) c.Rboolean {
    if (!allow_callback) return c.FALSE;
    callback(data);
    return c.TRUE;
}

export fn R_CheckUserInterrupt() void {
    interrupt_probes += 1;
}

fn record(stream: io.Stream, text: [*:0]const u8) void {
    const bytes = std.mem.span(text);
    writes += 1;
    switch (stream) {
        .out => {
            @memcpy(out_text[out_length..][0..bytes.len], bytes);
            out_length += bytes.len;
        },
        .err => {
            @memcpy(err_text[err_length..][0..bytes.len], bytes);
            err_length += bytes.len;
        },
    }
}

fn reset() void {
    es.reset();
    allow_callback = true;
    interrupt_probes = 0;
    out_length = 0;
    err_length = 0;
    writes = 0;
    io.sink = &record;
}

test "print formats text onto R's output and message streams" {
    reset();
    try io.print(.out, "{d} of {s}\n", .{ 3, "five" });
    try io.print(.err, "%s and %d stay literal\n", .{});
    try std.testing.expectEqualStrings("3 of five\n", out_text[0..out_length]);
    try std.testing.expectEqualStrings("%s and %d stay literal\n", err_text[0..err_length]);
}

test "text longer than the stack buffer is written in full" {
    reset();
    const long: [10000]u8 = @splat('x');
    try io.print(.out, "{s}", .{&long});
    try std.testing.expectEqual(@as(usize, 10000), out_length);
    try std.testing.expectEqual(@as(usize, 1), writes);
}

test "a transfer of control while printing becomes a pending interrupt" {
    reset();
    allow_callback = false;
    try std.testing.expectError(es.Error.RZigError, io.print(.out, "lost\n", .{}));
    try std.testing.expect(es.takeInterrupt());
    try std.testing.expectEqual(@as(usize, 0), out_length);
}

test "progress redraws only when the percentage changes and checks interrupts" {
    reset();
    var progress = Progress.init(1000, true);
    var step: usize = 0;
    while (step < 1000) : (step += 1) try progress.add(1);
    try progress.finish();
    try progress.finish();
    // 101 redraws (0% to 100%) from add(), then the final bar and its newline.
    try std.testing.expectEqual(@as(usize, 103), writes);
    try std.testing.expectEqual(@as(usize, 101), interrupt_probes);
    const text = err_text[0..err_length];
    try std.testing.expect(std.mem.endsWith(u8, text, "] 100%\n"));
    try std.testing.expect(std.mem.indexOf(u8, text, "\r[====================                    ]  50%") != null);
}

test "a hidden progress bar writes nothing but still checks interrupts" {
    reset();
    var progress = Progress.init(10, false);
    var step: usize = 0;
    while (step < 10) : (step += 1) try progress.add(1);
    try progress.finish();
    try std.testing.expectEqual(@as(usize, 0), writes);
    try std.testing.expectEqual(@as(usize, 10), interrupt_probes);
}

test "an interrupt during progress stops the loop" {
    reset();
    var progress = Progress.init(10, false);
    allow_callback = false;
    try std.testing.expectError(es.Error.RZigError, progress.add(1));
    try std.testing.expect(es.takeInterrupt());
}
