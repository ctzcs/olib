package main

import "core:fmt"
import "core:mem"
import foster "olib:foster"

verify_graphics :: proc(device: ^foster.GraphicsDevice, flush: proc(_: ^foster.GraphicsDevice)) {
	verify_msaa_graphics(device, flush)
	verify_depth_sampling(device, flush)
	verify_font_graphics(device, flush)
	batcher: foster.Batcher
	foster.BatcherInit(&batcher, device)
	defer foster.BatcherDispose(&batcher)
	white: foster.Texture
	foster.TextureInit(&white, device, 1, 1)
	defer foster.TextureDispose(&white)
	white_pixel := [1]foster.Color{foster.White}
	foster.TextureSetData(&white, raw_data(white_pixel[:]), size_of(white_pixel))
	target: foster.Target
	foster.TargetInit(&target, device, 8, 8)
	defer foster.TargetDispose(&target)
	offscreen := foster.DrawableTargetFromTarget(&target)
	foster.GraphicsDeviceClear(device, offscreen, foster.Black)
	batcher.Texture = &white
	foster.BatcherRect(&batcher, {0, 0, 8, 4}, foster.Color{255, 0, 0, 255})
	foster.BatcherRect(&batcher, {0, 4, 8, 4}, foster.Color{0, 0, 255, 255})
	foster.BatcherRender(&batcher, offscreen)
	flush(device)
	texture := foster.TargetAttachment(&target, 0)
	pixels := foster.TextureDownloadData(texture)
	defer delete(pixels)
	assert(len(pixels) == 256)
	for y in 0 ..< 8 {
		for x in 0 ..< 8 {
			i := (x + y * 8) * 4
			assert(
				pixels[i] == (y < 4 ? 255 : 0) &&
				pixels[i + 2] == (y < 4 ? 0 : 255) &&
				pixels[i + 3] == 255,
			)
		}
	}
	patch := [1]foster.Color{{0, 255, 0, 255}}
	foster.TextureSetDataRegion(texture, mem.slice_to_bytes(patch[:]), 1, 1, 1, 1)
	clone := foster.TextureClone(texture)
	defer foster.TextureDispose(&clone)
	flush(device)
	cloned := foster.TextureDownloadData(&clone)
	defer delete(cloned)
	assert(cloned[(1 + 8) * 4 + 1] == 255 && cloned[(7 + 7 * 8) * 4 + 2] == 255)
	scaled: foster.Texture
	foster.TextureInit(&scaled, device, 16, 16)
	defer foster.TextureDispose(&scaled)
	foster.TextureBlit(&clone, &scaled, {0, 0, 8, 8}, {0, 0, 16, 16})
	flush(device)
	larger := foster.TextureDownloadData(&scaled)
	defer delete(larger)
	assert(
		len(larger) == 1024 &&
		larger[(2 + 2 * 16) * 4 + 1] == 255 &&
		larger[(15 + 15 * 16) * 4 + 2] == 255,
	)
	fmt.println(
		"PASS: offscreen draw orientation, GPU readback, partial upload, clone and scaled blit",
	)

	stencil_target: foster.Target
	attachments := [2]foster.TargetAttachmentSpec{{Format = .Color}, {Format = .Depth24Stencil8}}
	foster.TargetInit(&stencil_target, device, 8, 8, attachments[:])
	defer foster.TargetDispose(&stencil_target)
	stencil_surface := foster.DrawableTargetFromTarget(&stencil_target)
	clear_colors := [1]foster.Color{foster.Black}
	foster.GraphicsDeviceClear(device, stencil_surface, clear_colors[:], 1, 0, .All)
	foster.BatcherClear(&batcher)
	batcher.Texture = &white
	// Write a stencil mask while suppressing color writes.
	batcher.Blend = foster.BlendModeDisabled
	batcher.Blend.Mask = {}
	foster.BatcherPushStencil(
		&batcher,
		foster.BatcherStencilMake(
			true,
			{FailOp = .Keep, PassOp = .Replace, DepthFailOp = .Keep, CompareOp = .Always},
			1,
		),
	)
	foster.BatcherRect(&batcher, {0, 0, 4, 8}, foster.White)
	foster.BatcherPopStencil(&batcher)
	batcher.Blend = foster.BlendModeDisabled
	foster.BatcherPushStencil(
		&batcher,
		foster.BatcherStencilMake(
			true,
			{FailOp = .Keep, PassOp = .Keep, DepthFailOp = .Keep, CompareOp = .Equal},
			1,
			255,
			0,
		),
	)
	foster.BatcherRect(&batcher, {0, 0, 8, 8}, foster.Color{0, 255, 0, 255})
	foster.BatcherPopStencil(&batcher)
	assert(foster.BatcherBatchCount(&batcher) == 2)
	foster.BatcherRender(&batcher, stencil_surface)
	flush(device)
	masked := foster.TextureDownloadData(foster.TargetAttachment(&stencil_target, 0))
	defer delete(masked)
	assert(len(masked) == 256)
	for y in 0 ..< 8 {
		for x in 0 ..< 8 {
			assert(masked[(x + y * 8) * 4 + 1] == (x < 4 ? 255 : 0))
		}
	}
	foster.GraphicsDeviceClear(device, stencil_surface, clear_colors[:], 1, 0, .All)
	command: foster.DrawCommand
	foster.DrawCommandFromMesh(
		&command,
		stencil_surface,
		&batcher.Mesh,
		batcher.Batches[1].Material,
	)
	defer foster.DrawCommandDispose(&command)
	command.IndexOffset = 6
	command.IndexCount = 6
	command.BlendMode = foster.BlendModeDisabled
	command.DepthTestEnabled = true
	command.DepthWriteEnabled = true
	command.DepthCompare = .Less
	foster.GraphicsDeviceDraw(device, &command)
	// Drawing the same geometry at the same depth with Less must fail.
	red_pixel := [1]foster.Color{{255, 0, 0, 255}}
	red: foster.Texture
	foster.TextureInit(&red, device, 1, 1)
	defer foster.TextureDispose(&red)
	foster.TextureSetData(&red, raw_data(red_pixel[:]), size_of(red_pixel))
	command.Material.Fragment.Samplers[0].Texture = &red
	foster.GraphicsDeviceDraw(device, &command)
	flush(device)
	depth_pixels := foster.TextureDownloadData(foster.TargetAttachment(&stencil_target, 0))
	defer delete(depth_pixels)
	assert(len(depth_pixels) == 256)
	for i in 0 ..< 64 {
		assert(depth_pixels[i * 4 + 1] == 255)
	}
	// Repeated disposal is safe and returns the Batcher's owned storage.
	foster.BatcherDispose(&batcher)
	foster.BatcherDispose(&batcher)
	assert(
		batcher.VertexShader.Resource == nil &&
		batcher.FragmentShader.Resource == nil &&
		len(batcher.Batches) == 0,
	)
	fmt.println(
		"PASS: stencil mask, color write mask, depth write/compare, Batcher state splitting and disposal",
	)
}

