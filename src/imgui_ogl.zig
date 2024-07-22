const zimgui = @import("Zig-ImGui");

const LoaderInitErrors = enum(i32) {
    ok = 0,
    init_error = -1,
    open_library = -2,
    opengl_version_unsupported = -3,
};

extern fn imgl3wInit2(get_proc_address_pfn: *const fn ([*:0]const u8) callconv(.C) ?*anyopaque) LoaderInitErrors;
pub const populate_dear_imgui_opengl_symbol_table = imgl3wInit2;

pub extern fn ImGui_ImplOpenGL3_Init(glsl_version: ?[*:0]const u8) bool;
pub extern fn ImGui_ImplOpenGL3_Shutdown() void;
pub extern fn ImGui_ImplOpenGL3_NewFrame() void;
pub extern fn ImGui_ImplOpenGL3_RenderDrawData(draw_data: *const zimgui.DrawData) void;
