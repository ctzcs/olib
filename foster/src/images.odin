package foster_framework

import qoi "./internal/third_party"
import "core:c"
import "core:strings"
import stbi "vendor:stb/image"
import "core:bytes"
import "core:math"
import zlib "core:compress/zlib"
import json "core:encoding/json"
import stb "./internal/third_party"
import "core:mem"
import "core:unicode/utf8"

// 文件内导航（按 Foster 目录 / 类型分级）
//   Images / Image — 图像加载、写入与像素操作
//   Images / Packer — 图集打包
//   Images / Aseprite — Aseprite 文件解析
//   Images / MsdfFont — MSDF 字体
//   Images / Font — 字体字形与度量
//   Graphics / Texture — 从图像创建纹理
//   Graphics / SpriteFont — 字体烘焙、排版与绘制

// ==============================================================================
// Images / Image — 图像加载、写入与像素操作
// ==============================================================================

Image :: struct {
	Width, Height: int,
	Pixels:        [dynamic]Color,
	IsDisposed:    bool,
}

ImageMake :: proc(width, height: int, fill := Transparent) -> Image {
	i := Image {
		Width  = width,
		Height = height,
	}
	resize(&i.Pixels, width * height)
	for n in 0 ..< len(i.Pixels) {
		i.Pixels[n] = fill
	}
	return i
}

ImageFromPixels :: proc(width, height: int, pixels: []Color) -> Image {
	i := Image {
		Width  = width,
		Height = height,
	}
	for p in pixels {
		append(&i.Pixels, p)
	}
	return i
}

ImageFromQoi :: proc(data: []u8) -> Image {
	desc: qoi.QoiDesc = {}
	bytes := qoi.QoiDecode(data, 4, &desc)
	defer delete(bytes)
	if len(bytes) == 0 {
		return {}
	}
	i := Image {
		Width  = int(desc.Width),
		Height = int(desc.Height),
	}
	resize(&i.Pixels, int(desc.Width * desc.Height))
	for n in 0 ..< len(i.Pixels) {
		i.Pixels[n] = Color{bytes[n * 4], bytes[n * 4 + 1], bytes[n * 4 + 2], bytes[n * 4 + 3]}
	}
	return i
}

ImageToQoi :: proc(i: ^Image) -> [dynamic]u8 {
	bytes: [dynamic]u8 = {}
	defer delete(bytes)
	resize(&bytes, len(i.Pixels) * 4)
	for n in 0 ..< len(i.Pixels) {
		c := i.Pixels[n]
		bytes[n * 4] = c.R
		bytes[n * 4 + 1] = c.G
		bytes[n * 4 + 2] = c.B
		bytes[n * 4 + 3] = c.A
	}
	return qoi.QoiEncode(bytes[:], u32(i.Width), u32(i.Height), 4)
}

ImageFromEncoded :: proc(data: []u8) -> Image {
	if qoi.QoiIsFormat(data) {
		return ImageFromQoi(data)
	}
	if len(data) == 0 {
		return {}
	}
	w, h, components: c.int = 0, 0, 0
	ptr := stbi.load_from_memory(&data[0], c.int(len(data)), &w, &h, &components, 4)
	if ptr == nil || w <= 0 || h <= 0 {
		return {}
	}
	result := ImageMake(int(w), int(h))
	total := int(w * h * 4)
	for n in 0 ..< total {
		byte_index := n
		pixel := n / 4
		channel := n % 4
		switch channel {
		case 0:
			result.Pixels[pixel].R = ptr[byte_index]
		case 1:
			result.Pixels[pixel].G = ptr[byte_index]
		case 2:
			result.Pixels[pixel].B = ptr[byte_index]
		case 3:
			result.Pixels[pixel].A = ptr[byte_index]
		}
	}
	stbi.image_free(ptr)
	return result
}

ImageLoadFile :: proc(path: string) -> Image {
	data := storage_os_read_file(path, context.temp_allocator)
	if data == nil {
		return {}
	}
	return ImageFromEncoded(data)
}

ImageWritePng :: proc(i: ^Image, path: string) -> bool {
	if i.Width <= 0 || i.Height <= 0 || len(i.Pixels) == 0 {
		return false
	}
	when ODIN_OS == .JS {
		return fw_image_write_png(
			raw_data(path),
			i32(len(path)),
			i32(i.Width),
			i32(i.Height),
			raw_data(i.Pixels),
		)
	} else {
		cstr, _ := strings.clone_to_cstring(path, context.temp_allocator)
		return(
			stbi.write_png(
				cstr,
				c.int(i.Width),
				c.int(i.Height),
				4,
				raw_data(i.Pixels),
				c.int(i.Width * 4),
			) !=
			0 \
		)
	}
}

ImageWriteQoi :: proc(i: ^Image, path: string) -> bool {
	data := ImageToQoi(i)
	defer delete(data)
	if len(data) == 0 {
		return false
	}
	return storage_os_write_file(path, data[:])
}
ImageLoad :: ImageLoadFile
ImageWritePNG :: ImageWritePng

ImagePixelCount :: proc(i: ^Image) -> int {
	return i.Width * i.Height
}

ImageBounds :: proc(i: ^Image) -> RectInt {
	return RectInt{0, 0, i.Width, i.Height}
}

ImageWidth :: proc(i: ^Image) -> int {
	return i.Width
}

ImageHeight :: proc(i: ^Image) -> int {
	return i.Height
}

ImageGetPixel :: proc(i: ^Image, x, y: int) -> Color {
	if x < 0 || y < 0 || x >= i.Width || y >= i.Height {
		return Transparent
	}
	return i.Pixels[x + y * i.Width]
}

ImageGetPixelIndex :: proc(i: ^Image, index: int) -> Color {
	if i == nil || index < 0 || index >= len(i.Pixels) {
		return Transparent
	}
	return i.Pixels[index]
}

ImageSetPixel :: proc(i: ^Image, x, y: int, c: Color) {
	if x >= 0 && y >= 0 && x < i.Width && y < i.Height {
		i.Pixels[x + y * i.Width] = c
	}
}

ImageSetPixelIndex :: proc(i: ^Image, index: int, c: Color) {
	if i != nil && index >= 0 && index < len(i.Pixels) {
		i.Pixels[index] = c
	}
}

ImageData :: proc(i: ^Image) -> []Color {
	return i.Pixels[:]
}

ImageSize :: proc(i: ^Image) -> Point2 {
	if i == nil {
		return {}
	}
	return Point2{i.Width, i.Height}
}

// Clear 保留可复用的像素容量；Dispose 释放像素内存，可重复调用。

ImageDispose :: proc(image: ^Image) {
	if image == nil {
		return
	}
	delete(image.Pixels)
	image^ = Image {
		IsDisposed = true,
	}
}

ImageClear :: proc(i: ^Image) {
	clear(&i.Pixels)
	i.Width = 0
	i.Height = 0
	i.IsDisposed = true
}

ImageCopyPixels :: proc(
	dst: ^Image,
	src: ^Image,
	source_rect := RectInt{0, 0, 0, 0},
	destination := Point2{},
) {
	r := source_rect
	if r.Width == 0 {
		r = ImageBounds(src)
	}
	for y in 0 ..< r.Height {
		for x in 0 ..< r.Width {
			ImageSetPixel(
				dst,
				destination.X + x,
				destination.Y + y,
				ImageGetPixel(src, r.X + x, r.Y + y),
			)
		}
	}
}

ImageCopyPixelsBlend :: proc(
	dst: ^Image,
	src: ^Image,
	source_rect: RectInt,
	destination: Point2,
	blend: proc(a, b: Color) -> Color = nil,
) {
	r := source_rect
	if r.Width == 0 {
		r = ImageBounds(src)
	}
	for y in 0 ..< r.Height {
		for x in 0 ..< r.Width {
			c := ImageGetPixel(src, r.X + x, r.Y + y)
			if blend != nil {
				c = blend(ImageGetPixel(dst, destination.X + x, destination.Y + y), c)
			}
			ImageSetPixel(dst, destination.X + x, destination.Y + y, c)
		}
	}
}

ImagePremultiply :: proc(i: ^Image) {
	if i == nil {
		return
	}
	for n in 0 ..< len(i.Pixels) {
		i.Pixels[n] = Premultiply(i.Pixels[n])
	}
}

// ==============================================================================
// Images / Packer — 图集打包
// ==============================================================================

PackerEntry :: struct {
	Index:  int,
	Name:   string,
	Page:   int,
	Source: RectInt,
	Frame:  RectInt,
}

PackerOutput :: struct {
	Pages:   [dynamic]Image,
	Entries: [dynamic]PackerEntry,
}

PackerSource :: struct {
	Index:       int,
	Name:        string,
	Image:       Image,
	Frame:       RectInt,
	DuplicateOf: int,
	OwnsImage:   bool,
}

Packer :: struct {
	Trim:              bool,
	MaxSize:           int,
	Padding:           int,
	PowerOfTwo:        bool,
	DuplicateEdges:    bool,
	CombineDuplicates: bool,
	Sources:           [dynamic]PackerSource,
}

PackerMake :: proc() -> Packer {
	return Packer{Trim = true, MaxSize = 8192, Padding = 1}
}

packer_alpha :: proc(i: ^Image, x, y: int) -> u8 {
	return ImageGetPixel(i, x, y).A
}

packer_same :: proc(a, b: Image) -> bool {
	if a.Width != b.Width || a.Height != b.Height {
		return false
	}
	for n in 0 ..< len(a.Pixels) {
		if a.Pixels[n] != b.Pixels[n] {
			return false
		}
	}
	return true
}

