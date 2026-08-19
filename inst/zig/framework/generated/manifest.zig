//! Generated starter manifest. rzig::document() replaces this file.

/// Bind exported function names to the package's root Zig module.
pub fn Bind(comptime root: type) type {
    return struct {
        const bound_root = root;

        /// Metadata for public functions exposed through RZig.
        pub const exports = .{
            .{
                .name = "hello_zig",
                .func = bound_root.hello_zig,
                .doc = "Return a friendly greeting.",
            },
        };
    };
}
