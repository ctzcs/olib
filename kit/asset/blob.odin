// blob 是 Importer 与 Runtime 的边界格式：
//
//   Assets/ 的源文件 --(Importer)--> Library/<guid>.blob --(Runtime Loader)--> 游戏对象
//
// Importer 认识 png/qoi/json 等源格式并产出 blob；Runtime 只认识 blob，
// 完全不知道源文件的存在。将来的 pak 只是把 "按 guid 读一个 blob" 换成
// "按 pak 索引读一段偏移"，本格式不需要变化。
//
// 数值一律小端（v1 与宿主一致，x86/ARM 原生目标均为 LE）。
package asset


BLOB_MAGIC :: [8]u8{ 'O', 'L', 'A', 'S', 'B', 'L', 'O', 'B' }

// blob 格式版本（header 布局变化时 +1；v1 读取端精确匹配）。
BLOB_VERSION :: u32(1)

// Texture payload 的像素格式编号（v1 只有 RGBA8 一种）。
TEXTURE_FORMAT_RGBA8 :: u32(0)

// blob 头：importer_version 用于缓存失效——即使源文件 mtime/size 都没变，
// 只要导入逻辑升级（版本号变化），旧 blob 也会被判定过期而重新导入。
Blob_Header :: struct #packed {
	magic:            [8]u8,
	version:          u32,
	importer_version: u32,
	kind:             u8, // Asset_Kind 的底层值
	_pad:             [3]u8,
	guid:             [16]u8,
	payload_len:      u32,
	src_mtime:        i64, // 源文件 mtime（unix 纳秒），仅作新鲜度比对
	src_size:         i64, // 源文件字节数，仅作新鲜度比对
}

// Texture payload 的迷你头，其后紧跟 width*height*4 字节 RGBA8 像素。
// Json / Raw 的 payload 没有迷你头（utf8 / 原样字节）。
Blob_Texture_Header :: struct #packed {
	width:  u32,
	height: u32,
	format: u32,
}

// 组装一个完整 blob（header + payload 一次性分配）。
// payload 生命周期归调用方；返回的 buf 用 allocator 释放。
blob_build :: proc(
	guid:             Guid,
	kind:             Asset_Kind,
	importer_version: u32,
	src_mtime:        i64,
	src_size:         i64,
	payload:          []u8,
	allocator := context.allocator,
) -> (buf: []u8, ok: bool) {
	total := size_of(Blob_Header) + len(payload)
	data, err := make([]u8, total, allocator)
	if err != .None do return nil, false

	h := (^Blob_Header)(&data[0])
	h^ = Blob_Header{
		magic            = BLOB_MAGIC,
		version          = BLOB_VERSION,
		importer_version = importer_version,
		kind             = u8(kind),
		guid             = cast([16]u8)guid,
		payload_len      = u32(len(payload)),
		src_mtime        = src_mtime,
		src_size         = src_size,
	}
	copy(data[size_of(Blob_Header):], payload)
	return data, true
}

// 解析校验 blob：返回指向 data 内部的 header 与 payload 切片（零拷贝）。
// magic / version / payload_len 任一不符都判失败。
blob_parse :: proc(data: []u8) -> (header: ^Blob_Header, payload: []u8, ok: bool) {
	if len(data) < size_of(Blob_Header) do return nil, nil, false
	h := (^Blob_Header)(&data[0])
	if h.magic != BLOB_MAGIC do return nil, nil, false
	if h.version != BLOB_VERSION do return nil, nil, false
	end := size_of(Blob_Header) + int(h.payload_len)
	if end > len(data) do return nil, nil, false
	return h, data[size_of(Blob_Header):end], true
}

// Texture 专用：把 Importer 产出的像素（builder.data）打包成带迷你头的 payload。
blob_payload_texture :: proc(builder: ^Payload_Builder, allocator := context.allocator) -> (payload: []u8, ok: bool) {
	body := size_of(Blob_Texture_Header) + len(builder.data)
	data, err := make([]u8, body, allocator)
	if err != .None do return nil, false
	th := (^Blob_Texture_Header)(&data[0])
	th^ = Blob_Texture_Header{
		width  = builder.width,
		height = builder.height,
		format = builder.format,
	}
	copy(data[size_of(Blob_Texture_Header):], builder.data)
	return data, true
}

// Texture 专用：从 payload 拆出像素切片（视图，指向 payload 内部，不拷贝）。
blob_texture_parse :: proc(payload: []u8) -> (w, h, format: u32, pixels: []u8, ok: bool) {
	if len(payload) < size_of(Blob_Texture_Header) do return 0, 0, 0, nil, false
	th := (^Blob_Texture_Header)(&payload[0])
	if th.width == 0 || th.height == 0 do return 0, 0, 0, nil, false
	pixels = payload[size_of(Blob_Texture_Header):]
	if len(pixels) != int(th.width) * int(th.height) * 4 do return 0, 0, 0, nil, false
	return th.width, th.height, th.format, pixels, true
}