PackerAdd :: proc(p: ^Packer, name: string, image: Image) -> int {
	idx := len(p.Sources)
	source := image
	source_ref := image
	frame := RectInt{0, 0, image.Width, image.Height}
	if p.Trim && image.Width > 0 && image.Height > 0 {
		left, right, top, bottom := image.Width, 0, image.Height, 0
		for y in 0 ..< image.Height {
			for x in 0 ..< image.Width {
				if packer_alpha(&source_ref, x, y) > 0 {
					if x < left {
						left = x
					}
					if x >= right {
						right = x + 1
					}
					if y < top {
						top = y
					}
					if y >= bottom {
						bottom = y + 1
					}
				}
			}
		}
		if right > left && bottom > top {
			frame = RectInt{-left, -top, image.Width, image.Height}
			source = ImageMake(right - left, bottom - top)
			ImageCopyPixels(
				&source,
				&source_ref,
				RectInt{left, top, right - left, bottom - top},
				Point2{},
			)
		} else {
			source = ImageMake(0, 0)
		}
	}
	dup := -1
	if p.CombineDuplicates && source.Width > 0 {
		for old in p.Sources {
			if old.DuplicateOf < 0 && packer_same(old.Image, source) {
				dup = old.Index
				break
			}
		}
	}
	append(&p.Sources, PackerSource {
		Index       = idx,
		Name        = name,
		Image       = source,
		Frame       = frame,
		DuplicateOf = dup,
		OwnsImage   = p.Trim && image.Width > 0 && image.Height > 0,
	})
	return idx
}
PackerAddImage :: PackerAdd

PackerClear :: proc(p: ^Packer) {
	for &source in p.Sources {
		if source.OwnsImage {
			ImageDispose(&source.Image)
		}
	}
	clear(&p.Sources)
}

PackerDispose :: proc(p: ^Packer) {
	PackerClear(p)
	delete(p.Sources)
	p.Sources = nil
}

PackerOutputDispose :: proc(output: ^PackerOutput) {
	for &page in output.Pages {
		ImageDispose(&page)
	}
	delete(output.Pages)
	delete(output.Entries)
	output^ = {}
}

packer_next_pow2 :: proc(v: int) -> int {
	n := 1
	for n < v {
		n *= 2
	}
	return n
}

packer_flush :: proc(p: ^Packer, out: ^PackerOutput, page: ^Image, used_w, used_h: int) {
	if used_w <= 0 || used_h <= 0 {
		return
	}
	w, h := used_w, used_h
	if p.PowerOfTwo {
		w = packer_next_pow2(w)
		h = packer_next_pow2(h)
	}
	if w > p.MaxSize {
		w = p.MaxSize
	}
	if h > p.MaxSize {
		h = p.MaxSize
	}
	cropped := ImageMake(w, h)
	ImageCopyPixels(&cropped, page, RectInt{0, 0, w, h}, Point2{})
	append(&out.Pages, cropped)
}

PackerPack :: proc(p: ^Packer) -> PackerOutput {
	out := PackerOutput{}
	if p == nil || len(p.Sources) == 0 {
		return out
	}
	max_size := p.MaxSize
	if max_size <= 0 {
		return out
	}
	padding := p.Padding
	if padding < 0 {
		padding = 0
	}
	page := ImageMake(max_size, max_size)
	defer ImageDispose(&page)
	x, y, row, used_w, used_h := 0, 0, 0, 0, 0
	order: [dynamic]int = {}
	defer delete(order)
	for i in 0 ..< len(p.Sources) {
		area := p.Sources[i].Image.Width * p.Sources[i].Image.Height
		at := len(order)
		for j in 0 ..< len(order) {
			other := p.Sources[order[j]].Image.Width * p.Sources[order[j]].Image.Height
			if other < area {
				at = j
				break
			}
		}
		append(&order, 0)
		for j := len(order) - 1; j > at; j -= 1 {
			order[j] = order[j - 1]
		}
		order[at] = i
	}
	for oi in order {
		s := p.Sources[oi]
		if s.DuplicateOf >= 0 || s.Image.Width <= 0 || s.Image.Height <= 0 {
			continue
		}
		w, h := s.Image.Width, s.Image.Height
		if w + padding > max_size || h + padding > max_size {
			continue
		}
		if x + w + padding > max_size {
			x = 0
			y += row + padding
			row = 0
		}
		if y + h + padding > max_size {
			packer_flush(p, &out, &page, used_w, used_h)
			ImageDispose(&page)
			page = ImageMake(max_size, max_size)
			x, y, row, used_w, used_h = 0, 0, 0, 0, 0
		}
		pos := RectInt{x + padding / 2, y + padding / 2, w, h}
		src := s.Image
		ImageCopyPixels(&page, &src, RectInt{0, 0, w, h}, Point2{pos.X, pos.Y})
		if p.DuplicateEdges && padding >= 2 {
			for yy in 0 ..< h {
				ImageSetPixel(
					&page,
					pos.X - 1,
					pos.Y + yy,
					ImageGetPixel(&page, pos.X, pos.Y + yy),
				)
				ImageSetPixel(
					&page,
					pos.X + w,
					pos.Y + yy,
					ImageGetPixel(&page, pos.X + w - 1, pos.Y + yy),
				)
			}
			for xx in -1 ..< (w + 1) {
				ImageSetPixel(
					&page,
					pos.X + xx,
					pos.Y - 1,
					ImageGetPixel(&page, pos.X + xx, pos.Y),
				)
				ImageSetPixel(
					&page,
					pos.X + xx,
					pos.Y + h,
					ImageGetPixel(&page, pos.X + xx, pos.Y + h - 1),
				)
			}
		}
		append(&out.Entries, PackerEntry{s.Index, s.Name, len(out.Pages), pos, s.Frame})
		x += w + padding
		if h > row {
			row = h
		}
		if pos.X + w > used_w {
			used_w = pos.X + w
		}
		if pos.Y + h > used_h {
			used_h = pos.Y + h
		}
	}
	packer_flush(p, &out, &page, used_w, used_h)
	for s in p.Sources {
		if s.DuplicateOf >= 0 {
			for e in out.Entries {
				if e.Index == s.DuplicateOf {
					append(&out.Entries, PackerEntry{s.Index, s.Name, e.Page, e.Source, s.Frame})
					break
				}
			}
		} else if s.Image.Width <= 0 || s.Image.Height <= 0 {
			append(&out.Entries, PackerEntry{s.Index, s.Name, 0, RectInt{}, s.Frame})
		}
	}
	return out
}

// ==============================================================================
// Images / Aseprite — Aseprite 文件解析
// ==============================================================================
// core:os 经根包 storage_os_* 平台层使用(js 目标无 core:os)

// ------------------------------------------------------------------------------
// Images / Aseprite / Types — 枚举、图层与动画数据
// ------------------------------------------------------------------------------

AsepriteBlendMode :: enum {
	Normal,
	Multiply,
	Screen,
	Overlay,
	Darken,
	Lighten,
	ColorDodge,
	ColorBurn,
	HardLight,
	SoftLight,
	Difference,
	Exclusion,
	Hue,
	Saturation,
	Color,
	Luminosity,
	Addition,
	Subtract,
	Divide,
}

AsepriteLayerType :: enum {
	Normal,
	Group,
	Tilemap,
}

AsepriteLoopDir :: enum {
	Forward,
	Reverse,
	PingPong,
	PingPongReverse,
}

AsepriteLayerFlag :: enum u8 {
	Visible,
	Editable,
	LockMovement,
	Background,
	PreferLinkedCels,
	DisplayCollapsed,
	Reference,
}
AsepriteLayerFlags :: bit_set[AsepriteLayerFlag;u8]

AsepriteFormat :: enum {
	Indexed   = 8,
	Grayscale = 16,
	RGBA      = 32,
}

AsepriteCelType :: enum {
	RawImageData,
	LinkedCel,
	CompressedImage,
	CompressedTilemap,
}

AsepriteUserDataValues :: struct {
	Text:  string,
	Color: Color,
}

AsepriteLayer :: struct {
	Name:         string,
	Type:         AsepriteLayerType,
	Flags:        AsepriteLayerFlags,
	ChildLevel:   int,
	DefaultSize:  Point2,
	BlendMode:    AsepriteBlendMode,
	Opacity:      u8,
	TilesetIndex: int,
	UserData:     AsepriteUserDataValues,
}

AsepriteCel :: struct {
	Frame, Layer:             int,
	Position:                 Point2,
	Opacity:                  u8,
	ZIndex:                   int,
	Image:                    Image,
	Type:                     AsepriteCelType,
	LinkedFrame, LinkedLayer: int,
	UserData:                 AsepriteUserDataValues,
}

AsepriteFrame :: struct {
	Duration: f32,
	Cels:     [dynamic]AsepriteCel,
	UserData: AsepriteUserDataValues,
}

AsepriteTag :: struct {
	Name:      string,
	From, To:  int,
	Direction: AsepriteLoopDir,
	Repeat:    int,
	UserData:  AsepriteUserDataValues,
}

AsepriteSliceKey :: struct {
	FrameStart:     int,
	Bounds:         RectInt,
	NinSliceCenter: RectInt,
	HasNineSlice:   bool,
	Pivot:          Point2,
	HasPivot:       bool,
}

AsepriteSlice :: struct {
	Name:     string,
	Keys:     [dynamic]AsepriteSliceKey,
	UserData: AsepriteUserDataValues,
}

Aseprite :: struct {
	SourceData:    []u8, // 拥有字符串字段的底层数据，Load 完成后原始输入可释放。
	Width, Height: int,
	Format:        AsepriteFormat,
	Frames:        [dynamic]AsepriteFrame,
	Layers:        [dynamic]AsepriteLayer,
	Tags:          [dynamic]AsepriteTag,
	Slices:        [dynamic]AsepriteSlice,
	Palette:       [dynamic]Color,
	UserData:      AsepriteUserDataValues,
}

