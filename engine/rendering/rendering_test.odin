// rendering 包单元测试（CPU 侧；纹理上传/裁剪需要 GPU，不在此覆盖）。
#+test
package rendering

import "core:testing"

import foster "olib:foster"

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
