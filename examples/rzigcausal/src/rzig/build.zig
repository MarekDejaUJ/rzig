const std = @import("std");

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
    const kernel_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const run_tests = b.addRunArtifact(kernel_tests);
    b.step("test", "Run the Zig tests of src/tests.zig without R").dependOn(&run_tests.step);
}
