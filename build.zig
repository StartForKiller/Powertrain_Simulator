const std = @import("std");

const zgl = @import("zgl");
const ZigImGui_build_script = @import("ZigImGui");

fn create_imgui_glfw_static_lib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    glfw_dep: *std.Build.Dependency,
    imgui_dep: *std.Build.Dependency,
    ZigImGui_dep: *std.Build.Dependency,
) *std.Build.Step.Compile {
    // compile the desired backend into a separate static library
    const imgui_glfw = b.addStaticLibrary(.{
        .name = "imgui_glfw",
        .target = target,
        .optimize = optimize,
    });
    imgui_glfw.linkLibCpp();
    // link in the necessary symbols from ImGui base
    imgui_glfw.linkLibrary(ZigImGui_dep.artifact("cimgui"));

    // use the same override DEFINES that the ImGui base does
    for (ZigImGui_build_script.IMGUI_C_DEFINES) |c_define| {
        imgui_glfw.root_module.addCMacro(c_define[0], c_define[1]);
    }

    // ensure only a basic version of glfw is given to `imgui_impl_glfw.cpp` to
    // ensure it can be loaded with no extra headers.
    imgui_glfw.root_module.addCMacro("GLFW_INCLUDE_NONE", "1");

    // ensure the backend has access to the ImGui headers it expects
    imgui_glfw.addIncludePath(imgui_dep.path("."));
    imgui_glfw.addIncludePath(imgui_dep.path("backends/"));

    // Linking a compiled artifact auto-includes its headers now, fetch it here
    // so Dear ImGui's GLFW implementation can use it.
    const glfw_lib = glfw_dep.artifact("glfw");
    imgui_glfw.linkLibrary(glfw_lib);

    imgui_glfw.addCSourceFile(.{
        .file = imgui_dep.path("backends/imgui_impl_glfw.cpp"),
        // use the same compile flags that the ImGui base does
        .flags = ZigImGui_build_script.IMGUI_C_FLAGS,
    });

    return imgui_glfw;
}

/// touches up `imgui_impl_opengl3.cpp` to remove its needless incompatiblity
/// with simultaneous dynamic loading of opengl and OpenGL ES 2.0 support
fn generate_modified_imgui_source(b: *std.Build, path: []const u8) ![]const u8 {
    var list = blk: {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        var list = std.ArrayList(u8).init(b.allocator);
        try file.reader().readAllArrayList(&list, std.math.maxInt(usize));
        break :blk list;
    };
    defer list.deinit();

    // This should only replace the first occurrance of this #if near the top
    // of the file where it decides if it should include the GLES headers
    // instead of dynamically linking. We want dynamic linking for portability,
    // but also want Dear ImGui to limit its OpenGL API usage as is appropriate
    // for whatever version we've targeted, hence this substitution.
    const search_text_1 = "#if defined(IMGUI_IMPL_OPENGL_ES2)";
    const start_pos_1 = std.mem.indexOf(u8, list.items, search_text_1) orelse return error.InvalidSourceFile;
    try list.replaceRange(start_pos_1, search_text_1.len, "#if false");

    // This also should only replace the first occurrance of this #if near the
    // top  of the file where it decides if it should include the GLES headers
    // instead of dynamically linking. We want dynamic linking for portability,
    // but also want Dear ImGui to limit its OpenGL API usage as is appropriate
    // for whatever version we've targeted, hence this substitution.
    const search_text_2 = "#elif defined(IMGUI_IMPL_OPENGL_ES3)";
    const start_pos_2 = std.mem.indexOf(u8, list.items, search_text_2) orelse return error.InvalidSourceFile;
    try list.replaceRange(start_pos_2, search_text_2.len, "#elif false");

    // Normally, this setting disables Dear ImGui's builtin dynamic OpenGL
    // loader completely. For this project, it is preferrable for Dear ImGui to
    // keep using its included loader, but to skip the loader's dlopen of
    // OpenGL. This allows us to delegate the locating and opening of the
    // OpenGL dynamic library to glfw, and then give the `glXGetProcAddress`/
    // `glXGetProcAddressARB` function pointer that glfw located directly to
    // Dear ImGui's loader.
    const search_text_3 = "#elif !defined(IMGUI_IMPL_OPENGL_LOADER_CUSTOM)";
    const start_pos_3 = std.mem.indexOf(u8, list.items, search_text_3) orelse return error.InvalidSourceFile;
    try list.replaceRange(start_pos_3, search_text_3.len, "#else");

    return list.toOwnedSlice();
}

