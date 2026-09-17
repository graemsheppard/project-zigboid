const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Setup c lib dependencies
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });

    translate_c.addIncludePath(b.path("deps/glad/include/"));
    translate_c.addIncludePath(.{ .cwd_relative = "/usr/local/include" });

    const c_mod = translate_c.createModule();

    const exe = b.addExecutable(.{
        .name = "project_zigboid",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c", .module = c_mod }
            }
        }),
    });

    const exe_mod = exe.root_module;

    // libglfw3.a should be in /usr/local/lib
    exe_mod.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe_mod.linkSystemLibrary("glfw3", .{});

    // link GLAD loader
    exe_mod.addIncludePath(b.path("deps/glad/include"));
    exe_mod.addCSourceFile(.{
        .file = b.path("deps/glad/src/glad.c"),
        .flags = &.{}
    });

    // Required by GLFW
    exe_mod.linkFramework("Cocoa", .{});
    exe_mod.linkFramework("IOKit", .{});
    exe_mod.linkFramework("CoreVideo", .{});
    exe_mod.linkFramework("OpenGL", .{});

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

}
