const std = @import("std");

const cl = @import("zclay");
const UI = cl.UI;
const bg = cl.bg;
const w = cl.w;
const h = cl.h;
const p = cl.p;
const gap = cl.gap;
const flex = cl.flex;
const alignment = cl.alignment;
const sizing = cl.sizing;
const rounded = cl.rounded;
const rl = @import("raylib");

const light_grey: cl.Color = .{ 224, 215, 210, 255 };
const red: cl.Color = .{ 168, 66, 28, 255 };
const orange: cl.Color = .{ 225, 138, 50, 255 };
const orange_hover: cl.Color = .{ 200, 120, 40, 255 };
const white: cl.Color = .{ 250, 250, 255, 255 };
const sidebar_border: cl.Color = .{ 180, 170, 165, 255 };

const styles = @embedFile("resources/styles.css");

var any_sidebar_item_hovered: bool = false;
var sidebar_width = cl.w.px(300);
var start_time: i64 = 0;

pub fn init() void {
    start_time = std.time.milliTimestamp();

    std.debug.print("styles: {s}\n", .{styles});
}

fn sidebarItemComponent(index: u32) void {
    const is_hovered = cl.pointerOver(.IDI("SidebarBlob", index));
    const bg_color = if (is_hovered) orange_hover else orange;

    if (is_hovered) {
        any_sidebar_item_hovered = true;
    }

    UI()(.{
        .id = .IDI("SidebarBlob", index),
        .layout = .{ .sizing = cl.sizing(cl.w.grow, cl.h.px(50)) },
        .background_color = bg_color,
    })({});
}

pub fn createLayout(profile_picture: *const rl.Texture2D) []cl.RenderCommand {
    any_sidebar_item_hovered = false;
    cl.beginLayout();

    const elapsed = @as(f32, @floatFromInt(std.time.milliTimestamp() - start_time));
    const cycle_time: f32 = 2000.0; // Animation cycle duration in ms
    const min_width: f32 = 250.0;
    const max_width: f32 = 500.0;
    const cycle_value = @rem(elapsed, cycle_time);
    const normalized = cycle_value / cycle_time; // 0.0 to 1.0
    const width = min_width + (max_width - min_width) * normalized;
    sidebar_width = cl.w.px(@as(f32, @round(width)));
    // sidebar_width = cl.w.px(300);

    UI()(.{
        .id = .ID("OuterContainer"),
        .layout = .{
            .direction = flex.row,
            .sizing = .grow,
            .padding = p(16),
            .child_gap = gap(16),
        },
        .background_color = white,
    })({
        UI()(.{
            .id = .ID("SideBar"),
            .layout = .{
                .direction = flex.col,
                .sizing = sizing(sidebar_width, h.grow),
                .padding = p(16),
                .child_alignment = alignment(.center, .top),
                .child_gap = gap(16),
            },
            .background_color = light_grey,
            .border = .{ .color = bg.gray(300), .width = .{ .right = 3 } },
            .corner_radius = rounded.md,
        })({
            UI()(.{
                .id = .ID("ProfilePictureOuter"),
                .layout = .{
                    .sizing = .{ .w = w.grow },
                    .padding = p(16),
                    .child_alignment = alignment(.left, .center),
                    .child_gap = gap(16),
                },
                .background_color = red,
            })({
                UI()(.{
                    .id = .ID("ProfilePicture"),
                    .layout = .{ .sizing = sizing(w.px(60), h.px(60)) },
                    .aspect_ratio = .{ .aspect_ratio = 60 / 60 },
                    .image = .{ .image_data = @ptrCast(profile_picture) },
                })({});
                cl.text("Clay - UI Library", .{ .font_size = 24, .color = light_grey });
            });

            for (0..3) |i| sidebarItemComponent(@intCast(i));
        });

        UI()(.{
            .id = .ID("MainContent"),
            .layout = .{
                .sizing = .grow,
                .padding = p(16),
            },
            .background_color = light_grey,
            .clip = .{ .horizontal = true, .vertical = true },
        })({
            UI()(.{
                .id = .ID("MainContentText"),
                .layout = .{
                    .sizing = sizing(w.px(500), h.grow),
                    .padding = p(16),
                },
                .background_color = bg.blue(500),
            })({
                cl.text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.", .{ .font_size = 22, .color = bg.gray(800) });
            });
        });
    });

    return cl.endLayout();
}

pub fn shouldShowHandCursor() bool {
    return any_sidebar_item_hovered;
}