ase_u16 :: proc(data: []u8, at: ^int) -> u16 {
	v := u16(data[at^]) | u16(data[at^ + 1]) << 8
	at^ += 2
	return v
}

ase_s16 :: proc(data: []u8, at: ^int) -> i16 {
	return i16(ase_u16(data, at))
}

ase_u32 :: proc(data: []u8, at: ^int) -> u32 {
	v :=
		u32(data[at^]) |
		u32(data[at^ + 1]) << 8 |
		u32(data[at^ + 2]) << 16 |
		u32(data[at^ + 3]) << 24
	at^ += 4
	return v
}

ase_s32 :: proc(data: []u8, at: ^int) -> i32 {
	return i32(ase_u32(data, at))
}

ase_string :: proc(data: []u8, at: ^int) -> string {
	n := int(ase_u16(data, at))
	if n <= 0 || at^ + n > len(data) {
		return ""
	}
	s := string(data[at^:at^ + n])
	at^ += n
	return s
}

ase_pixels :: proc(
	raw: []u8,
	format: AsepriteFormat,
	width, height: int,
	palette: []Color,
) -> Image {
	img := ImageMake(width, height)
	for n in 0 ..< (width * height) {
		switch format {
		case .RGBA:
			if n * 4 + 3 < len(raw) {
				img.Pixels[n] = Color{raw[n * 4], raw[n * 4 + 1], raw[n * 4 + 2], raw[n * 4 + 3]}
			}
		case .Grayscale:
			if n * 2 + 1 < len(raw) {
				img.Pixels[n] = Color{raw[n * 2], raw[n * 2], raw[n * 2], raw[n * 2 + 1]}
			}
		case .Indexed:
			if int(raw[n]) < len(palette) {
				img.Pixels[n] = palette[int(raw[n])]
			}
		}
	}
	return img
}

// ------------------------------------------------------------------------------
// Images / Aseprite / Decoder — 块解析与解码
// ------------------------------------------------------------------------------

AsepriteLoad :: proc(data: []u8) -> Aseprite {
	a := Aseprite{}
	if len(data) < 128 {
		return a
	}
	at := 0
	_ = ase_u32(data, &at)
	if ase_u16(data, &at) != 0xA5E0 {
		return a
	}
	a.SourceData = make([]u8, len(data))
	copy(a.SourceData, data)
	data := a.SourceData
	frame_count := int(ase_u16(data, &at))
	a.Width = int(ase_u16(data, &at))
	a.Height = int(ase_u16(data, &at))
	a.Format = AsepriteFormat(ase_u16(data, &at))
	_ = ase_u32(data, &at)
	_ = ase_u16(data, &at)
	at += 8
	at += 1
	at += 3
	_ = ase_u16(data, &at)
	at += 2
	_ = ase_u16(data, &at)
	_ = ase_u16(data, &at)
	_ = ase_u16(data, &at)
	_ = ase_u16(data, &at)
	at += 84
	for fi in 0 ..< frame_count {
		if at + 16 > len(data) {
			break
		}
		start := at
		frame_size := int(ase_u32(data, &at))
		_ = ase_u16(data, &at)
		old_count := int(ase_u16(data, &at))
		duration := ase_u16(data, &at)
		at += 2
		new_count := int(ase_u32(data, &at))
		chunk_count := new_count
		if chunk_count == 0 {
			chunk_count = old_count
		}
		end := min(start + frame_size, len(data))
		frame := AsepriteFrame {
			Duration = f32(duration),
		}
		last_userdata_kind, last_userdata_index := 0, -1
		for _ in 0 ..< chunk_count {
			if at + 6 > end {
				break
			}
			chunk_start := at
			size := int(ase_u32(data, &at))
			typ := ase_u16(data, &at)
			chunk_end := min(chunk_start + size, end)
			switch typ {
			case 0x2019:
				if at + 20 <= chunk_end {
					total := int(ase_u32(data, &at))
					first := int(ase_u32(data, &at))
					last := int(ase_u32(data, &at))
					at += 8
					if total > 0 && last >= first {
						needed := last + 1
						if len(a.Palette) < needed {
							resize(&a.Palette, needed)
						}
						for pi := first; pi <= last; pi += 1 {
							if at + 6 > chunk_end {
								break
							}
							flags := ase_u16(data, &at)
							r, g, b, alpha := data[at], data[at + 1], data[at + 2], data[at + 3]
							at += 4
							a.Palette[pi] = Color{r, g, b, alpha}
							if flags & 1 != 0 && at + 2 <= chunk_end {
								_ = ase_string(data, &at)
							}
						}
					}
				}
			case 0x0004, 0x0011:
				if len(a.Palette) == 0 && at + 2 <= chunk_end {
					count := int(ase_u16(data, &at))
					if count <= 0 {
						count = 256
					}
					base := 0
					if typ == 0x0011 && at + 2 <= chunk_end {
						base = int(ase_u16(data, &at))
						_ = ase_u16(data, &at)
					}
					if len(a.Palette) < base + count {
						resize(&a.Palette, base + count)
					}
					for pi := 0; pi < count && at + 3 <= chunk_end; pi += 1 {
						a.Palette[base + pi] = Color{data[at], data[at + 1], data[at + 2], 255}
						at += 3
					}
				}
			case 0x2004:
				if at + 16 <= chunk_end {
					flags := ase_u16(data, &at)
					layer_type := ase_u16(data, &at)
					child := ase_u16(data, &at)
					dw := ase_u16(data, &at)
					dh := ase_u16(data, &at)
					blend := ase_u16(data, &at)
					opacity := data[at]
					at += 4
					name := ase_string(data, &at)
					tileset_index := -1
					if layer_type == 2 && at + 4 <= chunk_end {
						tileset_index = int(ase_u32(data, &at))
					}
					lf: AsepriteLayerFlags = {}
					for flag in AsepriteLayerFlag {
						if flags & (u16(1) << u16(flag)) != 0 {
							lf += {flag}
						}
					}
					append(&a.Layers, AsepriteLayer {
						Name         = name,
						Type         = AsepriteLayerType(layer_type),
						Flags        = lf,
						ChildLevel   = int(child),
						DefaultSize  = Point2{int(dw), int(dh)},
						BlendMode    = AsepriteBlendMode(blend),
						Opacity      = opacity,
						TilesetIndex = tileset_index,
					})
					last_userdata_kind = 1
					last_userdata_index = len(a.Layers) - 1
				}
			case 0x2005:
				if at + 16 <= chunk_end {
					layer := int(ase_u16(data, &at))
					x := int(ase_s16(data, &at))
					y := int(ase_s16(data, &at))
					opacity := data[at]
					at += 1
					cel_type := AsepriteCelType(ase_u16(data, &at))
					z := int(ase_s16(data, &at))
					at += 5
					if cel_type == .LinkedCel {
						linked := int(ase_u16(data, &at))
						append(&frame.Cels, AsepriteCel {
							Frame       = fi,
							Layer       = layer,
							Position    = Point2{x, y},
							Opacity     = opacity,
							ZIndex      = z,
							Type        = cel_type,
							LinkedFrame = linked,
							LinkedLayer = layer,
						})
					} else if cel_type != .CompressedTilemap && at + 4 <= chunk_end {
						w := int(ase_u16(data, &at))
						h := int(ase_u16(data, &at))
						payload := data[at:chunk_end]
						raw := payload
						buf: bytes.Buffer
						if cel_type == .CompressedImage {
							if zlib.inflate_from_byte_array(payload, &buf) == nil {
								raw = bytes.buffer_to_bytes(&buf)
							}
						}
						append(&frame.Cels, AsepriteCel {
							Frame       = fi,
							Layer       = layer,
							Position    = Point2{x, y},
							Opacity     = opacity,
							ZIndex      = z,
							Image       = ase_pixels(raw, a.Format, w, h, a.Palette[:]),
							Type        = cel_type,
							LinkedFrame = -1,
							LinkedLayer = -1,
						})
						bytes.buffer_destroy(&buf)
					}
					last_userdata_kind = 2
					last_userdata_index = len(frame.Cels) - 1
				}
			case 0x2018:
				if at + 10 <= chunk_end {
					count := int(ase_u16(data, &at))
					at += 8
					for _ in 0 ..< count {
						from := int(ase_u16(data, &at))
						to := int(ase_u16(data, &at))
						dir := AsepriteLoopDir(data[at])
						at += 1
						repeat := int(ase_u16(data, &at))
						at += 10
						append(&a.Tags, AsepriteTag {
							Name      = ase_string(data, &at),
							From      = from,
							To        = to,
							Direction = dir,
							Repeat    = repeat,
						})
						last_userdata_kind = 3
						last_userdata_index = len(a.Tags) - 1
					}
				}
			case 0x2022:
				if at + 12 <= chunk_end {
					count := int(ase_u32(data, &at))
					flags := ase_u32(data, &at)
					at += 4
					slice := AsepriteSlice {
						Name = ase_string(data, &at),
					}
					for _ in 0 ..< count {
						start_frame := int(ase_u32(data, &at))
						x := int(ase_s32(data, &at))
						y := int(ase_s32(data, &at))
						w := int(ase_u32(data, &at))
						h := int(ase_u32(data, &at))
						key := AsepriteSliceKey {
							FrameStart = start_frame,
							Bounds     = RectInt{x, y, w, h},
						}
						if flags & 1 != 0 && at + 16 <= chunk_end {
							key.NinSliceCenter = RectInt {
								int(ase_s32(data, &at)),
								int(ase_s32(data, &at)),
								int(ase_u32(data, &at)),
								int(ase_u32(data, &at)),
							}
							key.HasNineSlice = true
						}
						if flags & 2 != 0 && at + 8 <= chunk_end {
							key.Pivot = Point2{int(ase_s32(data, &at)), int(ase_s32(data, &at))}
							key.HasPivot = true
						}
						append(&slice.Keys, key)
					}
					append(&a.Slices, slice)
					last_userdata_kind = 4
					last_userdata_index = len(a.Slices) - 1
				}
			case 0x2020:
				// User data is attached to the preceding chunk. Preserve the payload on
				// the current frame and document-level object when no finer owner exists.
				if at + 4 <= chunk_end {
					flags := ase_u32(data, &at)
					text := ""
					if flags & 1 != 0 && at + 2 <= chunk_end {
						text = ase_string(data, &at)
					}
					value := AsepriteUserDataValues {
						Text = text,
					}
					if flags & 2 != 0 && at + 4 <= chunk_end {
						value.Color = Color{data[at], data[at + 1], data[at + 2], data[at + 3]}
						at += 4
					}
					switch last_userdata_kind {
					case 1:
						if last_userdata_index >= 0 && last_userdata_index < len(a.Layers) {
							a.Layers[last_userdata_index].UserData = value
						}
					case 2:
						if last_userdata_index >= 0 && last_userdata_index < len(frame.Cels) {
							frame.Cels[last_userdata_index].UserData = value
						}
					case 3:
						if last_userdata_index >= 0 && last_userdata_index < len(a.Tags) {
							a.Tags[last_userdata_index].UserData = value
						}
					case 4:
						if last_userdata_index >= 0 && last_userdata_index < len(a.Slices) {
							a.Slices[last_userdata_index].UserData = value
						}
					case:
						frame.UserData = value
					}
					a.UserData = value
				}
			}
			at = chunk_end
		}
		append(&a.Frames, frame)
		at = end
	}
	// Resolve linked cels after all frames have been read, including forward links.
	for fi := 0; fi < len(a.Frames); fi += 1 {
		for ci := 0; ci < len(a.Frames[fi].Cels); ci += 1 {
			cel := &a.Frames[fi].Cels[ci]
			if cel.Type != .LinkedCel || cel.LinkedFrame < 0 || cel.LinkedFrame >= len(a.Frames) {
				continue
			}
			for source in a.Frames[cel.LinkedFrame].Cels {
				if source.Layer != cel.LinkedLayer ||
				   source.Image.Width <= 0 ||
				   source.Image.Height <= 0 {
					continue
				}
				copy := ImageFromPixels(
					source.Image.Width,
					source.Image.Height,
					source.Image.Pixels[:],
				)
				cel.Image = copy
				break
			}
		}
	}
	return a
}

