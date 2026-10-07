package main

import "core:fmt"
import "core:math"
import "core:os"

import app "olib:kit/app"
import ui "olib:kit/ui"
import foster "olib:foster"
import clay "olib:thirdparty/clay-odin"

// 遗迹探索 HUD；旧控件验收页保留在 examples/ui_gallery。
VIEW_W :: 1280
VIEW_H :: 800
game: app.Game_App
ctx: ui.UI_Context
theme: ui.UI_Theme
batcher: foster.Batcher
font: foster.MsdfFont
font_texture, icons, button_skin: foster.Texture
font_path: string
volume: f32 = 0.65
music: bool = true
paused, settings: bool
bag_open: bool = true
selected: int = 3
frame: int
shot, pending, smoke: bool
capture: foster.Target
ui_scale: f32 = 1
health: f32 = 0.78
energy: f32 = 0.64
elapsed: f32
cooldowns: [6]f32 = {0, 0, 0, 3.8, 0, 0}
cooldown_lengths := [6]f32{1.2, 3, 5, 8, 4, 6}
player := foster.Vec2{564, 422}
destination := foster.Vec2{564, 422}
effect_timer: f32
notice: string = "A forgotten oath still echoes here."

main :: proc() {
	for arg, i in os.args {
		if arg == "font" && i + 1 < len(os.args) {
			font_path = os.args[i + 1]
		}
	}
	smoke = app.has_arg(os.args, "smoke")
	shot = app.has_arg(os.args, "shot") || smoke
	paused = app.has_arg(os.args, "modal")
	bag_open = !app.has_arg(os.args, "hud")
	if app.has_arg(os.args, "scaled") {
		ui_scale = 1.25
	}
	app.game_app_init(&game, "ASHEN VALE - game UI", VIEW_W, VIEW_H)
	defer app.game_app_dispose(&game)
	app.game_app_run(&game, startup, update, render, shutdown)
}

startup :: proc(g: ^foster.App) {
	if !ui.ui_init(&ctx, VIEW_W, VIEW_H) || !bake_font() {
		fmt.eprintln("Font unavailable. Pass: font <path-to-ttf>")
		foster.Exit(g)
		return
	}
	theme = ui.UI_THEME_DARK
	theme.panel = {20, 29, 33, 248}
	theme.panel_border = {51, 66, 69, 255}
	theme.button = {44, 62, 68, 255}
	theme.button_hover = {65, 89, 94, 255}
	theme.button_press = {29, 43, 48, 255}
	theme.primary = {137, 106, 57, 255}
	theme.primary_hover = {140, 112, 58, 255}
	theme.primary_press = {83, 65, 37, 255}
	theme.accent = GOLD
	theme.text = PAPER
	theme.text_dim = MUTED
	theme.corner_radius = 12
	theme.padding = 8
	theme.heading_font_size = 25
	theme.body_font_size = 16
	theme.small_font_size = 12
	foster.BatcherInit(&batcher, &g.GraphicsDevice, "ruins and HUD")
	make_icons(&g.GraphicsDevice)
	make_button_skin(&g.GraphicsDevice)
	if shot {
		foster.TargetInit(&capture, &g.GraphicsDevice, VIEW_W, VIEW_H)
	}
}

shutdown :: proc(g: ^foster.App) {
	foster.BatcherDispose(&batcher)
	ui.ui_dispose(&ctx)
	foster.TextureDispose(&font_texture)
	foster.TextureDispose(&icons)
	foster.TextureDispose(&button_skin)
	foster.MsdfFontDispose(&font)
	if shot {
		foster.TargetDispose(&capture)
	}
}

update :: proc(g: ^foster.App) {
	if foster.KeyboardPressed(&g.Input.State.Keyboard, .Escape) {
		paused = !paused
		settings = false
	}
	if paused {
		return
	}
	dt := shot ? f32(1.0 / 60) : min(g.Time.Delta, 0.1)
	elapsed += dt
	effect_timer = max(0, effect_timer - dt)
	for &cooldown in cooldowns {
		cooldown = max(0, cooldown - dt)
	}
	delta := destination - player
	distance := math.sqrt(delta.x * delta.x + delta.y * delta.y)
	if distance > 2 {
		player += delta / distance * min(distance, dt * 135)
	}
}

activate_skill :: proc(index: int) {
	if paused || cooldowns[index] > 0 {
		return
	}
	cooldowns[index] = cooldown_lengths[index]
	effect_timer = 0.8
	if index == 4 {
		health = min(1, health + 0.18)
		notice = "Ember flask restored your vitality."
	} else {
		energy = max(0.12, energy - 0.035)
		notice = skill_names[index]
	}
}

