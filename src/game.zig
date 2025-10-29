const std = @import("std");

const cl = @import("zclay");
const rl = @import("raylib");

const layout = @import("layout.zig");
const renderer = @import("raylib_render_clay.zig");

// Import the context structure from host
pub const GameContext = extern struct {
    screen_width: i32,
    screen_height: i32,
    mouse_x: f32,
    mouse_y: f32,
    mouse_down: bool,
    scroll_delta_x: f32,
    scroll_delta_y: f32,
    delta_time: f32,
    profile_picture: *const rl.Texture2D,
    debug_mode_enabled: bool,
    fonts: *[10]?rl.Font,
};

// Global Clay arena - we'll initialize this on first call
var clay_arena_memory: ?[]u8 = null;
var clay_arena: ?cl.Arena = null;
var clay_initialized: bool = false;
var current_fonts: *[10]?rl.Font = undefined;

pub export fn init_layout() callconv(.c) void {
    layout.init();
    clay_initialized = false;
}

// Wrapper for measureText that uses fonts from context
fn measureTextWrapper(clay_text: []const u8, config: *cl.TextElementConfig, _: void) cl.Dimensions {
    // Copy fonts from context to renderer's global for measureText to use
    renderer.raylib_fonts = current_fonts.*;
    return renderer.measureText(clay_text, config, {});
}

fn ensureClayInitialized(ctx: *const GameContext) !void {
    if (!clay_initialized) {
        // Store fonts pointer for use in measureText
        current_fonts = ctx.fonts;

        // Copy fonts to renderer's global array for compatibility
        renderer.raylib_fonts = ctx.fonts.*;

        // Initialize Clay
        const min_memory_size: u32 = cl.minMemorySize();
        clay_arena_memory = try std.heap.page_allocator.alloc(u8, min_memory_size);
        clay_arena = cl.createArenaWithCapacityAndMemory(clay_arena_memory.?);
        _ = cl.initialize(clay_arena.?, .{ .h = @floatFromInt(ctx.screen_height), .w = @floatFromInt(ctx.screen_width) }, .{});
        cl.setMeasureTextFunction(void, {}, measureTextWrapper);
        clay_initialized = true;
    } else {
        // Update fonts pointer if context changed
        current_fonts = ctx.fonts;
        renderer.raylib_fonts = ctx.fonts.*;
    }
}

// Exported function called by host
pub export fn update_and_render(ctx: *const GameContext, out_render_commands: *[*]cl.RenderCommand, out_length: *usize) callconv(.c) void {
    // Sync fonts from context to renderer's global array
    renderer.raylib_fonts = ctx.fonts.*;

    // Ensure Clay is initialized
    ensureClayInitialized(ctx) catch {
        out_length.* = 0;
        return;
    };

    // Update Clay input state
    cl.setPointerState(.{
        .x = ctx.mouse_x,
        .y = ctx.mouse_y,
    }, ctx.mouse_down);

    cl.updateScrollContainers(
        false,
        .{ .x = ctx.scroll_delta_x, .y = ctx.scroll_delta_y },
        ctx.delta_time,
    );

    cl.setLayoutDimensions(.{
        .w = @floatFromInt(ctx.screen_width),
        .h = @floatFromInt(ctx.screen_height),
    });

    cl.setDebugModeEnabled(ctx.debug_mode_enabled);

    // Generate layout
    const render_commands = layout.createLayout(ctx.profile_picture);

    // Return render commands
    if (render_commands.len > 0) {
        out_render_commands.* = @ptrCast(@alignCast(render_commands.ptr));
        out_length.* = render_commands.len;
    } else {
        out_length.* = 0;
    }
}

// Helper function to check cursor state (can be called from host if needed)
pub export fn should_show_hand_cursor() callconv(.c) bool {
    return layout.shouldShowHandCursor();
}
