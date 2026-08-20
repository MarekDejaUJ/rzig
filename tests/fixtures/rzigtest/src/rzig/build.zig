const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });
    const framework = b.createModule(.{
        .root_source_file = b.path("framework/rzig.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
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
}
