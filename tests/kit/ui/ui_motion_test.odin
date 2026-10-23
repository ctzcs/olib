// 状态驱动动效：追随、打断、冲击、回收、进出场与退场输入隔离（全 CPU）。
#+test
package ui

import "core:sync"
import "core:testing"

import clay "olib:thirdparty/clay-odin"

@(private)
MOTION_TEST :: UI_Motion{time = 0.2}

@(private)
motion_test_frame :: proc(ctx: ^UI_Context, target: UI_Visual, declare := true) -> UI_Visual {
	ui_begin(ctx, 1.0 / 60)
	value: UI_Visual
	if declare {
		value = ui_motion(ctx, "motion", target, MOTION_TEST)
	}
	ui_end(ctx)
	return value
}

@(test)
motion_follows_target_and_keeps_velocity_when_interrupted :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)

	rest := UI_VISUAL_DEFAULT
	lift := UI_VISUAL_DEFAULT
	lift.offset = {0, -20}
	first := motion_test_frame(&ctx, rest)
	testing.expect(t, first == rest, "first declaration starts at target")
	testing.expect(t, ctx.visuals[clay.ID("motion").id] == rest)

	value := motion_test_frame(&ctx, lift)
	testing.expectf(t, value.offset.y < 0 && value.offset.y > -20, "y=%v", value.offset.y)
	value = motion_test_frame(&ctx, lift) // 第二帧：仍在加速上升
	_, velocity, ok := ui_motion_state(&ctx, "motion")
	testing.expect(t, ok && velocity.offset.y < 0)
	// 中途改回：保留向上的速度，下一帧仍继续向上一点，不跳变。
	before := value.offset.y
	value = motion_test_frame(&ctx, rest)
	testing.expectf(t, value.offset.y <= before && before - value.offset.y < 5,
		"before=%v after=%v", before, value.offset.y)
	for _ in 0..<60 {
		value = motion_test_frame(&ctx, rest)
	}
	testing.expectf(t, abs(value.offset.y) < 0.01, "y=%v", value.offset.y)
}

@(test)
motion_kick_springs_back_and_undeclared_state_is_dropped :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)

	rest := UI_VISUAL_DEFAULT
	ui_motion_kick(&ctx, "motion", {scale = {-2, -2}}) // 尚无状态：忽略
	motion_test_frame(&ctx, rest)
	ui_motion_kick(&ctx, "motion", {scale = {-2, -2}})
	value := motion_test_frame(&ctx, rest)
	testing.expectf(t, value.scale.x < 1, "kick shrinks first, scale=%v", value.scale)
	for _ in 0..<60 {
		value = motion_test_frame(&ctx, rest)
	}
	testing.expectf(t, abs(value.scale.x - 1) < 0.001, "springs back, scale=%v", value.scale)

	motion_test_frame(&ctx, rest, declare = false)
	_, _, ok := ui_motion_state(&ctx, "motion")
	testing.expect(t, !ok, "state dropped after a frame without declaration")
	fresh := motion_test_frame(&ctx, rest)
	testing.expect(t, fresh == rest)
}

@(private)
presence_test_frame :: proc(ctx: ^UI_Context, open: bool) -> (alive: bool, progress: f32, state: UI_Interaction) {
	ui_begin(ctx, 1.0 / 60)
	alive, progress = ui_presence(ctx, "popup", open, MOTION_TEST, MOTION_TEST)
	if alive {
		state = ui_interact(ctx, "popup-button")
		if clay.UI()(clay.ElementDeclaration{
			id = clay.ID("popup"),
			layout = {sizing = {width = clay.SizingFixed(100), height = clay.SizingFixed(60)},
				padding = clay.PaddingAll(10)},
		}) {
			if clay.UI()(clay.ElementDeclaration{
				id = clay.ID("popup-button"),
				layout = {sizing = {width = clay.SizingFixed(40), height = clay.SizingFixed(20)}},
			}) {}
		}
	}
	ui_end(ctx)
	return
}

@(test)
presence_progress_and_exit_isolates_input :: proc(t: ^testing.T) {
	sync.mutex_lock(&clay_test_mutex)
	defer sync.mutex_unlock(&clay_test_mutex)
	ctx: UI_Context
	testing.expect(t, ui_init(&ctx, 800, 600))
	defer ui_dispose(&ctx)
	ui_set_pointer(&ctx, 20, 20, false)

	alive, progress, _ := presence_test_frame(&ctx, false)
	testing.expect(t, !alive && progress == 0, "closed and never opened: nothing to declare")

	alive, progress, _ = presence_test_frame(&ctx, true)
	testing.expectf(t, alive && progress > 0 && progress < 1, "enter starts from 0, t=%v", progress)
	state: UI_Interaction
	for _ in 0..<30 {
		alive, progress, state = presence_test_frame(&ctx, true)
	}
	testing.expectf(t, progress > 0.99, "t=%v", progress)
	testing.expect(t, state.hovered, "open popup takes pointer")
	testing.expect(t, len(ctx.previous_widgets) == 1)

	alive, progress, _ = presence_test_frame(&ctx, false)
	testing.expect(t, alive && progress < 1)
	alive, _, state = presence_test_frame(&ctx, false)
	testing.expect(t, alive)
	testing.expect(t, !state.hovered && !clay.PointerOver(clay.ID("popup-button")), "exiting subtree is not hit")
	testing.expect(t, len(ctx.previous_widgets) == 0, "exiting subtree is skipped by navigation")
	testing.expect(t, ctx.input.pointer == false)

	frames := 0
	for alive && frames < 120 {
		alive, progress, _ = presence_test_frame(&ctx, false)
		frames += 1
	}
	testing.expect(t, !alive && progress == 0, "exit finishes")
	// 重新打开从 0 开始入场，且可以交互。
	alive, progress, _ = presence_test_frame(&ctx, true)
	testing.expect(t, alive && progress < 0.5)
	alive, progress, state = presence_test_frame(&ctx, true)
	testing.expect(t, state.hovered, "reopened popup is interactive again")
}
