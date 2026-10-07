// sprite —— 帧动画集合（对位 DragonLib Engine.Rendering.Sprite）。
//
// 一个 Sprite = 若干帧（图集子图 + 时长）+ 若干命名动画（帧区间）。
// 与图集的关联只体现在 Subtexture 上；帧通常来自 aseprite_build 产出的
// Built_Clip（区域名 -> 图集子图）。
package rendering

import "core:math"

import foster "olib:foster"

// 分区：
//   类型 —— 帧 / 动画 / Sprite
//   动画注册 —— add_animation / get_animation
//   采样 —— get_frame_at

// ------------------------------------------------------------------------------
// 类型 —— 帧 / 动画 / Sprite
// ------------------------------------------------------------------------------

// 一帧：可绘制子图 + 停留时长（秒）。
Sprite_Frame :: struct {
	Subtexture: foster.Subtexture,
	Duration:   f32,
}

// 一段命名动画：frames 数组里 [FrameStart, FrameStart+FrameCount) 的帧。
Sprite_Animation :: struct {
	Name:       string,
	FrameStart: int,
	FrameCount: int,
	Duration:   f32, // 区间内帧时长总和（add 时累计）
}

// 包含动画的集合。Name/动画名为克隆字符串，dispose 统一释放。
Sprite :: struct {
	Name:   string,
	Origin: foster.Vec2, // 绘制锚点（像素）

	Frames:     [dynamic]Sprite_Frame,
	Animations: [dynamic]Sprite_Animation,
}

sprite_init :: proc(sprite: ^Sprite, name: string, origin: foster.Vec2 = {}) {
	sprite^ = {
		Name   = clone_owned(name),
		Origin = origin,
	}
}

sprite_dispose :: proc(sprite: ^Sprite) {
	delete(sprite.Name)
	for &anim in sprite.Animations {
		delete(anim.Name)
	}
	delete(sprite.Animations)
	delete(sprite.Frames)
	sprite^ = {}
}

// 追加一帧。
sprite_add_frame :: proc(sprite: ^Sprite, subtexture: foster.Subtexture, duration: f32) {
	append(&sprite.Frames, Sprite_Frame{Subtexture = subtexture, Duration = duration})
}

// ------------------------------------------------------------------------------
// 动画注册 —— add_animation / get_animation
// ------------------------------------------------------------------------------

// 注册一段动画并累计时长。区间越界时只收有效部分。
sprite_add_animation :: proc(sprite: ^Sprite, name: string, frame_start, frame_count: int) {
	if frame_count <= 0 do return

	duration: f32 = 0
	end := min(frame_start + frame_count, len(sprite.Frames))
	for i := max(frame_start, 0); i < end; i += 1 {
		duration += sprite.Frames[i].Duration
	}

	append(&sprite.Animations, Sprite_Animation{
		Name       = clone_owned(name),
		FrameStart = frame_start,
		FrameCount = frame_count,
		Duration   = duration,
	})
}

// 按名字查动画（线性扫描；动画数量级很小）。找不到返回 nil。
sprite_get_animation :: proc(sprite: ^Sprite, name: string) -> ^Sprite_Animation {
	for &anim in sprite.Animations {
		if anim.Name == name do return &anim
	}
	return nil
}

// ------------------------------------------------------------------------------
// 采样 —— get_frame_at
// ------------------------------------------------------------------------------

// 取动画在 second 时刻应显示的帧。
// loop=false 且超出总时长时夹到最后有效帧；loop=true 循环取模。
// 区间帧时长为 0 时兜底返回区间首帧。
sprite_get_frame_at :: proc(sprite: ^Sprite, animation: ^Sprite_Animation, second: f32, loop: bool) -> (Sprite_Frame, bool) {
	if animation == nil || animation.FrameCount <= 0 do return {}, false
	if len(sprite.Frames) == 0 do return {}, false

	end := min(animation.FrameStart + animation.FrameCount, len(sprite.Frames))
	start := max(animation.FrameStart, 0)
	if end <= start do return {}, false

	if second >= animation.Duration && !loop {
		return sprite.Frames[end - 1], true
	}

	t := second
	if animation.Duration > 0 {
		t = math.mod(second, animation.Duration)
	}
	for i := start; i < end; i += 1 {
		t -= sprite.Frames[i].Duration
		if t <= 0 {
			return sprite.Frames[i], true
		}
	}
	return sprite.Frames[start], true
}