AsepriteDispose :: proc(aseprite: ^Aseprite) {
	if aseprite == nil {
		return
	}
	for &frame in aseprite.Frames {
		for &cel in frame.Cels {
			ImageDispose(&cel.Image)
		}
		delete(frame.Cels)
	}
	for slice in aseprite.Slices {
		delete(slice.Keys)
	}
	delete(aseprite.Frames)
	delete(aseprite.Layers)
	delete(aseprite.Tags)
	delete(aseprite.Slices)
	delete(aseprite.Palette)
	delete(aseprite.SourceData)
	aseprite^ = {}
}

AsepriteLoadFile :: proc(path: string) -> Aseprite {
	data := storage_os_read_file(path, context.temp_allocator)
	if data == nil {
		return {}
	}
	return AsepriteLoad(data)
}

ase_effective_opacity :: proc(a: ^Aseprite, layer_index: int, cel_opacity: u8) -> f32 {
	if layer_index < 0 || layer_index >= len(a.Layers) {
		return 0
	}
	if .Visible not_in a.Layers[layer_index].Flags {
		return 0
	}
	value := f32(cel_opacity) / 255 * f32(a.Layers[layer_index].Opacity) / 255
	level := a.Layers[layer_index].ChildLevel
	for i := layer_index - 1; i >= 0; i -= 1 {
		if a.Layers[i].ChildLevel < level {
			if a.Layers[i].Type == .Group {
				if .Visible not_in a.Layers[i].Flags {
					return 0
				}
				value *= f32(a.Layers[i].Opacity) / 255
			}
			level = a.Layers[i].ChildLevel
		}
	}
	return value
}

ase_blend_channel :: proc(mode: AsepriteBlendMode, base, blend: f32) -> f32 {
	#partial switch mode {
	case .Multiply:
		return base * blend
	case .Screen:
		return 1 - (1 - base) * (1 - blend)
	case .Overlay:
		return base < .5 ? 2 * base * blend : 1 - 2 * (1 - base) * (1 - blend)
	case .Darken:
		return math.min(base, blend)
	case .Lighten:
		return math.max(base, blend)
	case .ColorDodge:
		if blend >= 1 {
			return 1
		}
		return math.min(1, base / (1 - blend))
	case .ColorBurn:
		if blend <= 0 {
			return 0
		}
		return 1 - math.min(1, (1 - base) / blend)
	case .HardLight:
		return blend < .5 ? 2 * base * blend : 1 - 2 * (1 - base) * (1 - blend)
	case .SoftLight:
		if blend < .5 {
			return base - (1 - 2 * blend) * base * (1 - base)
		}
		return base + (2 * blend - 1) * (math.sqrt(base) - base)
	case .Addition:
		return math.min(1, base + blend)
	case .Subtract:
		return math.max(0, base - blend)
	case .Difference:
		return math.abs(base - blend)
	case .Exclusion:
		return base + blend - 2 * base * blend
	case .Divide:
		if blend <= 0 {
			return 1
		}
		return math.min(1, base / blend)
	case:
		return blend
	}
}

ase_rgb_to_hsl :: proc(r, g, b: f32) -> [3]f32 {
	maxv := math.max(r, math.max(g, b))
	minv := math.min(r, math.min(g, b))
	l := (maxv + minv) * 0.5
	if maxv == minv {
		return [3]f32{0, 0, l}
	}
	d := maxv - minv
	s := d / (1 - math.abs(2 * l - 1))
	h: f32 = 0
	if maxv == r {
		h = (g - b) / d
		if h < 0 {
			h += 6
		}
	} else if maxv == g {
		h = (b - r) / d + 2
	} else {
		h = (r - g) / d + 4
	}
	return [3]f32{h / 6, s, l}
}

ase_hue_to_rgb :: proc(p, q, t: f32) -> f32 {
	x := t
	if x < 0 {
		x += 1
	}
	if x > 1 {
		x -= 1
	}
	if x < 1.0 / 6 {
		return p + (q - p) * 6 * x
	}
	if x < 1.0 / 2 {
		return q
	}
	if x < 2.0 / 3 {
		return p + (q - p) * (2.0 / 3 - x) * 6
	}
	return p
}

ase_hsl_to_rgb :: proc(h, s, l: f32) -> [3]f32 {
	if s <= 0 {
		return [3]f32{l, l, l}
	}
	q := l * (1 + s)
	if l >= 0.5 {
		q = l + s - l * s
	}
	p := 2 * l - q
	return [3]f32 {
		ase_hue_to_rgb(p, q, h + 1.0 / 3),
		ase_hue_to_rgb(p, q, h),
		ase_hue_to_rgb(p, q, h - 1.0 / 3),
	}
}

ase_blend_pixel :: proc(dst, src: Color, mode: AsepriteBlendMode, opacity: f32) -> Color {
	sa := f32(src.A) / 255 * opacity
	if sa <= 0 {
		return dst
	}
	da := f32(dst.A) / 255
	sr, sg, sb := f32(src.R) / 255, f32(src.G) / 255, f32(src.B) / 255
	dr, dg, db := f32(dst.R) / 255, f32(dst.G) / 255, f32(dst.B) / 255
	br, bg, bb: f32
	if mode == .Hue || mode == .Saturation || mode == .Color || mode == .Luminosity {
		base := ase_rgb_to_hsl(dr, dg, db)
		blend := ase_rgb_to_hsl(sr, sg, sb)
		h, s, l := base[0], base[1], base[2]
		#partial switch mode {
		case .Hue:
			h = blend[0]
		case .Saturation:
			s = blend[1]
		case .Color:
			h, s = blend[0], blend[1]
		case .Luminosity:
			l = blend[2]
		}
		rgb := ase_hsl_to_rgb(h, s, l)
		br, bg, bb = rgb[0], rgb[1], rgb[2]
	} else {
		br, bg, bb =
			ase_blend_channel(mode, dr, sr),
			ase_blend_channel(mode, dg, sg),
			ase_blend_channel(mode, db, sb)
	}
	oa := sa + da * (1 - sa)
	if oa <= 0 {
		return Transparent
	}
	return Color {
		u8((br * sa + dr * da * (1 - sa)) / oa * 255),
		u8((bg * sa + dg * da * (1 - sa)) / oa * 255),
		u8((bb * sa + db * da * (1 - sa)) / oa * 255),
		u8(oa * 255),
	}
}
AsepriteLayerFilter :: #type proc(layer: AsepriteLayer) -> bool

