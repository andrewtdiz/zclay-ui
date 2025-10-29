const std = @import("std");
const B = std.Build;

pub fn build(b: *B) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zclay_module = b.addModule("zclay", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    zclay_module.addImport("raylib", raylib_dep.module("raylib"));
    zclay_module.linkLibrary(raylib_dep.artifact("raylib"));

    // Build Clay C library (shared between host and DLL)
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

    // clay_lib.addCSourceFile(.{
    //     .file = b.addWriteFiles().add("clay.c",
    //         \\#define CLAY_IMPLEMENTATION
    //         \\#include<clay.h>
    //     ),
    //     .flags = &.{"-ffreestanding"},
    // });
    clay_lib.addCSourceFile(.{
        .file = b.path("library/clay.c"),
        .flags = &.{"-ffreestanding"},
    });

    zclay_module.linkLibrary(clay_lib);

    // Build host executable
    const host_module = b.createModule(.{
        .root_source_file = b.path("src/host.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_module.addImport("zclay", zclay_module);
    host_module.addImport("raylib", raylib_dep.module("raylib"));
    host_module.linkLibrary(raylib_dep.artifact("raylib"));

    const host_exe = b.addExecutable(.{ .name = "host", .root_module = host_module });
    b.installArtifact(host_exe);

    // Build game DLL
    const game_module = b.createModule(.{
        .root_source_file = b.path("src/game.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_module.addImport("zclay", zclay_module);
    game_module.addImport("raylib", raylib_dep.module("raylib"));
    game_module.linkLibrary(raylib_dep.artifact("raylib"));

    const game_dll = b.addLibrary(.{
        .name = "game",
        .linkage = .dynamic,
        .root_module = game_module,
    });
    game_dll.linkLibrary(clay_lib);

    const game_dll_install = b.addInstallArtifact(game_dll, .{});
    b.getInstallStep().dependOn(&game_dll_install.step);

    // Run step for host
    const run_cmd = b.addRunArtifact(host_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the host app");
    run_step.dependOn(&run_cmd.step);

    // Build step for game DLL only
    const game_dll_step = b.step("game_dll", "Build the game DLL");
    game_dll_step.dependOn(&game_dll_install.step);
}