// [olib L-018] 单采样深度附件可当贴图采样：深度清成 0.25，再用 Batcher 把它画到另一张颜色目标，
// 读回的红通道约为 64。多采样深度没有解析纹理，判定为不可采样。
verify_depth_sampling :: proc(device: ^foster.GraphicsDevice, flush: proc(_: ^foster.GraphicsDevice)) {
	if !foster.GraphicsDeviceIsTextureFormatSupported(device, .Depth32) {
		fmt.println("SKIP: Depth32 sampling is not supported by this device")
		return
	}
	scene: foster.Target
	attachments := [2]foster.TargetAttachmentSpec{{Format = .Color}, {Format = .Depth32}}
	foster.TargetInit(&scene, device, 8, 8, attachments[:], "depth sampling")
	defer foster.TargetDispose(&scene)
	depth := foster.TargetAttachment(&scene, 1)
	assert(foster.TextureIsSampleable(depth) && foster.TextureIsSampleable(foster.TargetAttachment(&scene, 0)))
	colors := [1]foster.Color{foster.Black}
	scene_surface := foster.DrawableTargetFromTarget(&scene)
	foster.GraphicsDeviceClear(device, scene_surface, colors[:], f32(0.25), 0, foster.ClearMask.Color | .Depth)
	output: foster.Target
	foster.TargetInit(&output, device, 8, 8)
	defer foster.TargetDispose(&output)
	surface := foster.DrawableTargetFromTarget(&output)
	foster.GraphicsDeviceClear(device, surface, foster.Black)
	batcher: foster.Batcher
	foster.BatcherInit(&batcher, device)
	defer foster.BatcherDispose(&batcher)
	foster.BatcherImage(&batcher, depth, foster.White)
	foster.BatcherRender(&batcher, surface)
	flush(device)
	pixels := foster.TextureDownloadData(foster.TargetAttachment(&output, 0))
	defer delete(pixels)
	assert(len(pixels) == 256)
	for i in 0 ..< 64 {
		assert(abs(int(pixels[i * 4]) - 64) <= 2)
	}
	if foster.GraphicsDeviceIsTextureMultiSampleSupported(device, .Depth32, .Four) {
		msaa: foster.Target
		msaa_attachments := [2]foster.TargetAttachmentSpec{
			{Format = .Color, SampleCount = .Four},
			{Format = .Depth32, SampleCount = .Four},
		}
		foster.TargetInit(&msaa, device, 8, 8, msaa_attachments[:], "MSAA depth sampling")
		defer foster.TargetDispose(&msaa)
		assert(foster.TextureIsSampleable(foster.TargetAttachment(&msaa, 0)))
		assert(!foster.TextureIsSampleable(foster.TargetAttachment(&msaa, 1)))
	}
	fmt.println("PASS: single-sample depth attachment sampled as a texture; MSAA depth is not sampleable")
}

