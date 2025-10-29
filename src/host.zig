const std = @import("std");
const windows = std.os.windows;
const kernel32 = windows.kernel32;
const c_allocator = std.heap.c_allocator;
const crypto = std.crypto;
const Blake3 = crypto.hash.Blake3;

const cl = @import("zclay");
const rl = @import("raylib");

const renderer = @import("raylib_render_clay.zig");

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

const UpdateAndRenderFn = *const fn (ctx: *const GameContext, out_render_commands: *[*]cl.RenderCommand, out_length: *usize) callconv(.c) void;
const ShouldShowHandCursorFn = *const fn () callconv(.c) bool;
const InitLayoutFn = *const fn () callconv(.c) void;

const GameLib = struct {
    handle: ?windows.HMODULE,
    update_and_render: UpdateAndRenderFn,
    should_show_hand_cursor: ?ShouldShowHandCursorFn,
    init_layout: InitLayoutFn,
    last_write_time: i128,
    last_file_size: u64,
    last_hash: [Blake3.digest_length]u8,
    source_path_buf: [std.fs.max_path_bytes]u8,
    source_path_len: usize,
    loaded_path_buf: [std.fs.max_path_bytes]u8,
    loaded_path_len: usize,
    generation: usize,
    copy_error_reported: bool,

    fn init(path: []const u8) !GameLib {
        var lib = GameLib{
            .handle = null,
            .update_and_render = undefined,
            .should_show_hand_cursor = null,
            .init_layout = undefined,
            .last_write_time = 0,
            .last_file_size = 0,
            .last_hash = undefined,
            .source_path_buf = undefined,
            .source_path_len = 0,
            .loaded_path_buf = undefined,
            .loaded_path_len = 0,
            .generation = 0,
            .copy_error_reported = false,
        };

        var abs_buf: [std.fs.max_path_bytes]u8 = undefined;
        const abs_path = try std.fs.cwd().realpath(path, &abs_buf);
        lib.source_path_len = abs_path.len;
        std.mem.copyForwards(u8, lib.source_path_buf[0..abs_path.len], abs_path);

        const stat = try lib.statSource();

        var hash_attempt: u8 = 0;
        hash_retry: while (true) {
            lib.last_hash = lib.computeHash() catch |err| switch (err) {
                error.FileNotFound,
                error.AccessDenied,
                error.SharingViolation,
                error.AntivirusInterference,
                error.PipeBusy,
                error.FileBusy,
                => {
                    if (hash_attempt >= 10) {
                        std.debug.print("Failed to hash DLL from {s} ({s})\n", .{ lib.sourcePath(), @errorName(err) });
                        return err;
                    }
                    hash_attempt += 1;
                    std.Thread.sleep(10 * std.time.ns_per_ms);
                    continue :hash_retry;
                },
                else => return err,
            };
            break;
        }

        var new_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const new_path = try lib.formatLoadedPath(lib.generation, &new_path_buf);

        var attempt: u8 = 0;
        const start = std.time.milliTimestamp();
        while (!(try lib.copyFileOnce(new_path))) : (attempt += 1) {
            if (attempt >= 10) {
                std.debug.print("Failed to stage DLL from {s}\n", .{lib.sourcePath()});
                return error.CopyFileFailed;
            }
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
        const end = std.time.milliTimestamp();
        std.debug.print("Time taken to stage DLL: {d}ms\n", .{end - start});
        errdefer std.fs.deleteFileAbsolute(new_path) catch {};

        const handle = try GameLib.loadModule(new_path);
        errdefer _ = kernel32.FreeLibrary(handle);

        const update_fn = try GameLib.loadUpdateFn(handle);
        const cursor_fn = GameLib.loadCursorFn(handle);
        const init_layout_fn = try GameLib.loadInitLayoutFn(handle);

        lib.handle = handle;
        lib.update_and_render = update_fn;
        lib.should_show_hand_cursor = cursor_fn;
        lib.init_layout = init_layout_fn;
        lib.last_write_time = stat.mtime;
        lib.last_file_size = stat.size;
        lib.loaded_path_len = new_path.len;
        std.mem.copyForwards(u8, lib.loaded_path_buf[0..new_path.len], new_path);
        lib.generation += 1;

        std.debug.print("Loaded DLL from {s}\n", .{new_path});
        init_layout_fn();
        return lib;
    }

    fn statSource(self: *const GameLib) !std.fs.File.Stat {
        return std.fs.cwd().statFile(self.sourcePath());
    }

    fn formatLoadedPath(self: *const GameLib, generation: usize, out: []u8) ![]const u8 {
        const dll_suffix = ".dll";
        const source = self.sourcePath();
        const base = if (std.mem.endsWith(u8, source, dll_suffix))
            source[0 .. source.len - dll_suffix.len]
        else
            source;
        return try std.fmt.bufPrint(out, "{s}_loaded_{d}.dll", .{ base, generation });
    }

    fn sourcePath(self: *const GameLib) []const u8 {
        return self.source_path_buf[0..self.source_path_len];
    }

    fn loadedPath(self: *const GameLib) []const u8 {
        return self.loaded_path_buf[0..self.loaded_path_len];
    }

    fn loadModule(path: []const u8) !windows.HMODULE {
        const wide = try std.unicode.utf8ToUtf16LeAllocZ(c_allocator, path);
        defer c_allocator.free(wide);

        const handle_opt = kernel32.LoadLibraryW(wide.ptr);
        if (handle_opt) |handle| {
            return handle;
        }
        const err_code = kernel32.GetLastError();
        std.debug.print("LoadLibraryW failed for {s} (win32 code {d})\n", .{ path, err_code });
        return error.LoadLibraryFailed;
    }

    fn copyFileOnce(self: *GameLib, dest: []const u8) !bool {
        std.fs.copyFileAbsolute(self.sourcePath(), dest, .{}) catch |err| switch (err) {
            error.FileNotFound,
            error.AccessDenied,
            error.SharingViolation,
            error.AntivirusInterference,
            error.PipeBusy,
            error.FileBusy,
            => {
                if (!self.copy_error_reported) {
                    std.debug.print("Waiting for DLL build output ({s})\n", .{@errorName(err)});
                    self.copy_error_reported = true;
                }
                return false;
            },
            else => return err,
        };

        self.copy_error_reported = false;
        return true;
    }

    fn computeHash(self: *const GameLib) ![Blake3.digest_length]u8 {
        var file = try std.fs.cwd().openFile(self.sourcePath(), .{});
        defer file.close();

        var hasher = Blake3.init(.{});
        var buffer: [4096]u8 = undefined;
        while (true) {
            const n = try file.read(buffer[0..]);
            if (n == 0) break;
            hasher.update(buffer[0..n]);
        }

        var out: [Blake3.digest_length]u8 = undefined;
        hasher.final(&out);
        return out;
    }

    fn loadUpdateFn(handle: windows.HMODULE) !UpdateAndRenderFn {
        const proc_addr_opt = kernel32.GetProcAddress(handle, "update_and_render");
        const proc_addr = proc_addr_opt orelse return error.GetProcAddressFailed;
        return @ptrCast(@alignCast(proc_addr));
    }

    fn loadInitLayoutFn(handle: windows.HMODULE) !InitLayoutFn {
        const proc_addr_opt = kernel32.GetProcAddress(handle, "init_layout");
        const proc_addr = proc_addr_opt orelse return error.GetProcAddressFailed;
        return @ptrCast(@alignCast(proc_addr));
    }

    fn loadCursorFn(handle: windows.HMODULE) ?ShouldShowHandCursorFn {
        const proc_addr_opt = kernel32.GetProcAddress(handle, "should_show_hand_cursor");
        return if (proc_addr_opt) |addr|
            @ptrCast(@alignCast(addr))
        else
            null;
    }

    fn reload(self: *GameLib) !bool {
        const stat = self.statSource() catch return false;
        const new_hash = self.computeHash() catch |err| switch (err) {
            error.FileNotFound,
            error.AccessDenied,
            error.SharingViolation,
            error.AntivirusInterference,
            error.PipeBusy,
            error.FileBusy,
            => return false,
            else => return err,
        };
        if (stat.mtime == self.last_write_time and
            stat.size == self.last_file_size and
            std.mem.eql(u8, new_hash[0..], self.last_hash[0..]))
        {
            return false;
        }

        if (std.mem.eql(u8, new_hash[0..], self.last_hash[0..])) {
            self.last_write_time = stat.mtime;
            self.last_file_size = stat.size;
            return false;
        }

        var new_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const new_path = try self.formatLoadedPath(self.generation, &new_path_buf);

        if (!(try self.copyFileOnce(new_path))) {
            return false;
        }

        std.debug.print("Reloading DLL...\n", .{});
        const start = std.time.milliTimestamp();

        errdefer std.fs.deleteFileAbsolute(new_path) catch {};

        const new_handle = try GameLib.loadModule(new_path);
        errdefer _ = kernel32.FreeLibrary(new_handle);

        const new_update = try GameLib.loadUpdateFn(new_handle);
        const new_cursor = GameLib.loadCursorFn(new_handle);
        const new_init_layout = try GameLib.loadInitLayoutFn(new_handle);

        const old_handle = self.handle;
        var old_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        var old_path: []const u8 = old_path_buf[0..0];
        if (self.loaded_path_len > 0) {
            const len = self.loaded_path_len;
            std.mem.copyForwards(u8, old_path_buf[0..len], self.loaded_path_buf[0..len]);
            old_path = old_path_buf[0..len];
        }

        self.update_and_render = new_update;
        self.should_show_hand_cursor = new_cursor;
        self.init_layout = new_init_layout;
        self.last_write_time = stat.mtime;
        self.last_file_size = stat.size;
        self.last_hash = new_hash;
        self.handle = new_handle;
        self.loaded_path_len = new_path.len;
        std.mem.copyForwards(u8, self.loaded_path_buf[0..new_path.len], new_path);
        self.generation += 1;
        new_init_layout();

        if (old_handle) |handle| {
            _ = kernel32.FreeLibrary(handle);
        }
        if (old_path.len > 0) {
            std.fs.deleteFileAbsolute(old_path) catch {};
        }
        const end = std.time.milliTimestamp();
        std.debug.print("Time taken to reload DLL: {d}ms\n", .{end - start});

        std.debug.print("DLL reloaded successfully from {s}\n", .{new_path});
        return true;
    }

    fn deinit(self: *GameLib) void {
        if (self.handle) |handle| {
            _ = kernel32.FreeLibrary(handle);
            self.handle = null;
        }

        const path = self.loadedPath();
        if (path.len > 0) {
            std.fs.deleteFileAbsolute(path) catch {};
            self.loaded_path_len = 0;
        }
    }
};

fn loadFont(file_data: ?[]const u8, font_id: u16, font_size: i32) !void {
    renderer.raylib_fonts[font_id] = try rl.loadFontFromMemory(".ttf", file_data, font_size * 2, null);
    rl.setTextureFilter(renderer.raylib_fonts[font_id].?.texture, .bilinear);
}

fn loadImage(comptime path: [:0]const u8) !rl.Texture2D {
    const texture = try rl.loadTextureFromImage(try rl.loadImageFromMemory(@ptrCast(std.fs.path.extension(path)), @embedFile(path)));
    rl.setTextureFilter(texture, .bilinear);
    return texture;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    rl.setConfigFlags(.{
        .msaa_4x_hint = true,
        .window_resizable = true,
    });
    rl.initWindow(1000, 1000, "Raylib zig Example - Hot Reload");
    defer rl.closeWindow();
    rl.setTargetFPS(120);

    try loadFont(@embedFile("./resources/Roboto-Regular.ttf"), 0, 24);
    const profile_picture = try loadImage("./resources/profile-picture.png");

    const dll_paths = [_][]const u8{ "zig-out/lib/game.dll", "zig-out/bin/game.dll", "game.dll" };
    var selected_path: ?[]const u8 = null;
    var newest_mtime: i128 = std.math.minInt(i128);

    for (dll_paths) |path| {
        const file = std.fs.cwd().openFile(path, .{}) catch continue;
        const stat = file.stat() catch {
            file.close();
            continue;
        };
        file.close();

        if (selected_path == null or stat.mtime > newest_mtime) {
            selected_path = path;
            newest_mtime = stat.mtime;
        }
    }

    if (selected_path == null) {
        std.debug.print(
            "Failed to locate game DLL. Build it first with: zig build game_dll\n",
            .{},
        );
        return error.LoadLibraryFailed;
    }

    var game_lib = GameLib.init(selected_path.?) catch |err| {
        std.debug.print("Failed to load DLL {s}: {}\n", .{ selected_path.?, err });
        return err;
    };
    defer game_lib.deinit();

    var debug_mode_enabled = false;
    var last_time = rl.getTime();

    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(.d)) {
            debug_mode_enabled = !debug_mode_enabled;
        }

        const current_time = rl.getTime();
        const delta_time = @as(f32, @floatCast(current_time - last_time));
        last_time = current_time;

        const mouse_pos = rl.getMousePosition();
        const scroll_delta = rl.getMouseWheelMoveV().multiply(.{ .x = 6, .y = 6 });

        _ = game_lib.reload() catch |err| {
            if (err != error.LoadLibraryFailed) {
                std.debug.print("Failed to reload DLL: {}\n", .{err});
            }
            return;
        };

        const ctx = GameContext{
            .screen_width = rl.getScreenWidth(),
            .screen_height = rl.getScreenHeight(),
            .mouse_x = mouse_pos.x,
            .mouse_y = mouse_pos.y,
            .mouse_down = rl.isMouseButtonDown(.left),
            .scroll_delta_x = scroll_delta.x,
            .scroll_delta_y = scroll_delta.y,
            .delta_time = delta_time,
            .profile_picture = &profile_picture,
            .debug_mode_enabled = debug_mode_enabled,
            .fonts = &renderer.raylib_fonts,
        };

        var render_commands_ptr: [*]cl.RenderCommand = undefined;
        var render_commands_len: usize = 0;
        game_lib.update_and_render(&ctx, &render_commands_ptr, &render_commands_len);

        if (game_lib.should_show_hand_cursor) |fn_ptr| {
            if (fn_ptr()) {
                rl.setMouseCursor(.pointing_hand);
            } else {
                rl.setMouseCursor(.arrow);
            }
        }

        rl.beginDrawing();
        rl.clearBackground(rl.Color{ .r = 200, .g = 200, .b = 200, .a = 255 });

        if (render_commands_len > 0) {
            const render_commands = render_commands_ptr[0..render_commands_len];
            renderer.clayRaylibRender(render_commands, allocator) catch {};
        }

        rl.endDrawing();
    }
}
