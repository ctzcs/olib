package main

import "core:fmt"
import "core:mem"
import foster "olib:foster"

verify_graphics :: proc(device: ^foster.GraphicsDevice, flush: proc(_: ^foster.GraphicsDevice)) {
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
