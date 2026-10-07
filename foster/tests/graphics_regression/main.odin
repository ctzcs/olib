package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import SDL "vendor:sdl3"
import foster "ofoster:."

pipeline_errors: int
validation_errors: int

capture_log :: proc "c" (userdata: rawptr, category: SDL.LogCategory, priority: SDL.LogPriority, message: cstring) {
    context = runtime.default_context()
    text := string(message)
    if strings.contains(text, "OFoster: SDL_CreateGPUGraphicsPipeline failed") {
        assert(strings.contains(text, "vertex='incompatible'") && strings.contains(text, "fragment='hdr-fragment'"))
        pipeline_errors += 1
    }
    if strings.contains(text, "OFoster: draw requires both") { validation_errors += 1 }
    fmt.println(text)
}

begin :: proc(device: ^foster.GraphicsDevice) {
    device.CommandBuffer = SDL.AcquireGPUCommandBuffer(device.Device)
    assert(device.CommandBuffer != nil)
    device.InFrame = true
}

submit :: proc(device: ^foster.GraphicsDevice) {
    foster.end_render_pass(device)
    assert(SDL.SubmitGPUCommandBuffer(device.CommandBuffer))
    device.CommandBuffer = nil
    device.InFrame = false
    assert(SDL.WaitForGPUIdle(device.Device))
}

load_shader :: proc(shader: ^foster.Shader, device: ^foster.GraphicsDevice, directory, file, entry, name: string, stage: foster.ShaderStage, uniforms: int) {
    extension := device.Driver == .D3D12 ? "dxil" : "spv"
    path := fmt.tprintf("%s/%s.%s", directory, file, extension)
    code, err := os.read_entire_file(path, context.allocator)
    assert(err == nil)
    // Shader.CreateInfo retains Code for recreation. Freed after ShaderDispose.
    foster.ShaderInit(shader, device, foster.ShaderCreateInfo{
        Stage = stage, Code = code, EntryPoint = entry, UniformBufferCount = uniforms,
    }, name)
}

dispose_shader :: proc(shader: ^foster.Shader) {
    code := shader.CreateInfo.Code
    foster.ShaderDispose(shader)
    delete(code)
}

verify_pixels :: proc(texture: ^foster.Texture, expected: [4]f32) {
    data := foster.TextureDownloadData(texture)
    defer delete(data)
    assert(len(data) == foster.TextureMemorySize(texture))
    for pixel in 0..<texture.Width * texture.Height {
        #partial switch texture.Format {
        case .R16G16B16A16_FLOAT:
            values := ([^]f16)(raw_data(data))
            for component in 0..<4 { assert(f32(values[pixel * 4 + component]) == expected[component]) }
        case .R32G32B32A32_FLOAT:
            values := ([^]f32)(raw_data(data))
            for component in 0..<4 { assert(values[pixel * 4 + component] == expected[component]) }
        case .R11G11B10_UFLOAT:
            // Exact packed representation of RGB = (2, 4, 8).
            packed := ([^]u32)(raw_data(data))
            assert(packed[pixel] == (u32(16 << 6) | u32(17 << 6) << 11 | u32(18 << 5) << 22))
        }
    }
    // Exercise upload/readback of the same native bits on a sampled texture.
    clone: foster.Texture
    foster.TextureInit(&clone, texture.GraphicsDevice, texture.Width, texture.Height, texture.Format)
    defer foster.TextureDispose(&clone)
    foster.TextureSetData(&clone, raw_data(data), len(data))
    roundtrip := foster.TextureDownloadData(&clone)
    defer delete(roundtrip)
    assert(len(roundtrip) == len(data))
    for value, i in data { assert(roundtrip[i] == value) }
}

