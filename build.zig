const std = @import("std");
const B = std.Build;

pub fn build(b: *B) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zigwin32_dep = b.dependency("zigwin32", .{});
    const win32 = zigwin32_dep.module("win32");
    const wgpu_dep = b.dependency("wgpu_native_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const window_mod = b.createModule(.{
        .root_source_file = b.path("src/window.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = win32 },
        },
    });

    const root_module = b.addModule("zclay", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "window", .module = window_mod },
        },
    });

    {
        const clay_lib = b.addLibrary(.{
            .name = "clay",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
            }),
        });

        const clay_dep = b.dependency("clay", .{});
        clay_lib.addIncludePath(clay_dep.path(""));

        clay_lib.addCSourceFile(.{
            .file = b.addWriteFiles().add("clay.c",
                \\#define CLAY_IMPLEMENTATION
                \\#include<clay.h>
            ),
            .flags = &.{"-ffreestanding"},
        });

        root_module.linkLibrary(clay_lib);
    }
    
    root_module.addImport("win32", win32);
    root_module.addImport("wgpu", wgpu_dep.module("wgpu"));

    const exe_unit_tests = b.addTest(.{ .root_module = root_module });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    const tests_check = b.addTest(.{ .root_module = root_module });
    const check = b.step("check", "Check if tests compile");
    check.dependOn(&tests_check.step);
}
