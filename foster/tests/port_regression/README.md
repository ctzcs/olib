# Port regression

Run from the repository root on Windows with Odin and the matching SDL3 runtime:

```powershell
New-Item -ItemType Directory -Force build | Out-Null
$odinRoot = (& odin root).Trim()
Copy-Item -LiteralPath (Join-Path $odinRoot 'vendor/sdl3/SDL3.dll') -Destination build
odin run tests/port_regression -collection:ofoster=src -out:build/port-regression.exe
```

The native executable tests D3D12 and Vulkan without opening a window. Checks
cover concave polygons in both windings, spatial/time/ease helpers, JSON array
and object converters, seeded RNG output, input filters and key/mouse press transitions, ZIP
Store/Deflate through the common storage API, directory enumeration, relative
ZIP roots, owned entry names, wildcard recursive enumeration and seekable streams;
writable streams with seek/write-at/flush/close and read-only ZIP write rejection.
The fixture `storage.zip`
contains a stored binary file, a Deflate text file, an empty file and directories.

Shared GPU checks verify offscreen orientation, partial updates of GPU-rendered
pixels, GPU clones, nearest scaled copies, stencil clipping, color write masks,
depth writing/comparison and repeated Batcher disposal.

For WebGL2, build the same checks and copy Odin's browser runtime:

```powershell
odin build tests/port_regression -collection:ofoster=src -target:js_wasm32 -out:build/port-regression.wasm
Copy-Item -LiteralPath (Join-Path $odinRoot 'core/sys/wasm/js/odin.js') -Destination tests/webtest/odin.js
python -m http.server 8139 --bind 127.0.0.1
```

Open `http://127.0.0.1:8139/tests/port_regression/?debug=1` in a browser.
Every group prints `PASS`; an assertion or browser exception is a failure.
The Web run also tests empty directories, persisted binary-safe storage,
directory enumeration and recursive removal under `/ofoster-port-regression`.
It creates and removes its own test files in that virtual namespace.
Native compute/HDR checks live in `../graphics_regression` and need additional
shader compilers described there. The browser test uses RGBA8, not every HDR format.

## Additional API and lifecycle checks

The shared suite covers component-ordered hexadecimal colors, StackList and
Polygon mutation, projection overlap, triangulation enumeration, same-frame
UTF-8 text accumulation and independent state-buffer storage, scaled text
kerning, sine offsets and wrapped line spacing. `zip64.zip` exercises ZIP64
end records and central-directory extra fields, CRC failures, truncated prefixes,
reinitialization and an end-record signature inside the comment. Regenerate it
with `python tests/port_regression/make_zip64.py`.

The real font fixture [Abel-Regular.ttf](fonts/Abel-Regular.ttf) comes from
[Google Fonts](https://github.com/google/fonts/tree/main/ofl/abel), under the
included [SIL Open Font License](fonts/OFL.txt). CPU allocation tracking covers
font rasterization and disposal, premultiplied and straight pixels, multi-page
packing, independent input disposal, MSDF parsing, Aseprite linked cels/string
ownership and PNG encode/decode. It asserts zero outstanding tracked allocations
and no invalid frees. The generated Aseprite fixture can be regenerated with
`python tests/port_regression/make_aseprite.py`.

D3D12, Vulkan and WebGL2 also verify that adding glyphs preserves existing atlas
textures and that pixel-perfect additions contain only binary alpha values.

## Browser input and file fixtures

Use `http://127.0.0.1:8139/tests/port_regression/?debug=1&input-tests=1` to enable
additional simulated browser tests. They exercise standard gamepad mapping,
button/axis transitions, rumble requests, DOM UTF-8/emoji/IME commits, text-input
toggling, cursor visibility/release, asynchronous clipboard success/denial,
file/folder binary import, UTF-8 paths, empty directories, ordered saves,
write failures, cancelled selection and missing picker APIs. Each asynchronous
group must print its final `PASS` as well as the shared groups.

The fixture temporarily replaces browser device, clipboard and picker methods,
then restores them. It does not access the OS clipboard, select personal files
or write real files. Hardware rumble, real system IME behavior, browser permission
prompts and actual native picker UI require manual validation. Imported virtual
snapshots and the temporary PNG are removed by the tests.