verify_compute :: proc(device: ^foster.GraphicsDevice, directory: string) {
    extension := device.Driver == .D3D12 ? "dxil" : "spv"
    code, err := os.read_entire_file(fmt.tprintf("%s/compute.%s", directory, extension), context.allocator)
    assert(err == nil)
    defer delete(code)
    shader: foster.Shader
    foster.ShaderInit(&shader, device, foster.ShaderCreateInfo{
        Stage = .Compute, Code = code, EntryPoint = device.Driver == .D3D12 ? "compute_main" : "main",
        ReadOnlyStorageTextureCount = 1, ReadOnlyStorageBufferCount = 1,
        ReadWriteStorageTextureCount = 1, ReadWriteStorageBufferCount = 1,
        UniformBufferCount = 1, ThreadCountX = 4, ThreadCountY = 4, ThreadCountZ = 1,
    }, "compute-regression")
    defer foster.ShaderDispose(&shader)
    source, output: foster.Texture
    foster.TextureInitFlags(&source, device, 8, 8, .R32G32B32A32_FLOAT, {.ComputeRead}, "input")
    foster.TextureInitFlags(&output, device, 8, 8, .R32G32B32A32_FLOAT, {.ComputeRead, .ComputeWrite}, "output")
    defer foster.TextureDispose(&source)
    defer foster.TextureDispose(&output)
    pixels: [64][4]f32
    for i in 0..<64 { pixels[i] = {1, 2, 3, 4} }
    foster.TextureSetData(&source, raw_data(pixels[:]), size_of(pixels))
    input: foster.StorageBuffer
    buffer: foster.ComputeStorageBuffer
    foster.StorageBufferInit(&input, device, size_of([4]f32))
    foster.ComputeStorageBufferInit(&buffer, device, size_of([4]f32))
    defer foster.StorageBufferDispose(&input)
    defer foster.ComputeStorageBufferDispose(&buffer)
    foster.StorageBufferUpload(&input, raw_data(pixels[:]), 64)
    foster.ComputeStorageBufferUpload(&buffer, raw_data(pixels[:]), 64)
    command: foster.ComputeCommand
    foster.ComputeCommandInit(&command)
    defer foster.ComputeCommandDispose(&command)
    command.Shader = &shader
    command.GroupCountX = 2
    command.GroupCountY = 2
    append(&command.ReadOnlyStorageTextures, &source)
    append(&command.ReadOnlyStorageBuffers, &input)
    append(&command.ReadWriteStorageTextures, &output)
    append(&command.ReadWriteStorageBuffers, &buffer)
    uniform: foster.UniformBuffer
    params := [1][4]f32{{10, 20, 30, 40}}
    foster.UniformBufferInit(&uniform)
    foster.UniformBufferSet(&uniform, mem.slice_to_bytes(params[:]))
    defer foster.UniformBufferDispose(&uniform)
    append(&command.UniformBuffers, uniform)
    // The standalone path must end its compute pass before submitting.
    assert(foster.GraphicsDeviceDispatch(device, &command))
    assert(SDL.WaitForGPUIdle(device.Device))
    verify_pixels(&output, {12, 24, 36, 48})
    // Repeat in an existing frame and after shader recreation.
    foster.ShaderRecreate(&shader, shader.CreateInfo)
    begin(device)
    assert(foster.GraphicsDeviceDispatch(device, &command))
    submit(device)
    verify_pixels(&output, {12, 24, 36, 48})
    // Read the writable storage buffer independently of the texture output.
    transfer := SDL.CreateGPUTransferBuffer(device.Device, {usage = .DOWNLOAD, size = size_of(pixels)})
    assert(transfer != nil)
    defer SDL.ReleaseGPUTransferBuffer(device.Device, transfer)
    cb := SDL.AcquireGPUCommandBuffer(device.Device)
    pass := SDL.BeginGPUCopyPass(cb)
    SDL.DownloadFromGPUBuffer(pass, {buffer = buffer.Base.Resource, size = size_of(pixels)}, {transfer_buffer = transfer})
    SDL.EndGPUCopyPass(pass)
    assert(SDL.SubmitGPUCommandBuffer(cb) && SDL.WaitForGPUIdle(device.Device))
    ptr := SDL.MapGPUTransferBuffer(device.Device, transfer, false)
    assert(ptr != nil)
    values := ([^][4]f32)(ptr)
    for i in 0..<64 { assert(values[i] == [4]f32{24, 48, 72, 96}) }
    SDL.UnmapGPUTransferBuffer(device.Device, transfer)
    command.GroupCountX = 0
    assert(!foster.GraphicsDeviceDispatch(device, &command))
    command.GroupCountX = 2
    buffer.Base.Disposed = true
    assert(!foster.GraphicsDeviceDispatch(device, &command))
    buffer.Base.Disposed = false
    fmt.println("PASS: compute readonly/readwrite textures and buffers, uniform data, standalone/frame dispatch and recreation")
}