AsepriteRenderFrameFiltered :: proc(
	a: ^Aseprite,
	index: int,
	filter: AsepriteLayerFilter = nil,
) -> Image {
	if a == nil || index < 0 || index >= len(a.Frames) {
		return {}
	}
	out := ImageMake(a.Width, a.Height)
	order: [dynamic]int = {}
	defer delete(order)
	for i := 0; i < len(a.Frames[index].Cels); i += 1 {
		z := a.Frames[index].Cels[i].ZIndex
		at := len(order)
		for j in 0 ..< len(order) {
			if a.Frames[index].Cels[order[j]].ZIndex > z {
				at = j
				break
			}
		}
		append(&order, 0)
		for j := len(order) - 1; j > at; j -= 1 {
			order[j] = order[j - 1]
		}
		order[at] = i
	}
	for oi in order {
		cel := a.Frames[index].Cels[oi]
		if cel.Layer < 0 || cel.Layer >= len(a.Layers) {
			continue
		}
		layer := a.Layers[cel.Layer]
		if .Visible not_in layer.Flags {
			continue
		}
		if filter != nil && !filter(layer) {
			continue
		}
		opacity := ase_effective_opacity(a, cel.Layer, cel.Opacity)
		src := cel.Image
		for y in 0 ..< src.Height {
			for x in 0 ..< src.Width {
				dx := cel.Position.X + x
				dy := cel.Position.Y + y
				if dx < 0 || dy < 0 || dx >= out.Width || dy >= out.Height {
					continue
				}
				s := ImageGetPixel(&src, x, y)
				out.Pixels[dx + dy * out.Width] = ase_blend_pixel(
					out.Pixels[dx + dy * out.Width],
					s,
					layer.BlendMode,
					opacity,
				)
			}
		}
	}
	return out
}

AsepriteRenderFrame :: proc(a: ^Aseprite, index: int) -> Image {
	return AsepriteRenderFrameFiltered(a, index, nil)
}

AsepriteRenderFrames :: proc(
	a: ^Aseprite,
	from, to: int,
	filter: AsepriteLayerFilter = nil,
) -> [dynamic]Image {
	result: [dynamic]Image = {}
	if a == nil {
		return result
	}
	lo, hi := from, to
	if lo < 0 {
		lo = 0
	}
	if hi >= len(a.Frames) {
		hi = len(a.Frames) - 1
	}
	if hi < lo {
		return result
	}
	for i := lo; i <= hi; i += 1 {
		append(&result, AsepriteRenderFrameFiltered(a, i, filter))
	}
	return result
}

AsepriteRenderAllFrames :: proc(
	a: ^Aseprite,
	filter: AsepriteLayerFilter = nil,
) -> [dynamic]Image {
	if a == nil {
		return {}
	}
	return AsepriteRenderFrames(a, 0, len(a.Frames) - 1, filter)
}

AsepriteRenderFramesSlice :: proc(
	a: ^Aseprite,
	from, to: int,
	slice: RectInt,
	filter: AsepriteLayerFilter = nil,
) -> [dynamic]Image {
	result: [dynamic]Image = {}
	frames := AsepriteRenderFrames(a, from, to, filter)
	defer delete(frames)
	for &image in frames {
		cropped := ImageMake(slice.Width, slice.Height)
		source := image
		ImageCopyPixels(&cropped, &source, slice, Point2{})
		ImageDispose(&image)
		append(&result, cropped)
	}
	return result
}

AsepriteRenderSlice :: proc(
	a: ^Aseprite,
	frame: int,
	slice_index: int,
	filter: AsepriteLayerFilter = nil,
) -> Image {
	if a == nil || slice_index < 0 || slice_index >= len(a.Slices) {
		return {}
	}
	img := AsepriteRenderFrameFiltered(a, frame, filter)
	keys := a.Slices[slice_index].Keys
	if len(keys) == 0 {
		return img
	}
	key := keys[0]
	for k in keys {
		if k.FrameStart <= frame {
			key = k
		} else {
			break
		}
	}
	out := ImageMake(key.Bounds.Width, key.Bounds.Height)
	ImageCopyPixels(&out, &img, key.Bounds, Point2{})
	ImageDispose(&img)
	return out
}

// ==============================================================================
// Images / MsdfFont — MSDF 字体
// ==============================================================================
// core:os 经根包 storage_os_* 平台层使用(js 目标无 core:os)

MsdfAtlasProperties :: struct {
	Type:                                                    string,
	DistanceRange, DistanceRangeMiddle, Size, Width, Height: f32,
	YOrigin:                                                 string,
}

MsdfMetricsProperties :: struct {
	EmSize, LineHeight, Ascender, Descender, UnderlineY, UnderlineThickness: f32,
}

MsdfBounds :: struct {
	Left, Top, Right, Bottom: f32,
}

MsdfGlyph :: struct {
	Unicode:                  int,
	Advance:                  f32,
	PlaneBounds, AtlasBounds: MsdfBounds,
}

MsdfCharacter :: struct {
	Codepoint:  int,
	SourceRect: Rect,
	Advance:    f32,
	Offset:     Vec2,
}

MsdfKerning :: struct {
	First, Second: int,
	Advance:       f32,
}

MsdfFont :: struct {
	OwnsImage:                                                         bool,
	Image:                                                             Image,
	Size, Ascent, Descent, LineGap, Height, LineHeight, DistanceRange: f32,
	Characters:                                                        [dynamic]MsdfCharacter,
	Kerning:                                                           [dynamic]MsdfKerning,
}

msdf_num :: proc(v: json.Value) -> f32 {
	#partial switch x in v {
	case json.Float:
		return f32(x)
	case json.Integer:
		return f32(x)
	}
	return 0
}

msdf_obj :: proc(v: json.Value) -> json.Object {
	#partial switch x in v {
	case json.Object:
		return x
	}
	return nil
}

msdf_array :: proc(v: json.Value) -> json.Array {
	#partial switch x in v {
	case json.Array:
		return x
	}
	return nil
}

msdf_string :: proc(v: json.Value) -> string {
	#partial switch x in v {
	case json.String:
		return string(x)
	}
	return ""
}

msdf_bounds :: proc(v: json.Value) -> MsdfBounds {
	o := msdf_obj(v)
	return MsdfBounds {
		msdf_num(o["left"]),
		msdf_num(o["top"]),
		msdf_num(o["right"]),
		msdf_num(o["bottom"]),
	}
}

MsdfFontMake :: proc(atlas: Image, data: []u8) -> MsdfFont {
	f := MsdfFont {
		Image = atlas,
	}
	value, err := json.parse_bytes(data, json.Specification.JSON, false)
	if err != .None {
		return f
	}
	root := msdf_obj(value)
	a := msdf_obj(root["atlas"])
	m := msdf_obj(root["metrics"])
	f.Size = msdf_num(a["size"])
	f.DistanceRange = msdf_num(a["distanceRange"])
	f.Ascent = math_abs(msdf_num(m["ascender"])) * f.Size
	f.Descent = -math_abs(msdf_num(m["descender"])) * f.Size
	f.Height = f.Ascent - f.Descent
	f.LineHeight = msdf_num(m["lineHeight"]) * f.Size
	f.LineGap = f.LineHeight - f.Height
	for glyph in msdf_array(root["glyphs"]) {
		o := msdf_obj(glyph)
		unicode := int(msdf_num(o["unicode"]))
		advance := msdf_num(o["advance"]) * f.Size
		plane := msdf_bounds(o["planeBounds"])
		atlas_bounds := msdf_bounds(o["atlasBounds"])
		source := Rect {
			atlas_bounds.Left,
			atlas_bounds.Top,
			atlas_bounds.Right - atlas_bounds.Left,
			atlas_bounds.Bottom - atlas_bounds.Top,
		}
		offset := Vec2{plane.Left * f.Size, plane.Top * f.Size}
		append(&f.Characters, MsdfCharacter{unicode, source, advance, offset})
	}
	for pair in msdf_array(root["kerning"]) {
		o := msdf_obj(pair)
		first := int(msdf_num(o["unicode1"]))
		second := int(msdf_num(o["unicode2"]))
		advance := msdf_num(o["advance"]) * f.Size
		append(&f.Kerning, MsdfKerning{first, second, advance})
	}
	json.destroy_value(value)
	return f
}

math_abs :: proc(v: f32) -> f32 {
	if v < 0 {
		return -v
	}
	return v
}

MsdfFontDispose :: proc(font: ^MsdfFont) {
	if font == nil {
		return
	}
	if font.OwnsImage {
		ImageDispose(&font.Image)
	}
	delete(font.Characters)
	delete(font.Kerning)
	font^ = {}
}

MsdfFontLoadFiles :: proc(image_path, data_path: string) -> MsdfFont {
	image := ImageLoadFile(image_path)
	data := storage_os_read_file(data_path, context.temp_allocator)
	if data == nil {
		return MsdfFont{Image = image}
	}
	font := MsdfFontMake(image, data)
	font.OwnsImage = true
	return font
}

MsdfFontGetKerning :: proc(f: ^MsdfFont, a, b: int, size: f32 = 0) -> f32 {
	if f == nil {
		return 0
	}
	s := size
	if s == 0 {
		s = f.Size
	}
	for k in f.Kerning {
		if k.First == a && k.Second == b {
			if f.Size > 0 {
				return k.Advance * (s / f.Size)
			}
			return k.Advance
		}
	}
	return 0
}

MsdfFontFindCharacter :: proc(f: ^MsdfFont, codepoint: int) -> (MsdfCharacter, bool) {
	if f == nil {
		return {}, false
	}
	for c in f.Characters {
		if c.Codepoint == codepoint {
			return c, true
		}
	}
	return {}, false
}

// ==============================================================================
// Images / Font — 字体字形与度量
// ==============================================================================
// core:os 经根包 storage_os_* 平台层使用(js 目标无 core:os)

FontCharacter :: struct {
	GlyphIndex:    int,
	Width, Height: int,
	Advance:       f32,
	Offset:        Vec2,
	Scale:         f32,
	Visible:       bool,
}

Font :: struct {
	Data:                     [dynamic]u8,
	Backend:                  stb.StbFont,
	Ascent, Descent, LineGap: int,
	Disposed:                 bool,
}

FontMake :: proc(data: []u8) -> Font {
	f := Font{}
	for b in data {
		append(&f.Data, b)
	}
	f.Backend = stb.StbFontInit(f.Data[:])
	f.Ascent, f.Descent, f.LineGap = stb.StbFontMetrics(&f.Backend)
	if f.LineGap <= 0 && f.Descent < 0 {
		f.LineGap = -f.Descent
		f.Descent = 0
	}
	return f
}

