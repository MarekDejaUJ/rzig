//! RZig build.
//!
//! VERSION SENSITIVE. The Build API changed shape in 0.15 (addStaticLibrary ->
//! addLibrary, root_source_file -> root_module). Check the installed
//! std/Build.zig before editing.
//!
//! Targets:
//!   zig build            static archive for R to link
//!   zig build test       Zig unit tests, no R process needed
//!   zig build gen        regenerate src/generated/*
//!   zig build lint       enforce the one-error-exit rule

const std = @import("std");
const abi_check = @import("src/c/check.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // ReleaseSafe keeps bounds and overflow checks enabled.
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const pkg_name = b.option([]const u8, "pkg", "R package name, used for R_init_<pkg>") orelse "rzigtest";
    const r_include = b.option([]const u8, "r-include", "R include directory") orelse "";

    const opts = b.addOptions();
    opts.addOption([]const u8, "pkg_name", pkg_name);

    // --- the artefact R links -------------------------------------------------
    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
    });
    lib_module.addOptions("build_options", opts);
    if (r_include.len > 0) lib_module.addIncludePath(.{ .cwd_relative = r_include });
    const lib = b.addLibrary(.{
        .name = "zigpkg",
        .root_module = lib_module,
        .linkage = .static,
    });
    // R symbols stay undefined; R's own SHLIB link resolves them.
    b.installArtifact(lib);

    // --- unit tests -----------------------------------------------------------
    const test_module = b.createModule(.{
        // Exercise the proof-of-life entry point without starting an R process.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addOptions("build_options", opts);
    const tests = b.addTest(.{ .root_module = test_module });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run Zig unit tests").dependOn(&run_tests.step);

    // --- code generation ------------------------------------------------------
    const gen_module = b.createModule(.{
        .root_source_file = b.path("tools/gen_wrappers.zig"),
        .target = b.graph.host,
    });
    const gen = b.addExecutable(.{
        .name = "gen_wrappers",
        .root_module = gen_module,
    });
    const run_gen = b.addRunArtifact(gen);
    run_gen.addArg("src/generated/arity.zig");
    b.step("gen", "Regenerate src/generated/*").dependOn(&run_gen.step);

    // --- R ABI verification source -------------------------------------------
    const update_abi_check = b.addUpdateSourceFiles();
    const abi_check_source = abi_check.render(b);
    update_abi_check.addBytesToSource(abi_check_source, "tools/abi_check.c");
    update_abi_check.addBytesToSource(abi_check_source, "tests/fixtures/rzigtest/src/abi_check.c");
    b.step("gen-abi-check", "Regenerate the R ABI verification source").dependOn(&update_abi_check.step);

    // --- lint: the one-error-exit rule ---------------------------------------
    const lint = b.addSystemCommand(&.{ "sh", "tools/lint_error_exit.sh" });
    b.step("lint", "Fail if Rf_error escapes boundary.zig").dependOn(&lint.step);
}