run :: proc(driver: foster.GraphicsDriver, directory: string) {
    driver_name: cstring = driver == .D3D12 ? "direct3d12" : "vulkan"
    device := foster.GraphicsDevice{Driver = driver}
    device.Device = SDL.CreateGPUDevice({.SPIRV, .DXIL}, false, driver_name)
    assert(device.Device != nil, string(SDL.GetError()))
    defer SDL.DestroyGPUDevice(device.Device)
    defer foster.graphics_device_dispose_caches(&device)
    fmt.println("Testing", driver)
    verify_compute(&device, directory)

    vertex, fragment: foster.Shader
    load_shader(&vertex, &device, directory, "vertex", "vertex_main", "hdr-vertex", .Vertex, 0)
    defer dispose_shader(&vertex)
    load_shader(&fragment, &device, directory, "fragment", "fragment_main", "hdr-fragment", .Fragment, 1)
    defer dispose_shader(&fragment)
    material: foster.Material
    foster.MaterialInit(&material, &vertex, &fragment)
    defer delete(material.Fragment.UniformBuffers[0])
    defer foster.UniformBufferDispose(&material.Fragment.UniformBufferObjects[0])
    mesh: foster.Mesh
    foster.MeshInitTyped(foster.BatcherVertex, &mesh, &device, foster.IndexFormat.Sixteen)
    defer foster.MeshDispose(&mesh)
    vertices := [3]foster.BatcherVertex{
        foster.MakeBatcherVertex({-1, -1}, {}, foster.White, foster.White),
        foster.MakeBatcherVertex({3, -1}, {}, foster.White, foster.White),
        foster.MakeBatcherVertex({-1, 3}, {}, foster.White, foster.White),
    }
    foster.MeshSetVerticesTyped(foster.BatcherVertex, &mesh, vertices[:])

    target: foster.Target
    attachments := [2]foster.TargetAttachmentSpec{
        {Format = .R16G16B16A16_FLOAT}, {Format = .R32G32B32A32_FLOAT},
    }
    foster.TargetInit(&target, &device, 16, 16, attachments[:], "HDR MRT")
    defer foster.TargetDispose(&target)
    command: foster.DrawCommand
    foster.DrawCommandFromMesh(&command, foster.DrawableTargetFromTarget(&target), &mesh, &material)
    defer foster.DrawCommandDispose(&command)
    assert(command.BlendMode == foster.BlendModePremultiply)
    assert(foster.BlendModeDisabled == foster.BlendModeMake(.Add, .One, .Zero))
    command.BlendMode = foster.BlendModeDisabled
    params := [1][4]f32{{2, 4, 8, 0.25}}
    foster.MaterialStageSetUniformBuffer(&material.Fragment, mem.slice_to_bytes(params[:]), 0)
    for frame in 0..<100 {
        begin(&device)
        foster.GraphicsDeviceDraw(&device, &command)
        submit(&device)
        if frame == 0 || frame == 99 {
            verify_pixels(foster.TargetAttachment(&target, 0), {2, 4, 8, 0.25})
            verify_pixels(foster.TargetAttachment(&target, 1), {4, 8, 16, 0.5})
        }
        free_all(context.temp_allocator)
    }
    assert(len(device.PipelineCache) == 1)
    fmt.println("PASS: RGBA16F/RGBA32F MRT, HDR values, alpha and upload/download stable for 100 frames")

    // Switching back to premultiplied blending must select a distinct pipeline.
    command.BlendMode = foster.BlendModePremultiply
    begin(&device)
    foster.GraphicsDeviceDraw(&device, &command)
    submit(&device)
    verify_pixels(foster.TargetAttachment(&target, 0), {3.5, 7, 14, 0.4375})
    assert(len(device.PipelineCache) == 2)
    command.BlendMode = foster.BlendModeDisabled
    fmt.println("PASS: premultiplied blending and pipeline cache separation")

    packed_target: foster.Target
    packed_attachments := [2]foster.TargetAttachmentSpec{
        {Format = .R11G11B10_UFLOAT}, {Format = .R16G16B16A16_FLOAT},
    }
    foster.TargetInit(&packed_target, &device, 16, 16, packed_attachments[:], "Packed HDR")
    defer foster.TargetDispose(&packed_target)
    command.Target = foster.DrawableTargetFromTarget(&packed_target)
    begin(&device)
    foster.GraphicsDeviceDraw(&device, &command)
    submit(&device)
    verify_pixels(foster.TargetAttachment(&packed_target, 0), {2, 4, 8, 0.25})
    fmt.println("PASS: packed R11G11B10_UFLOAT render and upload/download")

    before := validation_errors
    material.Vertex.Shader = nil
    begin(&device)
    for _ in 0..<100 { foster.GraphicsDeviceDraw(&device, &command) }
    submit(&device)
    material.Vertex.Shader = &vertex
    assert(validation_errors == before + 1)
    fmt.println("PASS: missing shader reports once without crashing")

    if driver == .D3D12 {
        incompatible: foster.Shader
        load_shader(&incompatible, &device, directory, "incompatible", "incompatible_vertex", "incompatible", .Vertex, 0)
        defer dispose_shader(&incompatible)
        material.Vertex.Shader = &incompatible
        before_pipeline := pipeline_errors
        for _ in 0..<3 {
            begin(&device)
            foster.GraphicsDeviceDraw(&device, &command)
            submit(&device)
        }
        assert(pipeline_errors == before_pipeline + 1)
        assert(len(device.FailedPipelineHashes) == 1)
        foster.ShaderRecreate(&incompatible, incompatible.CreateInfo)
        assert(len(device.FailedPipelineHashes) == 0)
        begin(&device)
        foster.GraphicsDeviceDraw(&device, &command)
        submit(&device)
        assert(pipeline_errors == before_pipeline + 2)
        material.Vertex.Shader = &vertex
        begin(&device)
        foster.GraphicsDeviceDraw(&device, &command)
        submit(&device)
        verify_pixels(foster.TargetAttachment(&packed_target, 0), {2, 4, 8, 0.25})
        fmt.println("PASS: actual pipeline failure logs names/error once, recreation resets diagnostics, valid draw recovers")
    }
}

main :: proc() {
    assert(len(os.args) == 3, "usage: graphics-regression <d3d12|vulkan> <shader-directory>")
    assert(SDL.Init({.VIDEO}), string(SDL.GetError()))
    defer SDL.Quit()
    SDL.SetLogOutputFunction(capture_log, nil)
    driver := os.args[1] == "d3d12" ? foster.GraphicsDriver.D3D12 : foster.GraphicsDriver.Vulkan
    run(driver, os.args[2])
}
