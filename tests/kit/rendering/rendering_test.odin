// rendering 包单元测试（CPU 侧；纹理上传/裁剪需要 GPU，不在此覆盖）。
#+test
package rendering

import "core:testing"

import foster "olib:foster"

@(test)
sprite_material_vertices_preserve_trim_atlas_and_origin :: proc(t: ^testing.T) {
	texture := foster.Texture{Width = 256, Height = 128}
	frame := foster.SubtextureMake(&texture, {64, 32, 32, 16}, {-4, -6, 48, 32})
	vertices := sprite_vertices(frame, {24, 16}, {2, 0, 0, 3, 100, 50})
	testing.expect_value(t, vertices[0].position, [2]f32{60, 20})
	testing.expect_value(t, vertices[2].position, [2]f32{124, 68})
	testing.expect_value(t, vertices[0].uv, [2]f32{0.25, 0.25})
	testing.expect_value(t, vertices[2].uv, [2]f32{0.375, 0.375})
}

// ---------------------------------------------------------------------------
// Grid 图集来源
// ---------------------------------------------------------------------------

@(test)
grid_build_rects_cells :: proc(t: ^testing.T) {
	rects := grid_build_rects(64, 32, 16, 16) // 4 列 x 2 行
	defer grid_rects_dispose(rects)

	testing.expectf(t, len(rects^) == 8, "应有 8 格: %d", len(rects^))

	r0c0, ok0 := atlas_key(rects, "r0_c0")
	testing.expect(t, ok0 && r0c0 == foster.RectInt{0, 0, 16, 16})
	r0c3, ok3 := atlas_key(rects, "r0_c3")
	testing.expect(t, ok3 && r0c3 == foster.RectInt{48, 0, 16, 16})
	r1c1, ok1 := atlas_key(rects, "r1_c1")
	testing.expect(t, ok1 && r1c1 == foster.RectInt{16, 16, 16, 16})

	_, missing := atlas_key(rects, "r2_c0") // 只有两行
	testing.expect(t, !missing)
}

@(private)
atlas_key :: proc(rects: ^map[string]foster.RectInt, name: string) -> (foster.RectInt, bool) {
	rect, ok := rects^[name]
	return rect, ok
}

// ---------------------------------------------------------------------------
// Kenney XML 来源
// ---------------------------------------------------------------------------

@(private)
KENNEY_XML :: `
<TextureAtlas imagePath="sheet.png">
	<SubTexture name="player_idle0.png" x="0" y="0" width="16" height="24"/>
	<SubTexture name="player_idle1.png" x="16" y="0" width="16" height="24"/>
	<SubTexture name="coin" x="32" y="0" width="8" height="8"/>
</TextureAtlas>
`

@(test)
kenney_build_rects_parse :: proc(t: ^testing.T) {
	xml_const := KENNEY_XML
	rects := kenney_build_rects(transmute([]u8)xml_const)
	defer kenney_rects_dispose(rects)

	testing.expectf(t, rects != nil, "解析失败")
	testing.expectf(t, len(rects^) == 5, "3 子图 + 2 个去 .png 别名: %d", len(rects^))

	full, ok_full := atlas_key(rects, "player_idle0.png")
	testing.expect(t, ok_full && full == foster.RectInt{0, 0, 16, 24})

	alias, ok_alias := atlas_key(rects, "player_idle0") // 去后缀别名
	testing.expect(t, ok_alias && alias == foster.RectInt{0, 0, 16, 24})

	coin, ok_coin := atlas_key(rects, "coin") // 无后缀只有本名
	testing.expect(t, ok_coin && coin == foster.RectInt{32, 0, 8, 8})

	_, nope := atlas_key(rects, "absent")
	testing.expect(t, !nope)
}

// ---------------------------------------------------------------------------
// 图集绘制坐标与默认图标目录
// ---------------------------------------------------------------------------

// 图集中的偏移只能影响 UV，不能把图标顶点移到本地原点之外。
@(test)
atlas_subtexture_uses_local_origin :: proc(t: ^testing.T) {
	atlas: Sprite_Atlas
	atlas.rects = make(map[string]foster.RectInt)
	defer delete(atlas.rects)
	atlas.rects["ui/test"] = {X = 266, Y = 398, Width = 128, Height = 128}
	atlas.texture.Width = 4096
	atlas.texture.Height = 4096

	_, before_upload := atlas_subtexture(&atlas, "ui/test")
	testing.expect(t, !before_upload)
	// 这里只构造纹理尺寸元数据，不创建 GPU 资源。
	atlas.has_upload = true
	sub, ok := atlas_subtexture(&atlas, "ui/test")
	testing.expect(t, ok && sub.Texture == &atlas.texture)
	testing.expect(t, sub.Frame == foster.Rect{0, 0, 128, 128})
	testing.expect(t, sub.DrawCoords[0] == foster.Vec2{0, 0})
	testing.expect(t, sub.DrawCoords[2] == foster.Vec2{128, 128})
	testing.expect(t, sub.TexCoords[0] == foster.Vec2{266.0 / 4096, 398.0 / 4096})
	testing.expect(t, sub.TexCoords[2] == foster.Vec2{394.0 / 4096, 526.0 / 4096})
	_, missing := atlas_subtexture(&atlas, "missing")
	testing.expect(t, !missing)
}

