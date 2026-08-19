const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
        .link_libc = true,
    });
    const library = b.addLibrary(.{
        .name = "zigpkg",
        .root_module = module,
        .linkage = .static,
    });
    library.bundle_compiler_rt = true;
    b.installArtifact(library);
}