FontLoadFile :: proc(path: string) -> Font {
	data := storage_os_read_file(path, context.temp_allocator)
	if data == nil {
		return {}
	}
	return FontMake(data)
}

FontHeight :: proc(f: ^Font) -> int {
	return f.Ascent - f.Descent
}

FontLineHeight :: proc(f: ^Font) -> int {
	return f.Ascent - f.Descent + f.LineGap
}

FontGetGlyphIndex :: proc(f: ^Font, codepoint: int) -> int {
	return stb.StbFontGlyph(&f.Backend, codepoint)
}

FontGetScale :: proc(f: ^Font, size: f32) -> f32 {
	return stb.StbFontScale(&f.Backend, size)
}

FontGetKerning :: proc(f: ^Font, a, b: int, scale: f32) -> f32 {
	return FontGetKerningBetweenGlyphs(f, FontGetGlyphIndex(f, a), FontGetGlyphIndex(f, b), scale)
}

FontGetCharacter :: proc(f: ^Font, codepoint: int, scale: f32) -> FontCharacter {
	glyph := FontGetGlyphIndex(f, codepoint)
	w, h, adv, ox, oy, visible := stb.StbFontCharacter(&f.Backend, glyph, scale)
	return FontCharacter {
		GlyphIndex = glyph,
		Width      = w,
		Height     = h,
		Advance    = adv,
		Offset     = Vec2{ox, oy},
		Scale      = scale,
		Visible    = visible,
	}
}

FontGetCharacterOfGlyph :: proc(f: ^Font, glyph: int, scale: f32) -> FontCharacter {
	w, h, adv, ox, oy, visible := stb.StbFontCharacter(&f.Backend, glyph, scale)
	return FontCharacter {
		GlyphIndex = glyph,
		Width      = w,
		Height     = h,
		Advance    = adv,
		Offset     = Vec2{ox, oy},
		Scale      = scale,
		Visible    = visible,
	}
}

FontGetKerningBetweenGlyphs :: proc(f: ^Font, a, b: int, scale: f32) -> f32 {
	return stb.StbFontKerning(&f.Backend, a, b, scale)
}

FontRasterize :: proc(f: ^Font, codepoint: int, size: f32) -> [dynamic]u8 {
	glyph := FontGetGlyphIndex(f, codepoint)
	ch := FontGetCharacter(f, codepoint, size)
	return stb.StbFontRasterize(&f.Backend, glyph, ch.Width, ch.Height, size)
}

FontGetPixels :: proc(
	f: ^Font,
	ch: FontCharacter,
	destination: []Color,
	premultiply_alpha: bool = true,
) -> bool {
	if !ch.Visible || len(destination) < ch.Width * ch.Height {
		return false
	}
	pixels := stb.StbFontRasterize(&f.Backend, ch.GlyphIndex, ch.Width, ch.Height, ch.Scale)
	defer delete(pixels)
	for i in 0 ..< ch.Width * ch.Height {
		destination[i] = Color{255, 255, 255, pixels[i]}
		if premultiply_alpha {
			destination[i] = Premultiply(destination[i])
		}
	}
	return true
}

FontGetImage :: proc(f: ^Font, ch: FontCharacter, premultiply_alpha: bool = true) -> Image {
	if !ch.Visible {
		return {}
	}
	img := ImageMake(ch.Width, ch.Height)
	_ = FontGetPixels(f, ch, img.Pixels[:], premultiply_alpha)
	return img
}

FontGetImageForCodepoint :: proc(f: ^Font, codepoint: int, scale: f32) -> Image {
	ch := FontGetCharacter(f, codepoint, scale)
	return FontGetImage(f, ch)
}

FontDispose :: proc(f: ^Font) {
	if f == nil {
		return
	}
	delete(f.Data)
	delete(f.Backend.Data)
	f.Data = nil
	f.Backend = stb.StbFont{}
	f.Disposed = true
}

// ==============================================================================
// Graphics / Texture — 从图像创建纹理
// ==============================================================================

TextureFromImage :: proc(device: ^GraphicsDevice, image: ^Image, name: string = "") -> Texture {
	tex: Texture
	if device == nil || image == nil || image.Width <= 0 || image.Height <= 0 {
		return tex
	}
	TextureInit(&tex, device, image.Width, image.Height, .Color, name)
	TextureSetData(&tex, raw_data(image.Pixels), len(image.Pixels) * size_of(Color))
	return tex
}

// ==============================================================================
// Graphics / SpriteFont — 字体烘焙、排版与绘制
// ==============================================================================

SpriteFontCharacter :: struct {
	Codepoint:  int,
	Subtexture: Subtexture,
	Advance:    f32,
	Offset:     Vec2,
	Exists:     bool,
}

SpriteFontKerning :: struct {
	First, Second: int,
	Advance:       f32,
}

SpriteFont :: struct {
	GraphicsDevice:      ^GraphicsDevice,
	Name:                string,
	Image:               ^Image,
	GeneratedTextures:   [dynamic]^Texture,
	Texture:             ^Texture,
	OwnsImage:           bool,
	Characters:          [dynamic]SpriteFontCharacter,
	Kerning:             [dynamic]SpriteFontKerning,
	LineHeight:          f32,
	Ascent:              f32,
	Descent:             f32,
	LineGap:             f32,
	Size:                f32,
	KerningFont:         ^Font,
	Material:            Material,
	Sampler:             TextureSampler,
	HasMaterial:         bool,
	NewlineCharacters:   [dynamic]rune,
	WordbreakCharacters: [dynamic]rune,
}

SpriteFontAscii :: proc() -> [96]int {
	result: [96]int = {}
	for i in 0 ..< len(result) {
		result[i] = i + 32
	}
	return result
}

SpriteFontMake :: proc(font: ^Font, size: f32 = 16, codepoints: []int = nil) -> SpriteFont {
	result := SpriteFont {
		Size        = size,
		KerningFont = font,
	}
	append(&result.NewlineCharacters, '\n')
	append(&result.WordbreakCharacters, '\n', ' ')
	if font == nil {
		return result
	}
	scale := FontGetScale(font, size)
	result.Ascent = f32(font.Ascent) * scale
	result.Descent = f32(font.Descent) * scale
	result.LineGap = f32(font.LineGap) * scale
	result.LineHeight = result.Ascent - result.Descent + result.LineGap
	result.Image = new(Image)
	result.Image^ = ImageMake(2048, 2048)
	result.OwnsImage = true
	points := codepoints
	if len(points) == 0 {
		ascii := SpriteFontAscii()
		points = ascii[:]
	}
	x, y, row := 0, 0, 0
	for cp in points {
		ch := FontGetCharacter(font, cp, scale)
		c := SpriteFontCharacter {
			Codepoint = cp,
			Advance   = ch.Advance,
			Offset    = ch.Offset,
			Exists    = true,
		}
		if ch.Visible && ch.Width > 0 && ch.Height > 0 {
			if x + ch.Width + 1 >= result.Image.Width {
				x = 0
				y += row + 1
				row = 0
			}
			// CPU 图集装不下时跳过该字形的位图(但保留字符注册): SpriteFontMakeGPU 会
			// 用 Packer 重新栅格化, 不依赖这张图; 旧行为是 break, 会静默丢弃后续全部码点
			if y + ch.Height < result.Image.Height {
				bmp := FontRasterize(font, cp, scale)
				for py in 0 ..< ch.Height {
					for px in 0 ..< ch.Width {
						ImageSetPixel(
							result.Image,
							x + px,
							y + py,
							Color{255, 255, 255, bmp[py * ch.Width + px]},
						)
					}
				}
				delete(bmp)
				c.Subtexture = Subtexture {
					Source = Rect{f32(x), f32(y), f32(ch.Width), f32(ch.Height)},
					Frame  = Rect{-ch.Offset[0], -ch.Offset[1], f32(ch.Width), f32(ch.Height)},
				}
				x += ch.Width + 1
				if ch.Height > row {
					row = ch.Height
				}
			}
		}
		append(&result.Characters, c)
	}
	return result
}

SpriteFontMakeGPU :: proc(
	device: ^GraphicsDevice,
	font: ^Font,
	size: f32 = 16,
	codepoints: []int = nil,
	premultiply_alpha: bool = true,
	pixel_perfect: bool = false,
) -> SpriteFont {
	result := SpriteFontMake(nil, size)
	result.GraphicsDevice = device
	result.KerningFont = font
	if font == nil || font.Disposed {
		return result
	}
	scale := FontGetScale(font, size)
	result.Ascent = f32(font.Ascent) * scale
	result.Descent = f32(font.Descent) * scale
	result.LineGap = f32(font.LineGap) * scale
	result.LineHeight = result.Ascent - result.Descent + result.LineGap
	points := codepoints
	ascii := SpriteFontAscii()
	if len(points) == 0 {
		points = ascii[:]
	}
	SpriteFontAddCharacters(&result, font, points, size, premultiply_alpha, pixel_perfect)
	return result
}

// ------------------------------------------------------------------------------
// Graphics / SpriteFont / Characters — 增量字形光栅化与图集
// ------------------------------------------------------------------------------

