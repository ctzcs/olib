# Foster Odin port

OFoster is an Odin implementation of the [Foster](https://github.com/FosterFramework/Foster)
2D game framework.

本目录已并入 olib，原 OFoster 仓库停止维护。上游 MIT 声明见 [LICENSE](LICENSE)，
版权文本取自下述 Foster sync baseline 的 [上游 LICENSE](https://github.com/FosterFramework/Foster/blob/06213b9cec2b29c715795a23253595d517ca13d2/LICENSE)。

## Requirements

- Odin nightly (the project uses the `vendor:sdl3` package shipped with Odin)
- SDL3 runtime available from the Odin distribution

## Foster sync baseline

This Odin port tracks the following upstream Foster source baseline:

- Upstream: [FosterFramework/Foster](https://github.com/FosterFramework/Foster)
- Foster version: `v0.4.2`
- Source commit: [`06213b9cec2b29c715795a23253595d517ca13d2`](https://github.com/FosterFramework/Foster/commit/06213b9cec2b29c715795a23253595d517ca13d2)
- Commit date: `2026-08-31`
- Release date: `2026-08-27`

The upstream `v0.4.2` line includes API changes after the previous `v0.3.0`
baseline. The Odin port is synchronized against this commit for version
tracking, with the remaining API differences to be ported incrementally.
When synchronizing later, compare upstream changes after this commit and update
this section together with `FosterVersionMajor`, `FosterVersionMinor`, and
`FosterVersionPatch` in `framework.odin`.

The 0.4.2 additions currently exposed by the port include stencil/fill draw
state, texture flags and region operations, compute pipeline/dispatch types,
uniform buffers, storage backends (including Store/Deflate and ZIP64 archives),
convex hull and rectangle difference helpers, and virtual-input
activation/manual-update helpers. The SDL3 bindings supplied with Odin are
used directly.

The library package is `foster/` in the olib repository. Runnable examples (Foster basics and
kit/ui demos) are maintained in the separate `OFoster_Sample` project, checked out next to olib.

## Use the framework

Import the Foster package from an Odin program. When building from the olib repository root,
use `-collection:olib=.`:

```odin
import foster "olib:foster"
```

The package mirrors Foster's public concepts: `App`, `Window`, `GraphicsDevice`,
`Texture`, `Target`, `Shader`, `Material`, `Mesh`, input bindings, spatial
primitives, storage helpers, and utility functions. Everything lives in the
single package under `foster/`, organized as topic files (`framework.odin`, `input.odin`,
`spatial.odin`, `storage.odin`, ...). The mapping from upstream Foster's C#
files to these files, plus intentional API differences, is documented in
[PORTING_MAP.md](docs/PORTING_MAP.md). The only subpackages are the internal ones:
`internal/third_party` (vendored C bindings) and `internal/web` (JS side of
the web bridge).

`tick_app` clears `context.temp_allocator` at the end of every frame, after
`RenderProc` and `end_frame`, on both native and Web targets. Temporary allocations
from Update/Render expire at that point; Startup allocations expire at the end of
the first frame. Keep data needed across frames in a persistent allocator.

`RelativeStorageContainer` returns a container borrowing the relative storage's
owned path. That path survives frame cleanup, but expires when the resolved path
changes or `RelativeStorageDispose` is called. Dispose the relative storage when
finished; its base container and prefix are borrowed. Do not copy an owning
relative storage and dispose both copies. If title storage cannot get SDL's base
path, an empty `Root` resolves paths relative to the current working directory.

## Directory layout (relative to `foster/`)

- `./`: the library package itself — `framework.odin` (app lifecycle, window,
  version), `foundation.odin` (math/color basics), `graphics.odin` (the GPU
  layer incl. Batcher), `images.odin` (image loading and fonts), `input.odin`,
  `spatial.odin`, `utility.odin`, `storage.odin`, `web.odin` (js bridge), plus
  `#+build` platform pair (`platform_native.odin` / `platform_web.odin`).
- `assets/shaders/`: default shaders embedded at compile time via `#load`.
- `internal/`: vendored C bindings (`third_party`) and the web bridge JS
  (`web`).
- `tests/`: `webtest` (web acceptance program), `graphics_regression`
  (native GPU suite) and `port_regression` (shared native/Web port checks).
- `docs/`: supplementary documentation — `PORTING_MAP.md` (upstream file
  mapping and API differences), `LOCAL_CHANGES.md` (olib's intentional deviations
  from upstream, tracked for re-syncing), `CODE_STYLE.md` (source layout and formatting),
  and `WEB_TARGET_REQUIREMENTS.md` (web target
  requirements and acceptance notes).
- `../build/`: git-ignored scratch space at the olib root for local harnesses and artifacts.

## Source layout and formatting

Each library file has a section index and hierarchical comments matching the
upstream directories and types. Major sections use `// ===` separators, and
types or smaller groups use `// ---` separators. Procedure bodies, control flow
and struct fields are expanded across lines for readability.

Follow [CODE_STYLE.md](docs/CODE_STYLE.md) when adding, porting or maintaining
code. It defines the section hierarchy, navigation comments, multiline layout
and examples. Keep related procedures in their existing sections and update the
file's section index when adding a new group.

The shared formatter settings are in `odinfmt.json`. With `odinfmt` available,
format the library from the olib repository root:

```powershell
odinfmt -path:foster -config:foster/odinfmt.json -w
```

## Port coverage and verification

The 2026-10-06 port update adds complete native compute resource binding
(samplers, readonly/readwrite textures and buffers, uniforms), GPU texture
clone/partial upload/scaled blit, Batcher stencil state and resource disposal,
concave polygon triangulation, input mask filtering and press transitions,
easing/time/spatial helpers, and JSON vector/matrix conversion procedures.
ZIP containers now work through the common storage API, including relative
roots, filtered/recursive directory enumeration, seekable `OpenRead` streams
and writable `Create` streams. Writes are buffered until Flush/Close/Destroy;
Create immediately truncates the destination. Destroy streams
with `io.destroy`; returned strings, byte slices and directory names are owned
by the caller. Keep `ZipStorage` alive and at a stable address while using its
container or relative views.

Seeded RNG integer/float/double output now follows the upstream bit-generation
rules on both native and Web targets. This changes sequences produced by older
OFoster versions for those methods; `RngU64` retains its existing sequence.

The update also completes StackList and Polygon mutation helpers, hex component
ordering, direction/sign parsing, projection overlap, triangulation enumerators,
incremental GPU font atlases, sine-wave and scaled/wrapped text drawing. Font
kerning now translates codepoints to glyph indices. Image, font, packer, Aseprite
and independent input disposal release owned allocations; linked Aseprite cels
and strings survive release of the original input. ZIP initialization accepts
files, memory or a storage container, handles ZIP64, and reports CRC/structural
errors through `ZipStorage.Error`, with no partially decoded entries exposed.

The WebGL2 bridge additionally supports offscreen color/depth/stencil targets,
depth and stencil draw state, RGBA8/R8/RG8/RGBA32F texture readback, GPU cloning
and scaled copies, PNG export to virtual storage, and persistent directory-aware
storage. It now bridges gamepads/rumble, UTF-8 and IME text, CSS/custom cursors,
asynchronous clipboard access and file/folder/save pickers. Browser pickers
require a supported File System Access API and user activation; unsupported or
cancelled pickers return an empty/cancelled result. Picked paths are virtual
snapshots. Writes to selected save files are queued; `FlushStorageFileAsync`
confirms completion, while the synchronous write result confirms virtual storage.
Web compute, graphics storage buffers, wireframe fill and attachment MSAA remain
outside WebGL2 coverage.
Custom Web shaders use the bridge's named uniforms (`u_matrix`, `u_tex`,
`u_distance_range`), rather than arbitrary native uniform-buffer layouts.
`GetClipboardString` returns an owned string (delete it); Web reads return the
last cached clipboard text. Use `RequestClipboardString` / `SetClipboardStringAsync`
for browser completion and permission failures. Callback text/paths are borrowed
for the callback duration. See [PORTING_MAP.md](docs/PORTING_MAP.md) for API adaptations and verification
limits; the baseline above is not a claim of complete C# API equivalence.

Run from the olib repository root on Windows:

```powershell
odin check foster -collection:olib=. -no-entry-point
odin run foster/tests/port_regression -collection:olib=. -out:build/port-regression.exe
./foster/tests/graphics_regression/run.ps1
```

The graphics suites exercise D3D12 and Vulkan. The native compute regression
requires DXC and `glslangValidator`; see its [README](tests/graphics_regression/README.md).
For browser checks, follow [tests/port_regression/README.md](tests/port_regression/README.md).

## App usage

Odin does not have C#-style class inheritance. Use composition: put an `App`
inside your game state, register lifecycle procedures, and attach the state with
`AppSetUserData` when callbacks need access to it.

```odin
package main

import foster "olib:foster"

Game :: struct {
    App: foster.App,
    Score: int,
}

startup :: proc(app: ^foster.App) {
    game := cast(^Game)foster.AppGetUserData(app)
    game.Score = 0
}

update :: proc(app: ^foster.App) {
    game := cast(^Game)foster.AppGetUserData(app)
    game.Score += 1
    if app.Time.Frame >= 60 {
        foster.Exit(app)
    }
}

main :: proc() {
    game := Game{}
    config := foster.DefaultAppConfig("MyGame", 1280, 720)
    foster.InitApp(&game.App, config)
    defer foster.Dispose(&game.App)

    foster.AppSetUserData(&game.App, rawptr(&game))
    game.App.StartupProc = startup
    game.App.UpdateProc = update
    foster.Run(&game.App)
}
```

For a small program with no custom state, the callbacks can simply use the
`^foster.App` argument directly, as shown in the `OFoster_Sample` project.

## Writing custom shaders

### Resource bindings and vertex inputs

Follow the [SDL GPU shader binding conventions](https://wiki.libsdl.org/SDL3/SDL_CreateGPUShader):

| Stage / format | Sampled textures, samplers and storage | Uniform buffers |
| --- | --- | --- |
| Vertex / SPIR-V | set 0 | set 1 |
| Fragment / SPIR-V | set 2 | set 3 |
| Vertex / DXIL | `t[n]` / `s[n]`, space0 | `b[n]`, space1 |
| Fragment / DXIL | `t[n]` / `s[n]`, space2 | `b[n]`, space3 |

Start each set/register sequence at zero without gaps. Order sampled textures
and samplers first, then storage textures, then storage buffers. The port's
graphics shader API currently exposes sampled textures and storage buffers;
it does not expose graphics-stage storage textures.

For example, this HLSL fragment shader uses one texture/sampler pair and one
uniform buffer. Compile the same source to SPIR-V or DXIL:

```hlsl
Texture2D scene_tex : register(t0, space2);
SamplerState scene_samp : register(s0, space2);
cbuffer Params : register(b0, space3) {
    float4 u_value;
};

float4 main(float2 uv : TEXCOORD0) : SV_Target0 {
    return scene_tex.Sample(scene_samp, uv) * u_value;
}
```

Use `TEXCOORD0`, `TEXCOORD1`, etc. for vertex attributes under SDL's default
D3D12 semantic mapping; system semantics such as `SV_Position` are separate.
The port's `BatcherVertex` is 24 bytes: location 0 is `float2` position,
location 1 is `float2` UV, and locations 2/3 are normalized four-byte colors.
Match this layout or supply your own vertex format.

### Shader metadata and uniform data

Set `ShaderCreateInfo.SamplerCount`, `UniformBufferCount` and
`StorageBufferCount` to match the compiled shader's resources. In the example
above they are 1, 1 and 0. The port chooses the shader binary format from the
device's `Driver`; pass the corresponding SPIR-V, DXIL or MSL code.

Use `MaterialStageSetUniformBuffer` to supply bytes. The draw path pushes
these bytes into the corresponding SDL uniform slot:

```odin
import "core:mem"

params := [1][4]f32{{1, 1, 1, 1}}
foster.MaterialStageSetUniformBuffer(&material.Fragment, mem.slice_to_bytes(params[:]), 0)
```

Do not use `transmute([]u8)` to turn a typed slice into bytes: it preserves
the slice's element count rather than multiplying by element size. A slice
of ten `float4` values needs 160 bytes, not 10.

Respect [SDL's std140 uniform layout requirements](https://wiki.libsdl.org/SDL3/SDL_PushGPUFragmentUniformData).
Using arrays of `float4` / `[4]f32` is straightforward. For mixed structs,
calculate member offsets and padding explicitly; `vec3` and `vec4` fields
must start on 16-byte boundaries.

### Compiling and loading on Windows

```text
dxc -spirv -T ps_6_0 -E main -Fo custom.frag.spv custom.frag.hlsl
dxc        -T ps_6_0 -E main -Fo custom.frag.dxil custom.frag.hlsl
```

Use `vs_6_0` for a vertex shader. Use a matching `dxc.exe` / `dxil.dll` pair
when producing DXIL, and keep container validation enabled. The downstream
glade project reported a validator mismatch with its Vulkan SDK 1.3.261
installation and succeeded with the Windows SDK's DXC 1.8 toolchain.
Treat this as a tool installation issue, not a restriction on SPIR-V output.
Skipping validation with `-Vd` is not a reliable fix for rejected DXIL.

Ship the SDL3 runtime matching your Odin bindings beside the executable to
avoid accidentally loading a different DLL from `PATH`. The downstream
rendering checks used SDL 3.4.2 with D3D12 and Vulkan; this is a tested
baseline, not a claim that all binding conventions require SDL 3.4 or newer.

### Fullscreen passes, HDR and diagnostics

Set `command.BlendMode = foster.BlendModeDisabled` for passes that fully
replace their destination. This disables hardware blending. It is equivalent
to the existing `BlendModeMake(.Add, .One, .Zero)` value. Draw commands and
Batcher still default to premultiplied alpha blending. When alpha is below
one, that default retains some destination color; clear the target or choose
replacement blending as appropriate.

HDR color formats are `R16G16B16A16_FLOAT` (8 bytes/texel),
`R32G32B32A32_FLOAT` (16), and `R11G11B10_UFLOAT` (4, packed unsigned RGB
without alpha). Use them in `TargetAttachmentSpec.Format` for HDR targets,
including MRT. Check support on the actual graphics device.
`TextureSetData` and `TextureDownloadData` transfer native texel bits without
conversion: decode half floats, floats or packed unsigned floats accordingly.
Read back after the rendering command buffer has been submitted, such as in
the next update, and release the returned slice with `delete`.

Draw validation and render-pass failures use SDL's GPU error log category
once per failure reason per device. Pipeline creation failures include both
shader names and `SDL.GetError()`, once per pipeline hash. Shader recreation
or disposal clears associated pipeline failure records. Applications can
redirect these messages through `SDL.SetLogOutputFunction`.
