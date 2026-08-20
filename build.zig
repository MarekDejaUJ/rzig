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
        .link_libc = true,
    });
    lib_module.addOptions("build_options", opts);
    if (r_include.len > 0) lib_module.addIncludePath(.{ .cwd_relative = r_include });
    const lib = b.addLibrary(.{
        .name = "zigpkg",
        .root_module = lib_module,
        .linkage = .static,
    });
    lib.bundle_compiler_rt = true;
    // R symbols stay undefined; R's own SHLIB link resolves them.
    b.installArtifact(lib);

    // --- unit tests -----------------------------------------------------------
    const test_module = b.createModule(.{
        // Exercise the proof-of-life entry point without starting an R process.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_module.addOptions("build_options", opts);
    const tests = b.addTest(.{ .root_module = test_module });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run Zig unit tests");
    test_step.dependOn(&run_tests.step);

    const convert_test_module = b.createModule(.{
        .root_source_file = b.path("src/convert_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const convert_tests = b.addTest(.{ .root_module = convert_test_module });
    const run_convert_tests = b.addRunArtifact(convert_tests);
    test_step.dependOn(&run_convert_tests.step);

    const interrupt_test_module = b.createModule(.{
        .root_source_file = b.path("src/interrupt_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const interrupt_tests = b.addTest(.{ .root_module = interrupt_test_module });
    const run_interrupt_tests = b.addRunArtifact(interrupt_tests);
    test_step.dependOn(&run_interrupt_tests.step);

    const generator_test_module = b.createModule(.{
        .root_source_file = b.path("tools/gen_wrappers.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generator_tests = b.addTest(.{ .root_module = generator_test_module });
    const run_generator_tests = b.addRunArtifact(generator_tests);
    test_step.dependOn(&run_generator_tests.step);

    const scanner_test_module = b.createModule(.{
        .root_source_file = b.path("tools/scan.zig"),
        .target = target,
        .optimize = optimize,
    });
    const scanner_tests = b.addTest(.{ .root_module = scanner_test_module });
    const run_scanner_tests = b.addRunArtifact(scanner_tests);
    test_step.dependOn(&run_scanner_tests.step);

    const compile_fail = b.addSystemCommand(&.{ "sh", "tools/compile_fail.sh" });
    compile_fail.setEnvironmentVariable("ZIG", b.graph.zig_exe);
    test_step.dependOn(&compile_fail.step);

    const fixture_sync = b.addSystemCommand(&.{ "sh", "tools/sync_fixture.sh", "--check" });
    test_step.dependOn(&fixture_sync.step);

    const r_package_assets = b.addSystemCommand(&.{ "sh", "tools/sync_r_package_assets.sh", "--check" });
    test_step.dependOn(&r_package_assets.step);

    const makevars_templates = b.addSystemCommand(&.{ "sh", "tools/check_makevars_templates.sh" });
    test_step.dependOn(&makevars_templates.step);

    const configure_templates = b.addSystemCommand(&.{ "sh", "tools/check_configure_templates.sh" });
    test_step.dependOn(&configure_templates.step);

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
    const fmt_gen = b.addSystemCommand(&.{ b.graph.zig_exe, "fmt", "src/generated/arity.zig" });
    fmt_gen.step.dependOn(&run_gen.step);

    const scan_module = b.createModule(.{
        .root_source_file = b.path("tools/scan.zig"),
        .target = b.graph.host,
    });
    const scan = b.addExecutable(.{
        .name = "scan_exports",
        .root_module = scan_module,
    });
    const run_scan = b.addRunArtifact(scan);
    run_scan.addArgs(&.{ "src/main.zig", "src/generated/manifest.zig" });
    const fmt_manifest = b.addSystemCommand(&.{ b.graph.zig_exe, "fmt", "src/generated/manifest.zig" });
    fmt_manifest.step.dependOn(&run_scan.step);

    const run_fixture_scan = b.addRunArtifact(scan);
    run_fixture_scan.addArgs(&.{
        "tests/fixtures/rzigtest/src/rzig/src/main.zig",
        "tests/fixtures/rzigtest/src/rzig/framework/generated/manifest.zig",
    });
    const fmt_fixture_manifest = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "fmt",
        "tests/fixtures/rzigtest/src/rzig/framework/generated/manifest.zig",
    });
    fmt_fixture_manifest.step.dependOn(&run_fixture_scan.step);

    const gen_step = b.step("gen", "Regenerate src/generated/*");
    gen_step.dependOn(&fmt_gen.step);
    gen_step.dependOn(&fmt_manifest.step);
    gen_step.dependOn(&fmt_fixture_manifest.step);

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
