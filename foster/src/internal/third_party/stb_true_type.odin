package foster_third_party

import "core:c"
import stb "vendor:stb/truetype"

// 文件内导航
//   Internal / ThirdParty / StbTrueType / Font — 字体数据与初始化
//   Internal / ThirdParty / StbTrueType / Metrics — 度量与字形
//   Internal / ThirdParty / StbTrueType / Rasterize — 光栅化

// ==============================================================================
// Internal / ThirdParty / StbTrueType / Font — 字体数据与初始化
// ==============================================================================

StbFont :: struct {
	Info:  stb.fontinfo,
	Data:  [dynamic]u8,
	Valid: bool,
}

StbFontInit :: proc(data: []u8) -> StbFont {
	f := StbFont{}
	for b in data {
		append(&f.Data, b)
	}
	if len(f.Data) == 0 {
		return f
	}
	offset := stb.GetFontOffsetForIndex(&f.Data[0], 0)
	if offset < 0 {
		offset = 0
	}
	result := stb.InitFont(&f.Info, &f.Data[0], offset)
	f.Valid = bool(result)
	return f
}

// ==============================================================================
// Internal / ThirdParty / StbTrueType / Metrics — 度量与字形
// ==============================================================================

StbFontScale :: proc(f: ^StbFont, size: f32) -> f32 {
	if !f.Valid {
		return 0
	}
	return stb.ScaleForMappingEmToPixels(&f.Info, size)
}

StbFontMetrics :: proc(f: ^StbFont) -> (int, int, int) {
	if !f.Valid {
		return 0, 0, 0
	}
	a, d, g: c.int = 0, 0, 0
	stb.GetFontVMetrics(&f.Info, &a, &d, &g)
	return int(a), int(d), int(g)
}

StbFontGlyph :: proc(f: ^StbFont, codepoint: int) -> int {
	if !f.Valid {
		return 0
	}
	return int(stb.FindGlyphIndex(&f.Info, rune(codepoint)))
}

StbFontKerning :: proc(f: ^StbFont, a, b: int, scale: f32) -> f32 {
	if !f.Valid {
		return 0
	}
	return f32(stb.GetGlyphKernAdvance(&f.Info, c.int(a), c.int(b))) * scale
}

StbFontCharacter :: proc(
	f: ^StbFont,
	glyph: int,
	scale: f32,
) -> (
	width, height: int,
	advance, offset_x, offset_y: f32,
	visible: bool,
) {
	if !f.Valid {
		return
	}
	aw, lsb: c.int = 0, 0
	stb.GetGlyphHMetrics(&f.Info, c.int(glyph), &aw, &lsb)
	x0, y0, x1, y1: c.int = 0, 0, 0, 0
	stb.GetGlyphBitmapBox(&f.Info, c.int(glyph), scale, scale, &x0, &y0, &x1, &y1)
	return int(x1 - x0), int(y1 - y0), f32(aw) * scale, f32(x0), f32(y0), x1 > x0 && y1 > y0
}

// ==============================================================================
// Internal / ThirdParty / StbTrueType / Rasterize — 光栅化
// ==============================================================================

StbFontRasterize :: proc(f: ^StbFont, glyph, width, height: int, scale: f32) -> [dynamic]u8 {
	pixels: [dynamic]u8 = {}
	if !f.Valid || width <= 0 || height <= 0 {
		return pixels
	}
	resize(&pixels, width * height)
	stb.MakeGlyphBitmap(
		&f.Info,
		&pixels[0],
		c.int(width),
		c.int(height),
		c.int(width),
		scale,
		scale,
		c.int(glyph),
	)
	return pixels
}

StbTrueTypeAvailable :: proc() -> bool {
	return size_of(stb.fontinfo) > 0
}