SpriteFontAddCharacters :: proc(
	sprite: ^SpriteFont,
	font: ^Font,
	codepoints: []int,
	size: f32 = 0,
	premultiply_alpha: bool = true,
	pixel_perfect: bool = false,
) {
	if sprite == nil || font == nil || font.Disposed {
		return
	}
	size := size
	if size <= 0 {
		size = sprite.Size
	}
	scale := FontGetScale(font, size)
	packer := PackerMake()
	defer PackerDispose(&packer)
	codepoint_indices: [dynamic]int
	defer delete(codepoint_indices)
	area, largest := 0, 1
	for codepoint in codepoints {
		ch := FontGetCharacter(font, codepoint, scale)
		SpriteFontAddCharacter(
			sprite,
			{Codepoint = codepoint, Advance = ch.Advance, Offset = ch.Offset, Exists = true},
		)
		if !ch.Visible || sprite.GraphicsDevice == nil {
			continue
		}
		image := FontGetImage(font, ch, premultiply_alpha)
		if pixel_perfect {
			for &pixel in image.Pixels {
				pixel = pixel.A < 128 ? Transparent : White
			}
		}
		PackerAdd(&packer, "", image)
		ImageDispose(&image)
		append(&codepoint_indices, codepoint)
		area += (ch.Width + packer.Padding) * (ch.Height + packer.Padding)
		largest = max(largest, ch.Width + packer.Padding, ch.Height + packer.Padding)
	}
	// Choose a small working page for small additions; the packer can emit more pages.
	packer.MaxSize = min(8192, packer_next_pow2(max(largest, int(math.sqrt(f64(area))) + 1)))
	output := PackerPack(&packer)
	defer PackerOutputDispose(&output)
	texture_start := len(sprite.GeneratedTextures)
	for &page in output.Pages {
		texture := new(Texture)
		texture^ = TextureFromImage(sprite.GraphicsDevice, &page, "SpriteFont")
		append(&sprite.GeneratedTextures, texture)
	}
	for entry in output.Entries {
		if entry.Index < 0 ||
		   entry.Index >= len(codepoint_indices) ||
		   entry.Page < 0 ||
		   entry.Page >= len(output.Pages) {
			continue
		}
		character := SpriteFontGetCharacter(sprite, codepoint_indices[entry.Index])
		character.Subtexture = SubtextureMake(
			sprite.GeneratedTextures[texture_start + entry.Page],
			{
				f32(entry.Source.X),
				f32(entry.Source.Y),
				f32(entry.Source.Width),
				f32(entry.Source.Height),
			},
			{
				f32(entry.Frame.X),
				f32(entry.Frame.Y),
				f32(entry.Frame.Width),
				f32(entry.Frame.Height),
			},
		)
		SpriteFontAddCharacter(sprite, character)
	}
	if sprite.Texture == nil && len(sprite.GeneratedTextures) > 0 {
		sprite.Texture = sprite.GeneratedTextures[0]
	}
}

SpriteFontFromMsdf :: proc(device: ^GraphicsDevice, msdf: ^MsdfFont) -> SpriteFont {
	result := SpriteFont {
		GraphicsDevice = device,
	}
	if msdf == nil {
		return result
	}
	result.Size = msdf.Size
	result.Ascent = msdf.Ascent
	result.Descent = msdf.Descent
	result.LineGap = msdf.LineGap
	result.LineHeight = msdf.LineHeight
	result.Image = &msdf.Image
	result.Sampler = TextureSamplerMake(TextureFilter.Linear, TextureWrap.Clamp)
	append(&result.NewlineCharacters, '\n')
	append(&result.WordbreakCharacters, '\n', ' ')
	for k in msdf.Kerning {
		append(&result.Kerning, SpriteFontKerning{k.First, k.Second, k.Advance})
	}
	if device != nil {
		tex := TextureFromImage(device, &msdf.Image, "MsdfFont")
		result.Texture = new(Texture)
		result.Texture^ = tex
		append(&result.GeneratedTextures, result.Texture)
		if device.Defaults.Initialized {
			result.Material = MaterialClone(&device.Defaults.MsdfMaterial)
			distance := [1]f32{msdf.DistanceRange}
			uniform: [size_of(distance)]u8
			mem.copy(raw_data(uniform[:]), raw_data(distance[:]), size_of(distance))
			MaterialStageSetUniformBuffer(&result.Material.Fragment, uniform[:], 0)
			result.HasMaterial = true
		}
	}
	for ch in msdf.Characters {
		source := ch.SourceRect
		frame := Rect{-ch.Offset[0], -ch.Offset[1], source.Width, source.Height}
		sub := SubtextureMake(result.Texture, source, frame)
		append(
			&result.Characters,
			SpriteFontCharacter{ch.Codepoint, sub, ch.Advance, ch.Offset, true},
		)
	}
	return result
}

SpriteFontFindCharacter :: proc(font: ^SpriteFont, codepoint: int) -> (SpriteFontCharacter, bool) {
	if font == nil {
		return {}, false
	}
	for c in font.Characters {
		if c.Codepoint == codepoint {
			return c, c.Exists
		}
	}
	return {}, false
}

SpriteFontGetCharacter :: proc(font: ^SpriteFont, codepoint: int) -> SpriteFontCharacter {
	c, _ := SpriteFontFindCharacter(font, codepoint)
	return c
}

SpriteFontTryGetCharacter :: proc(
	font: ^SpriteFont,
	codepoint: int,
) -> (
	SpriteFontCharacter,
	bool,
) {
	return SpriteFontFindCharacter(font, codepoint)
}

SpriteFontTryGetCharacterRune :: proc(font: ^SpriteFont, r: rune) -> (SpriteFontCharacter, bool) {
	return SpriteFontFindCharacter(font, int(r))
}

sprite_font_is_newline :: proc(font: ^SpriteFont, r: rune) -> bool {
	if font == nil {
		return r == '\n'
	}
	for c in font.NewlineCharacters {
		if c == r {
			return true
		}
	}
	return false
}

sprite_font_is_wordbreak :: proc(font: ^SpriteFont, r: rune) -> bool {
	if font == nil {
		return r == '\n' || r == ' '
	}
	for c in font.WordbreakCharacters {
		if c == r {
			return true
		}
	}
	return false
}

SpriteFontAddCharacter :: proc(font: ^SpriteFont, character: SpriteFontCharacter) {
	if font == nil {
		return
	}
	for i := 0; i < len(font.Characters); i += 1 {
		if font.Characters[i].Codepoint == character.Codepoint {
			font.Characters[i] = character
			return
		}
	}
	append(&font.Characters, character)
}

SpriteFontBindTexture :: proc(font: ^SpriteFont, texture: ^Texture) {
	if font == nil {
		return
	}
	for i := 0; i < len(font.Characters); i += 1 {
		c := font.Characters[i]
		if c.Subtexture.Source.Width > 0 && c.Subtexture.Source.Height > 0 {
			c.Subtexture = SubtextureMake(texture, c.Subtexture.Source, c.Subtexture.Frame)
			font.Characters[i] = c
		}
	}
}

SpriteFontSetKerning :: proc(font: ^SpriteFont, a, b: int, advance: f32) {
	if font == nil {
		return
	}
	for i := 0; i < len(font.Kerning); i += 1 {
		if font.Kerning[i].First == a && font.Kerning[i].Second == b {
			font.Kerning[i].Advance = advance
			return
		}
	}
	append(&font.Kerning, SpriteFontKerning{a, b, advance})
}

SpriteFontDispose :: proc(font: ^SpriteFont) {
	if font == nil {
		return
	}
	for tex in font.GeneratedTextures {
		if tex != nil {
			TextureDispose(tex)
			free(tex)
		}
	}
	delete(font.GeneratedTextures)
	font.GeneratedTextures = nil
	font.Texture = nil
	if font.Image != nil && font.OwnsImage {
		ImageDispose(font.Image)
		free(font.Image)
	}
	font.Image = nil
	delete(font.Characters)
	delete(font.Kerning)
	delete(font.NewlineCharacters)
	delete(font.WordbreakCharacters)
	font.Characters = nil
	font.Kerning = nil
	font.NewlineCharacters = nil
	font.WordbreakCharacters = nil
	if font.HasMaterial {
		MaterialDispose(&font.Material)
	}
	font.HasMaterial = false
}

SpriteFontGetKerning :: proc(font: ^SpriteFont, a, b: int, size: f32 = 0) -> f32 {
	if font == nil {
		return 0
	}
	s := size
	if s == 0 {
		s = font.Size
	}
	for k in font.Kerning {
		if k.First == a && k.Second == b {
			if font.Size > 0 {
				return k.Advance * (s / font.Size)
			}
			return k.Advance
		}
	}
	if font.KerningFont == nil {
		return 0
	}
	scale := FontGetScale(font.KerningFont, s)
	return FontGetKerning(font.KerningFont, a, b, scale)
}

SpriteFontWidthOfLine :: proc(font: ^SpriteFont, text: string, size: f32 = 0) -> f32 {
	if font == nil {
		return 0
	}
	s := size
	if s == 0 {
		s = font.Size
	}
	factor := f32(1)
	if font.Size > 0 {
		factor = s / font.Size
	}
	width: f32 = 0
	last := 0
	for r in text {
		if sprite_font_is_newline(font, r) {
			break
		}
		cp := int(r)
		if c, ok := SpriteFontFindCharacter(font, cp); ok {
			if last != 0 {
				width += SpriteFontGetKerning(font, last, cp)
			}
			width += c.Advance
		}
		last = cp
	}
	return width * factor
}

SpriteFontWidthOf :: proc(font: ^SpriteFont, text: string, size: f32 = 0) -> f32 {
	if font == nil {
		return 0
	}
	s := size
	if s == 0 {
		s = font.Size
	}
	maxw, cur: f32 = 0, 0
	last := 0
	for r in text {
		if sprite_font_is_newline(font, r) {
			if cur > maxw {
				maxw = cur
			}
			cur = 0
			last = 0
			continue
		}
		cp := int(r)
		if c, ok := SpriteFontFindCharacter(font, cp); ok {
			if last != 0 {
				cur += SpriteFontGetKerning(font, last, cp)
			}
			cur += c.Advance
		}
		last = cp
	}
	if cur > maxw {
		maxw = cur
	}
	if font.Size > 0 {
		return maxw * (s / font.Size)
	}
	return maxw
}

