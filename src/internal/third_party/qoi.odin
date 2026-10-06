package foster_third_party

// 文件内导航
//   Internal / ThirdParty / QOI / Header — 文件描述与格式检测
//   Internal / ThirdParty / QOI / Helpers — 哈希与字节读取
//   Internal / ThirdParty / QOI / Decode — 解码
//   Internal / ThirdParty / QOI / Encode — 编码

// ==============================================================================
// Internal / ThirdParty / QOI / Header — 文件描述与格式检测
// ==============================================================================

QoiDesc :: struct {
	Width, Height:        u32,
	Channels, Colorspace: u8,
}

QoiIsFormat :: proc(data: []u8) -> bool {
	return len(data) >= 4 && data[0] == 'q' && data[1] == 'o' && data[2] == 'i' && data[3] == 'f'
}

// ------------------------------------------------------------------------------
// Internal / ThirdParty / QOI / Helpers — 哈希与字节读取
// ------------------------------------------------------------------------------

qoi_hash :: proc(r, g, b, a: u8) -> int {
	return (int(r) * 3 + int(g) * 5 + int(b) * 7 + int(a) * 11) & 63
}

qoi_read32 :: proc(data: []u8, at: ^int) -> u32 {
	a := u32(data[at^])
	at^ += 1
	b := u32(data[at^])
	at^ += 1
	c := u32(data[at^])
	at^ += 1
	d := u32(data[at^])
	at^ += 1
	return a << 24 | b << 16 | c << 8 | d
}

// ==============================================================================
// Internal / ThirdParty / QOI / Decode — 解码
// ==============================================================================

QoiDecode :: proc(data: []u8, channels: int, desc: ^QoiDesc) -> [dynamic]u8 {
	if len(data) < 22 || !QoiIsFormat(data) {
		return {}
	}
	at := 0
	magic := qoi_read32(data, &at)
	desc.Width = qoi_read32(data, &at)
	desc.Height = qoi_read32(data, &at)
	desc.Channels = data[at]
	at += 1
	desc.Colorspace = data[at]
	at += 1
	_ = magic
	if desc.Width == 0 ||
	   desc.Height == 0 ||
	   desc.Channels < 3 ||
	   desc.Channels > 4 ||
	   desc.Colorspace > 1 {
		return {}
	}
	ch := channels
	if ch == 0 {
		ch = int(desc.Channels)
	}
	if ch != 3 && ch != 4 {
		return {}
	}
	count := int(desc.Width * desc.Height)
	out := [dynamic]u8{}
	resize(&out, count * ch)
	ir: u8 = 0
	ig: u8 = 0
	ib: u8 = 0
	ia: u8 = 255
	idx: [64][4]u8 = {}
	run := 0
	end := len(data) - 8
	for n := 0; n < count; n += 1 {
		if run > 0 {
			run -= 1
		} else if at < end {
			b1 := data[at]
			at += 1
			if b1 == 0xfe {
				ir = data[at]
				ig = data[at + 1]
				ib = data[at + 2]
				at += 3
			} else if b1 == 0xff {
				ir = data[at]
				ig = data[at + 1]
				ib = data[at + 2]
				ia = data[at + 3]
				at += 4
			} else if (b1 & 0xc0) == 0 {
				v := idx[int(b1 & 63)]
				ir, ig, ib, ia = v[0], v[1], v[2], v[3]
			} else if (b1 & 0xc0) == 0x40 {
				ir = u8(int(ir) + int((b1 >> 4) & 3) - 2)
				ig = u8(int(ig) + int((b1 >> 2) & 3) - 2)
				ib = u8(int(ib) + int(b1 & 3) - 2)
			} else if (b1 & 0xc0) == 0x80 {
				b2 := data[at]
				at += 1
				vg := int(b1 & 63) - 32
				ir = u8(int(ir) + vg - 8 + int((b2 >> 4) & 15))
				ig = u8(int(ig) + vg)
				ib = u8(int(ib) + vg - 8 + int(b2 & 15))
			} else {
				run = int(b1 & 63)
			}
			idx[qoi_hash(ir, ig, ib, ia)] = [4]u8{ir, ig, ib, ia}
		}
		pos := n * ch
		out[pos] = ir
		out[pos + 1] = ig
		out[pos + 2] = ib
		if ch == 4 {
			out[pos + 3] = ia
		}
	}
	return out
}

// ==============================================================================
// Internal / ThirdParty / QOI / Encode — 编码
// ==============================================================================

QoiEncode :: proc(
	pixels: []u8,
	width, height: u32,
	channels: u8,
	colorspace: u8 = 0,
) -> [dynamic]u8 {
	if width == 0 || height == 0 || (channels != 3 && channels != 4) {
		return {}
	}
	out: [dynamic]u8 = {}
	append(&out, 'q', 'o', 'i', 'f')
	append(
		&out,
		u8(width >> 24),
		u8(width >> 16),
		u8(width >> 8),
		u8(width),
		u8(height >> 24),
		u8(height >> 16),
		u8(height >> 8),
		u8(height),
		channels,
		colorspace,
	)
	idx: [64][4]u8 = {}
	pr: u8 = 0
	pg: u8 = 0
	pb: u8 = 0
	pa: u8 = 255
	run := 0
	count := int(width * height)
	for n in 0 ..< count {
		pos := n * int(channels)
		r, g, b := pixels[pos], pixels[pos + 1], pixels[pos + 2]
		a := pa
		if channels == 4 {
			a = pixels[pos + 3]
		}
		if r == pr && g == pg && b == pb && a == pa {
			run += 1
			if run == 62 || n == count - 1 {
				append(&out, u8(0xc0 | (run - 1)))
				run = 0
			}
		} else {
			if run > 0 {
				append(&out, u8(0xc0 | (run - 1)))
				run = 0
			}
			h := qoi_hash(r, g, b, a)
			slot := idx[h]
			if slot[0] == r && slot[1] == g && slot[2] == b && slot[3] == a {
				append(&out, u8(h))
			} else {
				idx[h] = [4]u8{r, g, b, a}
				if a == pa {
					vr := int(r) - int(pr)
					vg := int(g) - int(pg)
					vb := int(b) - int(pb)
					vgr := vr - vg
					vgb := vb - vg
					if vr > -3 && vr < 2 && vg > -3 && vg < 2 && vb > -3 && vb < 2 {
						append(&out, u8(0x40 | ((vr + 2) << 4) | ((vg + 2) << 2) | (vb + 2)))
					} else if vgr > -9 && vgr < 8 && vg > -33 && vg < 32 && vgb > -9 && vgb < 8 {
						append(&out, u8(0x80 | (vg + 32)))
						append(&out, u8(((vgr + 8) << 4) | (vgb + 8)))
					} else {
						append(&out, 0xfe, r, g, b)
					}
				} else {
					append(&out, 0xff, r, g, b, a)
				}
			}
		}
		pr, pg, pb, pa = r, g, b, a
	}
	append(&out, 0, 0, 0, 0, 0, 0, 0, 1)
	return out
}