render :: proc(g: ^foster.App) {
	target := foster.DrawableTargetFromWindow(&g.Window)
	window_size := foster.Size(&g.Window)
	w, h := f32(target.WidthInPixels), f32(target.HeightInPixels)
	fit := min(w / VIEW_W, h / VIEW_H)
	origin := foster.Vec2{(w - VIEW_W * fit) * 0.5, (h - VIEW_H * fit) * 0.5}
	ui.ui_set_viewport(&ctx, {origin.x, origin.y, VIEW_W * fit, VIEW_H * fit}, fit * ui_scale)
	mouse := g.Input.State.Mouse
	mx := mouse.Position.X * w / f32(max(window_size.X, 1))
	my := mouse.Position.Y * h / f32(max(window_size.Y, 1))
	ui.ui_set_pointer(&ctx, mx, my, foster.MouseDown(&mouse, .Left))
	ui.ui_add_scroll(&ctx, mouse.Wheel.X, mouse.Wheel.Y)
	if shot && app.has_arg(os.args, "scroll") {
		ui.ui_set_pointer(&ctx, (ctx.width - 140) * fit * ui_scale, 310 * fit * ui_scale, false)
		if frame == 2 {
			ui.ui_add_scroll(&ctx, 0, -12)
		}
	}
	keyboard := &g.Input.State.Keyboard
	nav: ui.UI_Navigation
	if foster.KeyboardPressed(keyboard, .Tab) {
		nav.next = foster.KeyboardDown(keyboard, .LeftShift) ? -1 : 1
	}
	nav.activate = foster.KeyboardPressed(keyboard, .Enter)
	nav.adjust = f32(int(foster.PressedOrRepeated(keyboard, .Right)) - int(foster.PressedOrRepeated(keyboard, .Left)))
	ui.ui_set_navigation(&ctx, nav)
	if smoke {
		smoke_input()
	}
	ui.ui_set_modal(&ctx, paused ? "pause" : "")
	ui.ui_begin(&ctx, g.Time.Delta)
	declare_hud()
	foster.BatcherClear(&batcher)
	foster.BatcherPushMatrixTRS(&batcher, origin, {fit, fit}, 0, false)
	foster.BatcherPushMode(&batcher, .Fill)
	draw_world()
	foster.BatcherPopMode(&batcher)
	foster.BatcherPopMatrix(&batcher)
	ui.ui_draw(&ctx, &batcher)
	consumed := ui.ui_input_capture(&ctx)
	if !paused && !consumed.keyboard {
		if foster.KeyboardPressed(keyboard, .B) {
			bag_open = !bag_open
		}
		for key, i in ([6]foster.Keys{.D1, .D2, .D3, .D4, .D5, .D6}) {
			if foster.KeyboardPressed(keyboard, key) {
				activate_skill(i)
			}
		}
	}
	if !paused && !consumed.pointer && foster.MousePressed(&mouse, .Left) {
		destination = {math.clamp((mx - origin.x) / fit, 250, 840),
			math.clamp((my - origin.y) / fit, 265, 600)}
	}
	foster.GraphicsDeviceClear(&g.GraphicsDevice, target, {8, 14, 18, 255})
	foster.BatcherRender(&batcher, target)
	frame += 1
	if shot && pending {
		save_capture()
		fmt.printf("UI diagnostics: errors=%d, pool_overflow=%v\n", ctx.error_count, ctx.pool_overflow)
		foster.Exit(g)
	} else if shot && frame >= (smoke ? 23 : 10) {
		offscreen := foster.DrawableTargetFromTarget(&capture)
		foster.GraphicsDeviceClear(&g.GraphicsDevice, offscreen, {8, 14, 18, 255})
		foster.BatcherRender(&batcher, offscreen)
		pending = true
	}
}

// 可复现的交互验收：通过真实布局包围盒驱动按下/松开，不直接修改被测状态。
smoke_input :: proc() {
	id: string
	down := false
	switch frame {
	case 1, 2:
		id = "skill-0"
		down = frame == 1
	case 3, 4:
		assert(cooldowns[0] > 0, "skill click must start cooldown")
		id = "item-2"
		down = frame == 3
	case 5, 6:
		assert(selected == 2, "inventory click must select an item")
		id = "pause-open"
		down = frame == 5
	case 8, 9:
		assert(paused, "pause button must open modal")
		id = "settings"
		down = frame == 8
	case 11, 12:
		assert(settings, "settings menu must open")
		id = "volume"
		down = frame == 11
	case 13, 14:
		assert(volume > 0.85, "slider must respond to drag")
		id = "music"
		down = frame == 13
	case 15, 16:
		assert(!music, "music toggle must respond on release")
		id = "settings-back"
		down = frame == 15
	case 18, 19:
		assert(!settings, "back must return to pause menu")
		id = "resume"
		down = frame == 18
	case 20:
		assert(!paused, "resume must leave modal")
		fmt.println("Game UI smoke passed: skill, inventory, pause, slider, toggle, back, resume")
	}
	ui.ui_set_pointer(&ctx, -100, -100, false)
	if len(id) > 0 {
		data := clay.GetElementData(clay.ID(id))
		assert(data.found, "smoke target must exist")
		box := data.boundingBox
		x := box.x + box.width * (id == "volume" ? 0.92 : 0.5)
		y := box.y + box.height * 0.5
		ui.ui_set_pointer(&ctx, x * ctx.scale + ctx.viewport_origin.x,
			y * ctx.scale + ctx.viewport_origin.y, down)
	}
}

save_capture :: proc() {
	bytes := foster.TextureDownloadData(foster.TargetAttachment(&capture, 0))
	defer delete(bytes)
	image := foster.ImageMake(VIEW_W, VIEW_H)
	defer foster.ImageDispose(&image)
	if len(bytes) < VIEW_W * VIEW_H * 4 {
		fmt.eprintln("Capture readback failed")
		return
	}
	for &pixel, i in image.Pixels {
		pixel = {bytes[i * 4], bytes[i * 4 + 1], bytes[i * 4 + 2], bytes[i * 4 + 3]}
	}
	name := paused ? "game_ui_modal.png" : app.has_arg(os.args, "scaled") ? "game_ui_scaled.png" : !bag_open ? "game_ui_hud.png" : app.has_arg(os.args, "scroll") ? "game_ui_scroll.png" : "game_ui.png"
	fmt.println(name, foster.ImageWritePng(&image, name))
}
