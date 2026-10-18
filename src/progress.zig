//! A text progress bar on R's message stream for loops on the R thread.

const std = @import("std");
const es = @import("error_state.zig");
const interrupt = @import("interrupt.zig");
const io = @import("io.zig");

const bar_width = 40;

/// A progress bar for `total` steps, drawn with REprintf when `show` is true.
///
/// The bar is redrawn when its percentage changes, at most 101 times, and each
/// redraw also checks for a user interrupt (with or without `show`). Create it
/// with `ctx.progress()`; like the call context it belongs to the R thread and
/// cannot be passed to `rzig.parallelFor` workers.
pub const Progress = struct {
    total: usize,
    done: usize = 0,
    percent: usize = 0,
    show: bool,
    drawn: bool = false,
    finished: bool = false,

    /// Marks the type for the worker-state check of `rzig.parallelFor`.
    pub const rzig_r_thread_only = {};

    pub fn init(total: usize, show: bool) Progress {
        return .{ .total = total, .show = show };
    }

    /// Advance by `steps` (at most to `total`).
    pub fn add(self: *Progress, steps: usize) es.Error!void {
        self.done = @min(self.total, self.done +| steps);
        const percent = percentOf(self.done, self.total);
        if (self.drawn and percent == self.percent) return;
        self.percent = percent;
        self.drawn = true;
        if (self.show) try draw(percent);
        try interrupt.checkInterrupt();
    }

    /// Draw the complete bar and end its line. Later calls do nothing.
    pub fn finish(self: *Progress) es.Error!void {
        if (self.finished) return;
        self.finished = true;
        self.done = self.total;
        self.percent = 100;
        if (self.show) {
            try draw(100);
            try io.write(.err, "\n");
        }
    }
};

fn percentOf(done: usize, total: usize) usize {
    if (total == 0) return 100;
    return @intCast(@as(u128, done) * 100 / total);
}

fn draw(percent: usize) es.Error!void {
    var bar: [bar_width]u8 = undefined;
    const filled = percent * bar_width / 100;
    @memset(bar[0..filled], '=');
    @memset(bar[filled..], ' ');
    try io.print(.err, "\r[{s}] {d:>3}%", .{ bar[0..], percent });
}

test "percentages round down and reach 100 only at the end" {
    try std.testing.expectEqual(@as(usize, 0), percentOf(0, 3));
    try std.testing.expectEqual(@as(usize, 33), percentOf(1, 3));
    try std.testing.expectEqual(@as(usize, 100), percentOf(3, 3));
    try std.testing.expectEqual(@as(usize, 100), percentOf(0, 0));
    try std.testing.expectEqual(@as(usize, 50), percentOf(std.math.maxInt(usize) / 2 + 1, std.math.maxInt(usize)));
}
