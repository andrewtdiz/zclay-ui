Clay UI Hot Reload Demo
=======================

Overview
--------
- Zig + Raylib host executable that keeps the window, GPU state, and Clay allocator alive between reloads.
- Gameplay/UI code lives in a dynamic library that exports `init_layout`, `update_and_render`, and `should_show_hand_cursor`.
- Host copies, hashes, and loads freshly built DLLs, calling `init_layout` after every reload to reset Clay state.

Quick Start
-----------
1. `zig build game_dll --watch` – keeps the Clay/Raylib DLL rebuilt on file changes.
2. `zig build run` – launches the host; it picks the newest `game.dll` from `zig-out`.
3. Edit files under `src/` (e.g. `layout.zig`); the host console prints “Reloading DLL…” and the window updates without restarting.

Project Layout
--------------
- `src/host.zig` – win32 loader, input capture, DLL staging, and Clay draw submission.
- `src/game.zig` – exported API surface from the DLL, Clay setup, and command buffer handoff.
- `src/layout.zig` – example Clay UI tree rendered through Raylib.
- `build.zig` – builds the static Clay C shim, the Raylib host executable, and the hot-reloadable DLL.

Notes
-----
- Requires a Windows environment; the dynamic loader uses `LoadLibraryW` and Win32 file APIs.
- Always flush writers created through the new `std.Io.Writer` interface when adding logging.
- Verify Zig stdlib API usage with `zigdoc`; the build is pegged to the Zig version configured for the workspace.