fn create_imgui_opengl_static_lib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imgui_dep: *std.Build.Dependency,
    ZigImGui_dep: *std.Build.Dependency,
    selected_opengl_version: zgl.OpenGlVersion,
) !*std.Build.Step.Compile {
    // compile the desired backend into a separate static library
    const imgui_opengl = b.addStaticLibrary(.{
        .name = "imgui_opengl",
        .target = target,
        .optimize = optimize,
    });
    imgui_opengl.linkLibCpp();
    // link in the necessary symbols from ImGui base
    imgui_opengl.linkLibrary(ZigImGui_dep.artifact("cimgui"));

    // use the same override DEFINES that the ImGui base does
    for (ZigImGui_build_script.IMGUI_C_DEFINES) |c_define| {
        imgui_opengl.root_module.addCMacro(c_define[0], c_define[1]);
    }

    // ensure the backend has access to the ImGui headers it expects
    imgui_opengl.addIncludePath(imgui_dep.path("."));
    imgui_opengl.addIncludePath(imgui_dep.path("backends/"));

    imgui_opengl.defineCMacro("IMGUI_IMPL_OPENGL_LOADER_CUSTOM", "1");
    if (selected_opengl_version.es) {
        imgui_opengl.defineCMacro(b.fmt("IMGUI_IMPL_OPENGL_ES{d}", .{selected_opengl_version.major}), "1");
    }

    imgui_opengl.addCSourceFile(.{
        .file = b.addWriteFiles().add(
            "imgui_impl_opengl3.cpp",
            try generate_modified_imgui_source(
                b,
                imgui_dep.path("backends/imgui_impl_opengl3.cpp").getPath(imgui_dep.builder),
            ),
        ),
        // use the same compile flags that the ImGui base does
        .flags = ZigImGui_build_script.IMGUI_C_FLAGS,
    });

    return imgui_opengl;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const selected_opengl_version = zgl.OpenGlVersionLookupTable.get("VERSION_3_2") orelse unreachable;

    const mach_glfw_dep = b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    });
    const glfw_dep = mach_glfw_dep.builder.dependency("glfw", .{ .target = target, .optimize = optimize });
    const zgl_dep = b.dependency("zgl", .{
        .target = target,
        .optimize = optimize,
        .binding_version = @as([]const u8, b.fmt("{s}VERSION_{d}_{d}", .{
            if (selected_opengl_version.es)
                "ES_"
            else
                "",
            selected_opengl_version.major,
            selected_opengl_version.minor,
        })),
    });
    const ZigImGui_dep = b.dependency("ZigImGui", .{
        .target = target,
        .optimize = optimize,
        .enable_freetype = true,
        .enable_lunasvg = true,
    });
    const imgui_dep = ZigImGui_dep.builder.dependency("imgui", .{
        .target = target,
        .optimize = optimize,
    });
    const imgui_glfw = create_imgui_glfw_static_lib(b, target, optimize, glfw_dep, imgui_dep, ZigImGui_dep);
    const imgui_opengl = create_imgui_opengl_static_lib(b, target, optimize, imgui_dep, ZigImGui_dep, selected_opengl_version);

    const lib = b.addStaticLibrary(.{
        .name = "Powertrain_Simulator",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const imports: []const std.Build.Module.Import = &.{
        .{ .name = "mach-glfw", .module = mach_glfw_dep.module("mach-glfw") },
        .{ .name = "zgl", .module = zgl_dep.module("zgl") },
        .{ .name = "Zig-ImGui", .module = ZigImGui_dep.module("Zig-ImGui") },
    };

    const exe = b.addExecutable(.{
        .name = "Powertrain_Simulator",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    for (imports) |import| {
        exe.root_module.addImport(import.name, import.module);
    }

    {
        const opts = b.addOptions();
        opts.addOption(u32, "OPENGL_MAJOR_VERSION", selected_opengl_version.major);
        opts.addOption(u32, "OPENGL_MINOR_VERSION", selected_opengl_version.minor);
        opts.addOption(bool, "OPENGL_ES_PROFILE", selected_opengl_version.es);
        exe.root_module.addImport("build_options", opts.createModule());
    }

    exe.linkLibrary(imgui_glfw);
    exe.linkLibrary(try imgui_opengl);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
