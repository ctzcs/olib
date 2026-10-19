// animation_set —— 帧动画集合（对位 DragonLib Engine.Rendering.Sprite）。
//
// 一个 Animation_Set = 若干帧（图集子图 + 时长）+ 若干命名动画（帧区间）。
// 与图集的关联只体现在 Subtexture 上；帧通常来自 aseprite_build 产出的
// Built_Clip（区域名 -> 图集子图）。
package rendering2d

import "core:math"

import foster "olib:foster"

// 分区：
//   类型 —— 帧 / 动画 / Animation_Set
//   动画注册 —— add_animation / get_animation
//   采样 —— get_frame_at

// ------------------------------------------------------------------------------
// 类型 —— 帧 / 动画 / Animation_Set
// ------------------------------------------------------------------------------

// 一帧：可绘制子图 + 停留时长（秒）。
Animation_Frame :: struct {
	subtexture: foster.Subtexture,
	duration:   f32,
}

// 一段命名动画：frames 数组里 [frame_start, frame_start+frame_count) 的帧。
Animation :: struct {
	name:        string,
	frame_start: int,
	frame_count: int,
	duration:    f32, // 区间内帧时长总和（add 时累计）
}

// 包含动画的集合。名称与动画名为克隆字符串，dispose 统一释放。
Animation_Set :: struct {
	name:   string,
	origin: foster.Vec2, // 绘制锚点（像素）

	frames:     [dynamic]Animation_Frame,
	animations: [dynamic]Animation,
}

animation_set_init :: proc(sprite: ^Animation_Set, name: string, origin: foster.Vec2 = {}) {
	sprite^ = {
		name   = clone_owned(name),
		origin = origin,
	}
}

animation_set_dispose :: proc(sprite: ^Animation_Set) {
	delete(sprite.name)
	for &anim in sprite.animations {
		delete(anim.name)
	}
	delete(sprite.animations)
	delete(sprite.frames)
	sprite^ = {}
}

// 追加一帧。
animation_set_add_frame :: proc(sprite: ^Animation_Set, subtexture: foster.Subtexture, duration: f32) {
	append(&sprite.frames, Animation_Frame{subtexture = subtexture, duration = duration})
}

// ------------------------------------------------------------------------------
// 动画注册 —— add_animation / get_animation
// ------------------------------------------------------------------------------

// 注册一段动画并累计时长。区间越界时只收有效部分。
animation_set_add_animation :: proc(sprite: ^Animation_Set, name: string, frame_start, frame_count: int) {
	if frame_count <= 0 do return

	duration: f32 = 0
	end := min(frame_start + frame_count, len(sprite.frames))
	for i := max(frame_start, 0); i < end; i += 1 {
		duration += sprite.frames[i].duration
	}

	append(&sprite.animations, Animation{
		name        = clone_owned(name),
		frame_start = frame_start,
		frame_count = frame_count,
		duration    = duration,
	})
}

// 按名字查动画（线性扫描；动画数量级很小）。找不到返回 nil。
animation_set_get_animation :: proc(sprite: ^Animation_Set, name: string) -> ^Animation {
	for &anim in sprite.animations {
		if anim.name == name do return &anim
	}
	return nil
}

// ------------------------------------------------------------------------------
// 采样 —— get_frame_at
// ------------------------------------------------------------------------------

// 取动画在 second 时刻应显示的帧。
// loop=false 且超出总时长时夹到最后有效帧；loop=true 循环取模。
// 区间帧时长为 0 时兜底返回区间首帧。
animation_set_get_frame_at :: proc(sprite: ^Animation_Set, animation: ^Animation, second: f32, loop: bool) -> (Animation_Frame, bool) {
	if animation == nil || animation.frame_count <= 0 do return {}, false
	if len(sprite.frames) == 0 do return {}, false

	end := min(animation.frame_start + animation.frame_count, len(sprite.frames))
	start := max(animation.frame_start, 0)
	if end <= start do return {}, false

	if second >= animation.duration && !loop {
		return sprite.frames[end - 1], true
	}

	t := second
	if animation.duration > 0 {
		t = math.mod(second, animation.duration)
	}
	for i := start; i < end; i += 1 {
		t -= sprite.frames[i].duration
		if t <= 0 {
			return sprite.frames[i], true
		}
	}
	return sprite.frames[start], true
}
