# WGPU Backend Integration Plan for ClayUI

This document outlines a high-level implementation path for creating a new WGPU-based renderer for ClayUI, replacing the existing Raylib renderer. The new file will be `src/wgpu_render_clay.zig`. The design is based on the provided `imgui_wgpu_ref` implementation, emphasizing batched rendering for efficiency.

### 1. Core Renderer Structure (`wgpu_render_clay.zig`)

-   **`WgpuRenderer` Struct:** Create a central struct to own and manage all WGPU-related objects. This includes:
    -   `WGPUDevice`, `WGPUQueue`
    -   `WGPURenderPipeline`
    -   Vertex and Index `WGPUBuffer`s
    -   A uniform `WGPUBuffer` for the Model-View-Projection (MVP) matrix.
    -   A default `WGPUSampler` for textures.
    -   A `WGPUBindGroupLayout` for textures.

-   **`init()` Function:**
    -   Accepts a `WGPUDevice` and target `WGPUTextureFormat`.
    -   Creates the `WGPURenderPipeline`:
        -   Compiles embedded WGSL vertex and fragment shaders. The shaders will handle textured/colored vertices (`vec2<f32>` position, `vec2<f32>` uv, `vec4<f32>` color).
        -   Defines the vertex buffer layout matching ClayUI's vertex data.
        -   Sets up the necessary bind group layouts (one for common uniforms/sampler, one for per-draw-call textures).
    -   Initializes the uniform buffer, sampler, and other resources within the `WgpuRenderer` struct.

### 2. Render Loop (`clayWgpuRender`)

The main render function will be analogous to `raylib_render_clay.zig`'s `clayRaylibRender` but will target WGPU.

-   **Input:** Takes the list of `cl.RenderCommand`s and a `WGPURenderPassEncoder`.
-   **Vertex Generation:**
    -   Before drawing, iterate through all `RenderCommand`s and generate vertex/index data into host-side buffers (e.g., `std.ArrayList`).
    -   **Primitives:** `rectangle`, `border`, and `image` commands will be converted into sets of vertices forming quads or triangles.
    -   **Buffering:** Dynamically resize and write this data into a single large vertex buffer and index buffer for the entire frame using `wgpuQueueWriteBuffer`. This avoids multiple small buffer uploads.
-   **Drawing:**
    -   Set the render pipeline, vertex buffer, index buffer, and the common bind group (containing the MVP matrix and sampler) on the render pass encoder.
    -   Iterate through the `RenderCommand` list a second time to issue draw calls:
        -   **Scissoring:** Handle `.scissor_start` and `.scissor_end` by calling `wgpuRenderPassEncoderSetScissorRect`.
        -   **Texture Binding:** For `image` and `text` commands, get or create a `WGPUBindGroup` for the specific texture. Cache these bind groups in a map with the texture ID as the key to avoid recreation. Set this bind group on slot 1.
        -   **Draw Call:** Issue a `wgpuRenderPassEncoderDrawIndexed` call for each command or batch of commands that can be drawn together.

### 3. Texture & Font Handling

-   **Image Loading:**
    -   Create a helper function `loadWgpuTexture(device, queue, image_data)` that creates a `WGPUTexture` and `WGPUTextureView` from raw pixel data.
    -   The `cl.RenderCommand`'s `image_data` field will need to store a `WGPUTextureView` pointer (or a handle that can be resolved to one) to be used for binding.

### 4. Font Rendering

This can be approached in two ways: a simple bitmap implementation to start, and a more advanced instanced implementation for performance, as seen in the `msdf_text.zig` reference.

#### Approach A: Simple Bitmap Atlas (Good First Step)

This approach is simpler to implement initially.

1.  **Font Atlas:** On initialization, create a single texture containing rasterized glyphs for a font.
2.  **CPU-Side Vertex Generation:** For each `.text` command, iterate through its characters on the CPU. For each character, generate a quad (4 vertices) with the correct position and UV coordinates from the font atlas.
3.  **Drawing:** Add these vertices to the main vertex/index buffers for the frame and draw them as part of the single batched `drawIndexed` call.
4.  **Measurement:** A `measureText` function needs to be implemented that calculates text dimensions using the font's glyph metrics, independent of any rendering library.

#### Approach B: Instanced Drawing (Recommended for Performance)

This approach is significantly more efficient, especially for dynamic text.

1.  **GPU Data Buffers:**
    *   **Glyph Buffer:** Create a `WGPUBuffer` with `WGPUBufferUsage_Storage` to hold an array of all glyph metrics for a font (advance, size, offsets, texture coordinates). This is uploaded once when the font is loaded.
    *   **Instance Buffer:** Each frame, create a second `WGPUBuffer` containing an array of instance data. Each element would specify a character's `position` and its `glyph_index` into the glyph buffer. This is the only text-related buffer that needs to be updated per frame.

2.  **Instanced Drawing:**
    *   The render pipeline will be configured for instancing and will not take a per-vertex buffer input.
    *   The vertex shader generates quad vertices on the fly. It uses `builtin(vertex_index)` to identify the corner of the quad and `builtin(instance_index)` to look up the character's instance data from the instance buffer. It then uses the `glyph_index` to look up the full metrics from the glyph storage buffer.
    *   The draw call becomes `wgpuRenderPassEncoderDraw(4, character_count, 0, 0)`.