SpriteFontHeightOf :: proc(font: ^SpriteFont, text: string, size: f32 = 0) -> f32 {
	if font == nil || len(text) == 0 {
		return 0
	}
	s := size
	if s == 0 {
		s = font.Size
	}
	lines := 1
	for r in text {
		if sprite_font_is_newline(font, r) {
			lines += 1
		}
	}
	if font.Size > 0 {
		return(
			(font.LineHeight - font.LineGap + f32(lines - 1) * font.LineHeight) *
			(s / font.Size) \
		)
	}
	return font.LineHeight * f32(lines)
}

SpriteFontSizeOf :: proc(font: ^SpriteFont, text: string, size: f32 = 0) -> Vec2 {
	return Vec2{SpriteFontWidthOf(font, text, size), SpriteFontHeightOf(font, text, size)}
}

SpriteFontHeight :: proc(font: ^SpriteFont) -> f32 {
	if font == nil {
		return 0
	}
	return font.Ascent - font.Descent
}
SpriteFontMeasure :: SpriteFontSizeOf

sprite_font_draw_impl :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position, justify: Vec2,
	size: f32,
	color: Color,
	sine_start: f32 = 0,
	sine_step: f32 = 0,
	sine_offset: Vec2 = {},
) {
	if batch == nil || font == nil {
		return
	}
	scale := f32(1)
	if font.Size > 0 {
		scale = size / font.Size
	}
	BatcherPushMatrix2D(batch, position, Vec2{scale, scale}, 0, true)
	wave := sine_offset
	determinant := batch.Matrix[0] * batch.Matrix[5] - batch.Matrix[1] * batch.Matrix[4]
	if determinant != 0 {
		wave = {
			(sine_offset[0] * batch.Matrix[5] - sine_offset[1] * batch.Matrix[4]) / determinant,
			(sine_offset[1] * batch.Matrix[0] - sine_offset[0] * batch.Matrix[1]) / determinant,
		}
	}
	sine := sine_start
	if font.HasMaterial {
		BatcherPushMaterial(batch, &font.Material)
	}
	BatcherPushSampler(batch, font.Sampler)
	prev_texture := batch.Texture
	at := Vec2{0, font.Ascent}
	just_scale := f32(1)
	if font.Size > 0 && size > 0 {
		just_scale = font.Size / size
	}
	if justify[0] != 0 {
		at[0] -= justify[0] * SpriteFontWidthOfLine(font, text, size) * just_scale
	}
	if justify[1] != 0 {
		at[1] -= justify[1] * SpriteFontHeightOf(font, text, size) * just_scale
	}
	last := 0
	for r, index in text {
		if sprite_font_is_newline(font, r) {
			at[0] = 0
			if justify[0] != 0 && index + 1 < len(text) {
				at[0] -= justify[0] * SpriteFontWidthOfLine(font, text[index + 1:])
			}
			at[1] += font.LineHeight
			last = 0
			continue
		}
		cp := int(r)
		if c, ok := SpriteFontFindCharacter(font, cp); ok {
			if last != 0 {
				at[0] += SpriteFontGetKerning(font, last, cp)
			}
			if c.Subtexture.Texture != nil {
				BatcherImage(batch, c.Subtexture, at + c.Offset + wave * math.sin(sine), color)
			}
			at[0] += c.Advance
			sine += sine_step
			last = cp
		}
	}
	batch.Texture = prev_texture
	BatcherPopSampler(batch)
	if font.HasMaterial {
		BatcherPopMaterial(batch)
	}
	BatcherPopMatrixStack(batch)
}

SpriteFontDrawSineWave :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position, justify: Vec2,
	size: f32,
	color: Color,
	sine_start, sine_step: f32,
	sine_offset: Vec2,
) {
	sprite_font_draw_impl(
		batch,
		font,
		text,
		position,
		justify,
		size,
		color,
		sine_start,
		sine_step,
		sine_offset,
	)
}

sprite_font_draw_simple :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position: Vec2,
	color: Color,
) {
	sprite_font_draw_impl(batch, font, text, position, {}, font.Size, color)
}

sprite_font_draw_sized :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position: Vec2,
	size: f32,
	color: Color,
) {
	sprite_font_draw_impl(batch, font, text, position, {}, size, color)
}

sprite_font_draw_justified :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position, justify: Vec2,
	color: Color,
) {
	sprite_font_draw_impl(batch, font, text, position, justify, font.Size, color)
}

sprite_font_draw_justified_sized :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position, justify: Vec2,
	size: f32,
	color: Color,
) {
	sprite_font_draw_impl(batch, font, text, position, justify, size, color)
}
SpriteFontDraw :: proc {
	sprite_font_draw_simple,
	sprite_font_draw_sized,
	sprite_font_draw_justified,
	sprite_font_draw_justified_sized,
}

// ------------------------------------------------------------------------------
// Graphics / SpriteFont / Text — 测量、换行与绘制
// ------------------------------------------------------------------------------

SpriteFontTextRange :: struct {
	Start, Length: int,
}

SpriteFontWidthOfWord :: proc(
	font: ^SpriteFont,
	text: string,
	size: f32 = 0,
) -> (
	width: f32,
	length: int,
) {
	if font == nil {
		return 0, 0
	}
	s := size
	if s == 0 {
		s = font.Size
	}
	last := 0
	for length < len(text) {
		r, w := utf8.decode_rune_in_string(text[length:])
		if sprite_font_is_wordbreak(font, r) {
			break
		}
		cp := int(r)
		if c, ok := SpriteFontFindCharacter(font, cp); ok {
			if last != 0 {
				width += SpriteFontGetKerning(font, last, cp)
			}
			width += c.Advance
		}
		last = cp
		length += w
		if w <= 0 {
			length += 1
		}
	}
	if font.Size > 0 {
		width *= s / font.Size
	}
	return
}

SpriteFontWrapText :: proc(
	font: ^SpriteFont,
	text: string,
	max_width: f32,
	size: f32 = 0,
) -> [dynamic]SpriteFontTextRange {
	result: [dynamic]SpriteFontTextRange = {}
	if font == nil || len(text) == 0 {
		return result
	}
	line_start := 0
	line_width: f32 = 0
	cursor := 0
	for cursor < len(text) {
		r, w := utf8.decode_rune_in_string(text[cursor:])
		if w <= 0 {
			w = 1
		}
		if sprite_font_is_newline(font, r) {
			append(&result, SpriteFontTextRange{line_start, cursor - line_start})
			line_start = cursor + w
			cursor = line_start
			line_width = 0
			continue
		}
		word_width, word_len := SpriteFontWidthOfWord(font, text[cursor:], size)
		if line_width > 0 && max_width > 0 && line_width + word_width > max_width {
			append(&result, SpriteFontTextRange{line_start, cursor - line_start})
			line_start = cursor
			line_width = 0
		}
		line_width += word_width
		cursor += word_len
		if cursor < len(text) {
			next, _ := utf8.decode_rune_in_string(text[cursor:])
			if sprite_font_is_wordbreak(font, next) {
				line_width += SpriteFontWidthOfLine(font, text[cursor:cursor + 1], size)
				cursor += 1
			}
		}
		if word_len == 0 {
			cursor += w
		}
	}
	if line_start < len(text) {
		append(&result, SpriteFontTextRange{line_start, len(text) - line_start})
	}
	return result
}

sprite_font_draw_wrapped_impl :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position, justify: Vec2,
	max_width, size: f32,
	color: Color,
) {
	if batch == nil || font == nil {
		return
	}
	ranges := SpriteFontWrapText(font, text, max_width, size)
	defer delete(ranges)
	scale := font.Size > 0 ? size / font.Size : 1
	height := (f32(len(ranges)) * font.LineHeight - font.LineGap) * scale
	for range, line in ranges {
		line_position := Vec2 {
			position[0],
			position[1] - justify[1] * height + f32(line) * font.LineHeight * scale,
		}
		SpriteFontDraw(
			batch,
			font,
			text[range.Start:range.Start + range.Length],
			line_position,
			{justify[0], 0},
			size,
			color,
		)
	}
}

sprite_font_draw_wrapped_simple :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position: Vec2,
	max_width: f32,
	color: Color,
) {
	sprite_font_draw_wrapped_impl(batch, font, text, position, {}, max_width, font.Size, color)
}

sprite_font_draw_wrapped_justified :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position, justify: Vec2,
	max_width: f32,
	color: Color,
) {
	sprite_font_draw_wrapped_impl(
		batch,
		font,
		text,
		position,
		justify,
		max_width,
		font.Size,
		color,
	)
}

sprite_font_draw_wrapped_sized :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position: Vec2,
	max_width, size: f32,
	color: Color,
) {
	sprite_font_draw_wrapped_impl(batch, font, text, position, {}, max_width, size, color)
}

sprite_font_draw_wrapped_justified_sized :: proc(
	batch: ^Batcher,
	font: ^SpriteFont,
	text: string,
	position, justify: Vec2,
	max_width, size: f32,
	color: Color,
) {
	sprite_font_draw_wrapped_impl(batch, font, text, position, justify, max_width, size, color)
}
SpriteFontDrawWrapped :: proc {
	sprite_font_draw_wrapped_simple,
	sprite_font_draw_wrapped_justified,
	sprite_font_draw_wrapped_sized,
	sprite_font_draw_wrapped_justified_sized,
}

// ------------------------------------------------------------------------------
// Graphics / SpriteFont / Batcher — 文本绘制扩展
// ------------------------------------------------------------------------------

BatcherText :: SpriteFontDraw
BatcherTextWrapped :: SpriteFontDrawWrapped
