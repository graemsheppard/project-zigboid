const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glad_include = b.path("deps/glad/include");
    const glfw_include = b.path("deps/glfw/include");
    const glfw_lib = b.path("deps/glfw/lib");

    // Setup c lib dependencies
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });

    translate_c.addIncludePath(glad_include);
    translate_c.addIncludePath(glfw_include);

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

    // libglfw3.a should be in deps/glfw/lib
    exe_mod.addLibraryPath(glfw_lib);
    exe_mod.addIncludePath(glfw_include);
    exe_mod.linkSystemLibrary("glfw3", .{});

    // link GLAD loader
    exe_mod.addIncludePath(glad_include);
    exe_mod.addCSourceFile(.{
        .file = b.path("deps/glad/src/glad.c"),
        .flags = &.{}
    });

    // Required by GLFW
    if (target.result.os.tag == .macos) {
        exe_mod.linkFramework("Cocoa", .{});
        exe_mod.linkFramework("QuartzCore", .{});
        exe_mod.linkFramework("IOKit", .{});
        exe_mod.linkFramework("CoreVideo", .{});
        exe_mod.linkFramework("OpenGL", .{});
    } else if (target.result.os.tag == .windows) {
        exe_mod.linkSystemLibrary("gdi32", .{});
        exe_mod.linkSystemLibrary("user32", .{});
        exe_mod.linkSystemLibrary("shell32", .{});
        exe_mod.linkSystemLibrary("opengl32", .{});
    } else {
        @panic("Operating system not supported.");
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

}
