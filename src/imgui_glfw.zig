const std = @import("std");
const glfw = @import("mach-glfw");

const GlfwWindowHandle = @typeInfo(std.meta.fieldInfo(glfw.Window, .handle).type).Pointer.child;

pub extern fn ImGui_ImplGlfw_InitForOpenGL(window: *GlfwWindowHandle, install_callbacks: bool) bool;
pub extern fn ImGui_ImplGlfw_Shutdown() void;
pub extern fn ImGui_ImplGlfw_NewFrame() void;
