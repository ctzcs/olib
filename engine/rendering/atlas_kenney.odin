// atlas:kenney —— Kenney / Starling 风格 XML 图集来源（对位 DragonLib KenneyXmlAtlasSource）。
//
// 格式：<TextureAtlas><SubTexture name x y width height/>…</TextureAtlas>
// 每个子图额外收一份去掉 ".png" 后缀的别名，调用处写短名更省事。
package rendering

import "core:encoding/xml"
import "core:strconv"
import "core:strings"

import foster "ofoster:."

// 解析 Kenney/Starling XML 坐标（分配于 context.allocator，键随表存活；
// 注入图集后用 kenney_rects_dispose 释放原件）。解析失败返回 nil。
kenney_build_rects :: proc(xml_bytes: []u8) -> ^map[string]foster.RectInt {
	doc, err := xml.parse_bytes(xml_bytes)
	if err != nil || doc == nil do return nil
	defer xml.destroy(doc)

	rects := new(map[string]foster.RectInt)
	rects^ = make(map[string]foster.RectInt)

	// 元素平铺在 doc.elements 里，直接线性扫 SubTexture 即可（不需要树遍历）
	for &el in doc.elements {
		if el.ident != "SubTexture" do continue

		name := ""
		x, y, w, h := 0, 0, 0, 0
		for &attr in el.attribs {
			switch attr.key {
			case "name":   name = attr.val
			case "x":      x = parse_coord(attr.val)
			case "y":      y = parse_coord(attr.val)
			case "width":  w = parse_coord(attr.val)
			case "height": h = parse_coord(attr.val)
			}
		}
		if name == "" do continue

		rect := foster.RectInt{X = x, Y = y, Width = w, Height = h}
		key, _ := strings.clone(name, context.allocator)
		rects[key] = rect
		if strings.has_suffix(name, ".png") {
			alias, _ := strings.clone(name[:len(name) - len(".png")], context.allocator)
			rects[alias] = rect // 去后缀别名
		}
	}

	return rects
}

// 释放 kenney_build_rects 的产出。
kenney_rects_dispose :: proc(rects: ^map[string]foster.RectInt) {
	for key in rects^ {
		delete(key, context.allocator)
	}
	delete(rects^)
	free(rects)
}

@(private)
parse_coord :: proc(s: string) -> int {
	trimmed := strings.trim_space(s)
	v, ok := strconv.parse_int(trimmed)
	if !ok do return 0
	return int(v)
}
