package main

import "core:fmt"
import "core:os"

import app "olib:engine/app"
import ui "olib:engine/ui"
import clay "olib:thirdparty/clay-odin"
import foster "ofoster:."

// 设置 + 滚动背包 + 模态确认；可运行，也可用 shot 参数自动输出验收图。
game: app.Game_App
ctx: ui.UI_Context
theme: ui.UI_Theme
batcher: foster.Batcher
font: foster.MsdfFont
font_texture, icons: foster.Texture
distance_font: foster.MsdfFont
distance_texture: foster.Texture
distance_font_id: int
font_path: string
volume: f32 = 0.65
music: bool = true
dialog: bool
selected: int = -1
world_clicks: int
frame: int
shot, pending: bool
capture: foster.Target
ui_scale: f32 = 1

main :: proc() {
	for arg, i in os.args {
		if arg == "font" && i + 1 < len(os.args) {
			font_path = os.args[i + 1]
		}
	}
	shot = app.has_arg(os.args, "shot")
	dialog = app.has_arg(os.args, "modal")
	if app.has_arg(os.args, "scaled") {
		ui_scale = 1.25
	}
	app.game_app_init(&game, "olib game UI", 1100, 760)
	defer app.game_app_dispose(&game)
	app.game_app_run(&game, startup, update, render, shutdown)
}

startup :: proc(g: ^app.Game_App) {
	if !ui.ui_init(&ctx, 1100, 760) || !bake_font() {
		fmt.eprintln("Font unavailable. Pass: font <path-to-ttf>")
		app.game_app_exit(g)
		return
	}
	theme = ui.UI_THEME_DARK
	foster.BatcherInit(&batcher, &g.GraphicsDevice, "game UI")
	if app.has_arg(os.args, "msdf") {
		distance_font_id = make_distance_probe(&g.GraphicsDevice)
	}
	image := foster.ImageMake(64, 32)
	defer foster.ImageDispose(&image)
	for y in 0..<32 {
		for x in 0..<64 {
			color := x < 32 ? foster.Color{65, 190, 160, 255} : foster.Color{230, 160, 65, 255}
			if (x % 32 < 6 || x % 32 > 25) || y < 6 || y > 25 {
				color = {28, 34, 48, 255}
			}
			foster.ImageSetPixel(&image, x, y, color)
		}
	}
	icons = foster.TextureFromImage(&g.GraphicsDevice, &image, "two inventory icons")
	if shot {
		foster.TargetInit(&capture, &g.GraphicsDevice, 1100, 760)
	}
}

shutdown :: proc(g: ^app.Game_App) {
	foster.BatcherDispose(&batcher)
	ui.ui_dispose(&ctx)
	foster.TextureDispose(&font_texture)
	foster.TextureDispose(&icons)
	foster.MsdfFontDispose(&font)
	foster.TextureDispose(&distance_texture)
	foster.MsdfFontDispose(&distance_font)
	if shot {
		foster.TargetDispose(&capture)
	}
}

update :: proc(g: ^app.Game_App) {
	if foster.KeyboardPressed(&g.Input.State.Keyboard, .Escape) {
		if dialog {
			dialog = false
		} else {
			app.game_app_exit(g)
		}
	}
}