@(test)
builtin_icons_catalog_bounds :: proc(t: ^testing.T) {
	rects := kenney_build_rects(#load("../../../assets/icons/game-icons.xml"))
	if !testing.expect(t, rects != nil) do return
	defer kenney_rects_dispose(rects)
	testing.expectf(t, len(rects^) == 815, "默认图标应有 815 张，实际 %d", len(rects^))
	for name, rect in rects^ {
		testing.expectf(t, rect.Width == 128 && rect.Height == 128,
			"%s 必须保留原始 128px 留白", name)
		testing.expectf(t, rect.X >= 2 && rect.Y >= 2 &&
			rect.X + rect.Width + 2 <= 4096 && rect.Y + rect.Height + 2 <= 4096,
			"%s 超出图集或缺少采样隔离", name)
	}
	testing.expect(t, "game/action-points" in rects^)
}

// ---------------------------------------------------------------------------
// Sprite 动画采样
// ---------------------------------------------------------------------------

@(test)
sprite_get_frame_at_walks :: proc(t: ^testing.T) {
	sprite: Sprite
	sprite_init(&sprite, "coin")
	defer sprite_dispose(&sprite)

	// 3 帧：0.1s / 0.2s / 0.3s，动画覆盖全部
	durations := [3]f32{0.1, 0.2, 0.3}
	for i in 0..<3 {
		sprite_add_frame(&sprite, foster.SubtextureEmpty, durations[i])
	}
	sprite_add_animation(&sprite, "spin", 0, 3)

	anim := sprite_get_animation(&sprite, "spin")
	if !testing.expectf(t, anim != nil, "应找到动画") { return }
	testing.expectf(t, anim.Duration == 0.6, "总时长 0.6: %v", anim.Duration)

	// 各帧中点采样
	cases := [3]f32{0.05, 0.2, 0.45}
	for i in 0..<3 {
		frame, ok := sprite_get_frame_at(&sprite, anim, cases[i], true)
		index := frame_duration_index(durations, frame.Duration)
		testing.expectf(t, ok && index == i, "t=%v 应命中帧 %d, 实际 %d", cases[i], i, index)
	}

	// loop：循环回绕到第 0 帧
	wrap, ok := sprite_get_frame_at(&sprite, anim, 0.65, true)
	testing.expect(t, ok && wrap.Duration == durations[0])

	// 不循环：超出夹到最后帧
	clamp, ok2 := sprite_get_frame_at(&sprite, anim, 99, false)
	testing.expect(t, ok2 && clamp.Duration == durations[2])

	// 未知动画名
	testing.expect(t, sprite_get_animation(&sprite, "nope") == nil)
}

@(private)
frame_duration_index :: proc(durations: [3]f32, d: f32) -> int {
	for i in 0..<3 {
		if durations[i] == d do return i
	}
	return -1
}

// ---------------------------------------------------------------------------
// Aseprite slug 与 tag 展开
// ---------------------------------------------------------------------------

@(test)
aseprite_slug_cleans_names :: proc(t: ^testing.T) {
	cases := [][2]string{
		{"Hero Idle", "hero_idle"},
		{"player-2.WALK!!", "player_2_walk"},
		{"  _leading", "leading"},
		{"trailing__", "trailing"},
		{"MiXeD CaSe", "mixed_case"},
	}
	for tc in cases {
		slug := aseprite_slug(tc[0])
		defer delete(slug)
		testing.expectf(t, slug == tc[1], "slug(%q) = %q, want %q", tc[0], slug, tc[1])
	}
}

@(test)
aseprite_expand_tag_variants :: proc(t: ^testing.T) {
	regions := []string{"a", "b", "c"}
	durations := []f32{0.1, 0.1, 0.1}

	fwd, fwd_d := aseprite_expand_tag(regions, durations, 0, 2, .Forward)
	defer delete(fwd)
	defer delete(fwd_d)
	testing.expect(t, len(fwd) == 3 && fwd[0] == "a")

	rev, rev_d := aseprite_expand_tag(regions, durations, 0, 2, .Reverse)
	defer delete(rev)
	defer delete(rev_d)
	testing.expect(t, len(rev) == 3 && rev[0] == "c" && rev[2] == "a")

	pp, pp_d := aseprite_expand_tag(regions, durations, 0, 2, .PingPong)
	defer delete(pp)
	defer delete(pp_d)
	// a b c -> a b c b
	testing.expectf(t, len(pp) == 4 && pp[0] == "a" && pp[2] == "c" && pp[3] == "b",
		"PingPong 应展开为 a b c b: %v", pp)
	testing.expect(t, len(pp_d) == 4)

	ppr, _ := aseprite_expand_tag(regions, durations, 0, 2, .PingPongReverse)
	defer delete(ppr)
	// 反转后 c b a -> c b a b
	testing.expectf(t, len(ppr) == 4 && ppr[0] == "c" && ppr[3] == "b",
		"PingPongReverse 应展开为 c b a b: %v", ppr)

	// 越界区间被钳制
	oob, _ := aseprite_expand_tag(regions, durations, 1, 99, .Forward)
	defer delete(oob)
	testing.expect(t, len(oob) == 2 && oob[0] == "b" && oob[1] == "c")
}
