const std = @import("std");

/// A C library that Zig compiles into the package from sources shipped in
/// src/rzig, listed in c_libraries.zon. Paths are relative to src/rzig.
const CLibrary = struct {
    /// The Zig module of the translated header: `@import("name")`.
    name: []const u8,
    /// The header that translate-c turns into the module, if any.
    header: ?[]const u8 = null,
    /// The C source files.
    sources: []const []const u8 = &.{},
    /// Include directories of the sources and of the header.
    include: []const []const u8 = &.{},
    /// Compiler flags for the sources.
    flags: []const []const u8 = &.{},
};

const c_libraries: []const CLibrary = @import("c_libraries.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });
    _ = b.option([]const u8, "pkg", "R package name");
    const r_include = b.option([]const u8, "r-include", "R include directory") orelse "";

    const framework = b.createModule(.{
        .root_source_file = b.path("framework/rzig.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (r_include.len > 0) framework.addIncludePath(.{ .cwd_relative = r_include });

    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
        .link_libc = true,
    });
    module.addImport("rzig", framework);
    addCLibraries(b, module);

    const library = b.addLibrary(.{
        .name = "zigpkg",
        .root_module = module,
        .linkage = .static,
    });
    // Linux needs Zig's stack probe; other final C links supply the runtime.
    library.bundle_compiler_rt = target.result.os.tag == .linux;
    b.installArtifact(library);

    // `zig build test` (rzig::test_zig()) runs the test blocks reached from
    // src/tests.zig on the host, without R. Import there only files that do
    // not use the rzig module, whose R symbols exist only inside R.
    const kernel_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = c_libraries.len > 0,
    });
    addCLibraries(b, kernel_module);
    const kernel_tests = b.addTest(.{ .root_module = kernel_module });
    const run_tests = b.addRunArtifact(kernel_tests);
    b.step("test", "Run the Zig tests of src/tests.zig without R").dependOn(&run_tests.step);
}

/// Compile the sources of c_libraries.zon into `module` and make each
/// translated header importable from it.
fn addCLibraries(b: *std.Build, module: *std.Build.Module) void {
    for (c_libraries) |c_library| {
        for (c_library.include) |directory| module.addIncludePath(b.path(directory));
        if (c_library.sources.len > 0) {
            module.addCSourceFiles(.{ .files = c_library.sources, .flags = c_library.flags });
        }
        if (c_library.header) |header| {
            const translated = b.addTranslateC(.{
                .root_source_file = b.path(header),
                .target = module.resolved_target.?,
                .optimize = module.optimize.?,
                .link_libc = true,
            });
            for (c_library.include) |directory| translated.addIncludePath(b.path(directory));
            module.addImport(c_library.name, translated.createModule());
        }
    }
}
