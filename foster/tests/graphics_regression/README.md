# Graphics regression

Run from PowerShell on Windows with Odin, a SPIR-V-capable DXC on PATH,
and a Windows SDK DXC with its matching DXIL validator, plus glslangValidator:

```powershell
./tests/graphics_regression/run.ps1
```

Override `-SpirvDxc` / `-DxilDxc` for other compiler locations and
`-GlslangValidator` for the GLSL compute compiler location. Use
`-Drivers vulkan` / `-Drivers d3d12` to test one backend. Both are tested by
default. These tests require a GPU supporting the tested HDR render formats.
They create offscreen targets without opening a window, and write build
artifacts under `build/graphics-regression`.

Checks cover compute readonly/readwrite textures and buffers, uniform data,
standalone and frame dispatch, shader recreation and invalid dispatch rejection;
native HDR upload/readback, RGBA16F/RGBA32F MRT output and alpha,
100 frames of replacement blending without clears, premultiplied blending,
pipeline cache separation, packed R11G11B10_UFLOAT output, and missing-shader
log deduplication. The D3D12 run also uses a valid shader with an incompatible
vertex input to trigger an actual pipeline creation failure. It checks shader
names in the error, deduplication across repeated draws, diagnostic reset on
shader recreation, and successful drawing after restoring a valid shader.

The two pipeline error lines in a successful D3D12 run are intentional: one
before and one after recreating the incompatible shader. A failed assertion
or a nonzero process exit fails the script.