render :: proc(g: ^app.Game_App) {
	target := foster.DrawableTargetFromWindow(&g.Window)
	window_size := foster.Size(&g.Window)
	w, h := f32(target.WidthInPixels), f32(target.HeightInPixels)
	ui.ui_set_viewport(&ctx, {0, 0, w, h}, ui_scale)
	mouse := g.Input.State.Mouse
	ui.ui_set_pointer(&ctx,
		mouse.Position.X * w / f32(max(window_size.X, 1)),
		mouse.Position.Y * h / f32(max(window_size.Y, 1)), foster.MouseDown(&mouse, .Left))
	ui.ui_add_scroll(&ctx, mouse.Wheel.X, mouse.Wheel.Y)
	if shot && app.has_arg(os.args, "scroll") {
		ui.ui_set_pointer(&ctx, 400 * ui_scale, 240 * ui_scale, false)
		if frame == 2 {
			ui.ui_add_scroll(&ctx, 0, -10)
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
	ui.ui_set_modal(&ctx, dialog ? "confirm-dialog" : "")
	ui.ui_begin(&ctx, g.Time.Delta)

	root := ui.ui_column_decl(18)
	root.layout.padding = clay.PaddingAll(28)
	root.layout.sizing.height = clay.SizingGrow({})
	if clay.UI()(root) {
		ui.ui_heading(&ctx, &theme, "GAME UI / FIELD KIT")
		ui.ui_label_dim(&ctx, &theme, "Tab to focus  /  Enter to confirm  /  Arrow keys to adjust  /  Wheel to scroll")
		if clay.UI()(ui.ui_row_decl(24)) {
			panel := ui.ui_panel_decl(&theme, 18, 300)
			panel.id = clay.ID("settings-panel")
			ui.ui_block_pointer(&ctx, "settings-panel")
			if clay.UI()(panel) {
				ui.ui_heading(&ctx, &theme, "Settings")
				ui.ui_label(&ctx, &theme, "Music")
				ui.ui_toggle(&ctx, &theme, "music", &music)
				ui.ui_label(&ctx, &theme, fmt.aprintf("Volume  %d%%", int(volume * 100), allocator = context.temp_allocator))
				ui.ui_slider(&ctx, &theme, "volume", &volume, width = 250)
				ui.ui_separator(&ctx, &theme)
				ui.ui_label(&ctx, &theme, "Health")
				ui.ui_progress_bar(&ctx, &theme, 0.72, 250)
				ui.ui_button(&ctx, &theme, "locked", "Locked action", {disabled = true})
				if ui.ui_button_ex(&ctx, &theme, "reset", "Reset settings", .Primary) {
					dialog = true
				}
			}
			inventory := ui.ui_panel_decl(&theme, 12, 440)
			inventory.id = clay.ID("inventory-panel")
			ui.ui_block_pointer(&ctx, "inventory-panel")
			if clay.UI()(inventory) {
				ui.ui_heading(&ctx, &theme, "Inventory")
				ui.ui_label_dim(&ctx, &theme, "24 items / clipped viewport / atlas icons")
				if clay.UI()(ui.ui_scroll_decl(&ctx, "inventory-scroll", 276, gap = 6)) {
					for i in 0..<24 {
						if clay.UI()(ui.ui_row_decl(12)) {
							id := fmt.aprintf("item-%d", i, allocator = context.temp_allocator)
							sub := foster.SubtextureFromSource(&icons, {f32(i % 2) * 32, 0, 32, 32})
							if ui.ui_image_button(&ctx, &theme, id, sub, 26) {
								selected = i
							}
							ui.ui_label(&ctx, &theme, fmt.aprintf("Supply crate %02d", i + 1, allocator = context.temp_allocator))
						}
					}
				}
				ui.ui_separator(&ctx, &theme)
				ui.ui_label(&ctx, &theme, selected < 0 ? "Select an item" : fmt.aprintf("Selected: crate %02d", selected + 1, allocator = context.temp_allocator))
			}
		}
		ui.ui_label_dim(&ctx, &theme, fmt.aprintf("World clicks outside panels: %d", world_clicks, allocator = context.temp_allocator))
		if app.has_arg(os.args, "msdf") {
			ui.ui_label_dim(&ctx, &theme, "Distance field shader: same ring at 18 / 36 / 72px")
			if clay.UI()(ui.ui_row_decl(24)) {
				distance_theme := theme
				distance_theme.body_font_id = u16(distance_font_id)
				ui.ui_label_ex(&ctx, &distance_theme, "O", theme.text, 18)
				ui.ui_label_ex(&ctx, &distance_theme, "O", theme.text, 36)
				ui.ui_label_ex(&ctx, &distance_theme, "O", theme.text, 72)
			}
		}
	}
	// 使用本帧开头的 modal_id，保证弹窗显示与交互隔离在同一帧切换。
	if ctx.modal_id != 0 {
		ui.ui_set_scope(&ctx, "confirm-dialog")
		if clay.UI()(ui.ui_modal_decl(&ctx, "confirm-dialog")) {
			if clay.UI()(ui.ui_panel_decl(&theme, 18, 360)) {
				ui.ui_heading(&ctx, &theme, "Reset settings?")
				ui.ui_label(&ctx, &theme, "Music and volume will return to defaults.")
				if clay.UI()(ui.ui_row_decl(12)) {
					if ui.ui_button_ex(&ctx, &theme, "confirm-reset", "Reset", .Primary) {
						volume = 0.65
						music = true
						dialog = false
					}
					if ui.ui_button(&ctx, &theme, "cancel-reset", "Cancel") {
						dialog = false
					}
				}
			}
		}
		ui.ui_set_scope(&ctx, "")
	}
	foster.BatcherClear(&batcher)
	ui.ui_draw(&ctx, &batcher)
	if !ui.ui_input_capture(&ctx).pointer && foster.MousePressed(&mouse, .Left) {
		world_clicks += 1
	}
	foster.GraphicsDeviceClear(&g.GraphicsDevice, target, theme.window_bg)
	foster.BatcherRender(&batcher, target)
	frame += 1
	if shot && pending {
		save_capture()
		fmt.printf("UI diagnostics: errors=%d, pool_overflow=%v\n", ctx.error_count, ctx.pool_overflow)
		app.game_app_exit(g)
	} else if shot && frame >= 10 {
		offscreen := foster.DrawableTargetFromTarget(&capture)
		foster.GraphicsDeviceClear(&g.GraphicsDevice, offscreen, theme.window_bg)
		foster.BatcherRender(&batcher, offscreen)
		pending = true
	}
}

save_capture :: proc() {
	bytes := foster.TextureDownloadData(foster.TargetAttachment(&capture, 0))
	defer delete(bytes)
	image := foster.ImageMake(1100, 760)
	defer foster.ImageDispose(&image)
	if len(bytes) < 1100 * 760 * 4 {
		fmt.eprintln("Capture readback failed")
		return
	}
	for &pixel, i in image.Pixels {
		pixel = {bytes[i * 4], bytes[i * 4 + 1], bytes[i * 4 + 2], bytes[i * 4 + 3]}
	}
	name := app.has_arg(os.args, "modal") ? "game_ui_modal.png" : app.has_arg(os.args, "scaled") ? "game_ui_scaled.png" : app.has_arg(os.args, "msdf") ? "game_ui_msdf.png" : app.has_arg(os.args, "scroll") ? "game_ui_scroll.png" : "game_ui.png"
	fmt.println(name, foster.ImageWritePng(&image, name))
}
