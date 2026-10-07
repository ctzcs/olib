package main

import "core:fmt"
import "core:mem"
import foster "olib:foster"

font_data :: #load("fonts/Abel-Regular.ttf")

verify_font_memory :: proc() {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	{
		context.allocator = mem.tracking_allocator(&tracker)
		font := foster.FontMake(font_data)
		assert(font.Backend.Valid)
		scale := foster.FontGetScale(&font, 20)
		character := foster.FontGetCharacter(&font, 'A', scale)
		assert(character.Visible)
		assert(
			foster.FontGetKerning(&font, 'A', 'V', scale) ==
			foster.FontGetKerningBetweenGlyphs(
				&font,
				foster.FontGetGlyphIndex(&font, 'A'),
				foster.FontGetGlyphIndex(&font, 'V'),
				scale,
			),
		)
		image := foster.FontGetImage(&font, character)
		for pixel in image.Pixels {
			assert(pixel.R == pixel.A && pixel.G == pixel.A && pixel.B == pixel.A)
		}
		foster.ImageDispose(&image)
		image = foster.FontGetImage(&font, character, false)
		for pixel in image.Pixels {
			assert(pixel.R == 255 && pixel.G == 255 && pixel.B == 255)
		}
		foster.ImageDispose(&image)
		packer := foster.PackerMake()
		packer.MaxSize = 8
		image = foster.ImageMake(4, 4)
		for &pixel in image.Pixels {
			pixel = foster.White
		}
		for i in 0 ..< 3 {
			foster.PackerAdd(&packer, "glyph", image)
		}
		foster.ImageDispose(&image)
		output := foster.PackerPack(&packer)
		assert(len(output.Pages) >= 2 && len(output.Entries) == 3)
		foster.PackerOutputDispose(&output)
		foster.PackerDispose(&packer)
		foster.PackerDispose(&packer)
		cpu := foster.SpriteFontMake(&font, 20, {'A', 'V'})
		foster.SpriteFontDispose(&cpu)
		foster.FontDispose(&font)
		foster.FontDispose(&font)
		ase_data := #load("linked.aseprite")
		input_bytes := make([]u8, len(ase_data))
		copy(input_bytes, ase_data)
		aseprite := foster.AsepriteLoad(input_bytes)
		delete(input_bytes)
		assert(len(aseprite.Frames) == 2 && aseprite.Layers[0].Name == "图层")
		assert(len(aseprite.Frames[1].Cels[0].Image.Pixels) == 1)
		assert(aseprite.Frames[1].Cels[0].Image.Pixels[0] == foster.Color{255, 32, 0, 255})
		rendered := foster.AsepriteRenderFramesSlice(&aseprite, 0, 1, {0, 0, 1, 1})
		assert(len(rendered) == 2)
		for &frame in rendered {
			assert(frame.Pixels[0] == foster.Color{255, 32, 0, 255})
			foster.ImageDispose(&frame)
		}
		delete(rendered)
		foster.AsepriteDispose(&aseprite)
		foster.AsepriteDispose(&aseprite)
		atlas := foster.ImageMake(2, 2, foster.White)
		msdf := foster.MsdfFontMake(
			atlas,
			transmute([]u8)string(
				`{"atlas":{"size":16,"distanceRange":4},"metrics":{"ascender":0.8,"descender":-0.2,"lineHeight":1.2},"glyphs":[{"unicode":65,"advance":0.5}],"kerning":[]}`,
			),
		)
		assert(msdf.Size == 16 && len(msdf.Characters) == 1)
		foster.MsdfFontDispose(&msdf)
		assert(len(atlas.Pixels) == 4)
		storage := foster.StorageContainer {
			Root     = "build",
			Writable = true,
		}
		assert(foster.ImageWritePNG(&atlas, "build/port-regression-image.png"))
		png := foster.ReadAllBytes(&storage, "port-regression-image.png")
		assert(len(png) > 8 && png[0] == 137 && png[1] == 'P')
		decoded := foster.ImageFromEncoded(png)
		assert(decoded.Width == 2 && decoded.Height == 2 && decoded.Pixels[0] == foster.White)
		foster.ImageDispose(&decoded)
		delete(png)
		assert(foster.Remove(&storage, "port-regression-image.png"))
		foster.ImageDispose(&atlas)

		request := new(foster.DialogRequest)
		request.Allocator = context.allocator
		request.Filters = foster.storage_dialog_filters({{"图片", "*.png;*.qoi"}})
		assert(string(request.Filters[0].name) == "图片")
		foster.storage_dialog_dispose(request)
		provider := foster.InputProviderMake()
		foster.InputProviderText(&provider, "中文😀")
		foster.InputProviderUpdate(&provider, {})
		foster.InputProviderUpdate(&provider, {})
		foster.InputProviderDispose(&provider)
	}
	assert(tracker.current_memory_allocated == 0)
	assert(len(tracker.bad_free_array) == 0)
	fmt.println(
		"PASS: real font rasterization, premultiplication, glyph kerning, multi-page packing, Aseprite linked cels, PNG, MSDF and zero outstanding owned allocations",
	)
}

verify_font_graphics :: proc(
	device: ^foster.GraphicsDevice,
	flush: proc(_: ^foster.GraphicsDevice),
) {
	font := foster.FontMake(font_data)
	defer foster.FontDispose(&font)
	sprite := foster.SpriteFontMakeGPU(device, &font, 20, {'A', 'V'})
	defer foster.SpriteFontDispose(&sprite)
	first := foster.SpriteFontGetCharacter(&sprite, 'A')
	assert(first.Subtexture.Texture != nil)
	initial_pages := len(sprite.GeneratedTextures)
	foster.SpriteFontAddCharacters(&sprite, &font, {'B', ' '}, pixel_perfect = true)
	assert(
		foster.SpriteFontGetCharacter(&sprite, 'A').Subtexture.Texture == first.Subtexture.Texture,
	)
	added := foster.SpriteFontGetCharacter(&sprite, 'B')
	assert(added.Subtexture.Texture != nil && len(sprite.GeneratedTextures) > initial_pages)
	assert(foster.SpriteFontGetCharacter(&sprite, ' ').Exists)
	flush(device)
	pixels := foster.TextureDownloadData(added.Subtexture.Texture)
	defer delete(pixels)
	assert(len(pixels) > 0)
	visible := false
	for i := 0; i < len(pixels); i += 4 {
		assert(pixels[i + 3] == 0 || pixels[i + 3] == 255)
		assert(
			pixels[i] == pixels[i + 3] &&
			pixels[i + 1] == pixels[i + 3] &&
			pixels[i + 2] == pixels[i + 3],
		)
		visible ||= pixels[i + 3] == 255
	}
	assert(visible)
	fmt.println(
		"PASS: incremental GPU font atlas preserves old glyphs and produces pixel-perfect glyphs",
	)
}