// [olib L-005] 真正创建多采样附件，并跨通道绘制后验证解析纹理；不只测能力查询。
verify_msaa_graphics :: proc(device: ^foster.GraphicsDevice, flush: proc(_: ^foster.GraphicsDevice)) {
	if !foster.GraphicsDeviceIsTextureMultiSampleSupported(device, .Color, .Four) ||
	   !foster.GraphicsDeviceIsTextureMultiSampleSupported(device, .Depth32, .Four) {
		fmt.println("SKIP: 4x MSAA is not supported by this device")
		return
	}
	target: foster.Target
	attachments := [2]foster.TargetAttachmentSpec{
		{Format = .Color, SampleCount = .Four},
		{Format = .Depth32, SampleCount = .Four},
	}
	foster.TargetInit(&target, device, 16, 16, attachments[:], "MSAA regression")
	defer foster.TargetDispose(&target)
	assert(foster.TargetAttachment(&target).ResolveResource != nil)
	surface := foster.DrawableTargetFromTarget(&target)
	colors := [1]foster.Color{foster.Black}
	// [olib L-006] Depth32 无模板；只清颜色/深度也必须通过 SDL cycle 验证。
	foster.GraphicsDeviceClear(device, surface, colors[:], 1, 0, .Color | .Depth)
	batcher: foster.Batcher
	foster.BatcherInit(&batcher, device)
	defer foster.BatcherDispose(&batcher)
	white: foster.Texture
	foster.TextureInit(&white, device, 1, 1)
	defer foster.TextureDispose(&white)
	pixel := [1]foster.Color{foster.White}
	foster.TextureSetData(&white, raw_data(pixel[:]), size_of(pixel))
	batcher.Texture = &white
	foster.BatcherRect(&batcher, {0, 0, 16, 8}, foster.Color{255, 0, 0, 255})
	foster.BatcherRender(&batcher, surface)
	// [olib L-008] 通道活跃时再次上传，必须仍录入当前命令缓冲并保留红色区域。
	command_buffer := device.CommandBuffer
	staging_cursor := device.UploadStagingCursor
	assert(device.RenderPass != nil)
	foster.BatcherClear(&batcher)
	batcher.Texture = &white
	foster.BatcherRect(&batcher, {0, 8, 16, 8}, foster.Color{0, 255, 0, 255})
	foster.BatcherRender(&batcher, surface)
	assert(device.CommandBuffer == command_buffer)
	when ODIN_OS != .JS {
		assert(device.UploadStaging != nil && device.UploadStagingCursor > staging_cursor)
	}
	flush(device)
	pixels := foster.TextureDownloadData(foster.TargetAttachment(&target))
	defer delete(pixels)
	assert(len(pixels) == 16*16*4)
	for y in 0..<16 {
		for x in 0..<16 {
			i := (x+y*16)*4
			assert(pixels[i] == (y < 8 ? 255 : 0))
			assert(pixels[i+1] == (y < 8 ? 0 : 255))
			assert(pixels[i+3] == 255)
		}
	}
	foster.GraphicsDeviceClear(device, surface, colors[:], 1, 0, .Color | .Depth)
	foster.BatcherClear(&batcher)
	batcher.Texture = &white
	foster.BatcherTriangle(&batcher, {1, 1}, {15, 1}, {1, 15}, foster.White)
	foster.BatcherRender(&batcher, surface)
	flush(device)
	edge_pixels := foster.TextureDownloadData(foster.TargetAttachment(&target))
	defer delete(edge_pixels)
	partial := 0
	for i in 0..<16*16 {
		if edge_pixels[i*4] > 0 && edge_pixels[i*4] < 255 {
			partial += 1
		}
	}
	assert(partial > 0, "4x MSAA must produce partial edge coverage")
	fmt.println("PASS: 4x MSAA attachments, cross-pass preservation, resolve readback and edge coverage")
}
