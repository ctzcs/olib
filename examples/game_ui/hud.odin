package main

import "core:fmt"
import "core:math"

import app "olib:kit/app"
import ui "olib:kit/ui"
import foster "olib:foster"
import clay "olib:thirdparty/clay-odin"

// 布局与交互来自 kit/ui；游戏皮肤、道具语义、冷却遮罩属于示例。
skill_names := [6]string{"Riven blade", "Iron vow", "Ember burst", "Moonfall", "Ember flask", "Windstep"}
item_names := [6]string{"WARDEN'S BLADE", "OATHBOUND SHIELD", "CINDER CORE", "MOONGLASS SHARD", "EMBER FLASK", "VERDANT PLUME"}
item_types := [6]string{"WEAPON  /  +24 ATTACK", "ARMOR  /  +18 GUARD", "MATERIAL  /  FIRE", "RARE MATERIAL  /  ARCANE", "CONSUMABLE  /  RESTORE HP", "CHARM  /  +8 AGILITY"}

label :: proc(text: string, size: u16, color: foster.Color) {
	ui.ui_label_ex(&ctx, &theme, text, color, size)
}

anchor :: proc(id: string, x, y, width: f32, height: f32 = 0) -> clay.ElementDeclaration {
	return {
		id = clay.ID(id),
		layout = {
			sizing = {width = clay.SizingFixed(width), height = height > 0 ? clay.SizingFixed(height) : clay.SizingFit({})},
			layoutDirection = .TopToBottom, childGap = 8,
		},
		floating = {attachTo = .Root, offset = {x, y}, zIndex = 10, pointerCaptureMode = .Capture},
	}
}

frame_decl :: proc(id: string, x, y, width: f32, height: f32 = 0) -> clay.ElementDeclaration {
	decl := anchor(id, x, y, width, height)
	decl.layout.padding = clay.PaddingAll(16)
	decl.backgroundColor = ui.ui_clay_color(theme.panel)
	decl.cornerRadius = clay.CornerRadiusAll(18)
	ui.ui_block_pointer(&ctx, id)
	return decl
}

meter :: proc(value, width, height: f32, color: foster.Color) {
	if clay.UI()(clay.ElementDeclaration{
		layout = {sizing = {width = clay.SizingFixed(width), height = clay.SizingFixed(height)}, padding = clay.PaddingAll(2)},
		backgroundColor = {0.025, 0.04, 0.045, 1},
		cornerRadius = clay.CornerRadiusAll(height * 0.5),
	}) {
		if clay.UI()(clay.ElementDeclaration{
			layout = {sizing = {width = clay.SizingFixed((width - 4) * math.clamp(value, 0, 1)), height = clay.SizingFixed(height - 4)}},
			backgroundColor = ui.ui_clay_color(color),
			cornerRadius = clay.CornerRadiusAll((height - 4) * 0.5),
		}) {}
	}
}

badge :: proc(id: string, text: string, bottom: bool) {
	point: clay.FloatingAttachPointType = bottom ? .RightBottom : .LeftTop
	if clay.UI()(clay.ElementDeclaration{
		id = clay.ID(id),
		layout = {padding = clay.PaddingAll(3)},
		backgroundColor = {0.035, 0.045, 0.04, 0.95},
		cornerRadius = clay.CornerRadiusAll(4),
		floating = {attachTo = .Parent, attachment = {element = point, parent = point},
			offset = bottom ? clay.Vector2{-4, -4} : clay.Vector2{4, 4},
			zIndex = 12, pointerCaptureMode = .Passthrough, clipTo = .AttachedParent},
	}) {
		label(text, 11, PAPER)
	}
}

// 图片皮肤作底，图标、数量和冷却遮罩作为子元素叠加。
slot :: proc(id: string, icon: int, size: f32, chosen: bool,
	key, amount: string, cooldown: f32 = 0, fraction: f32 = 0) -> bool {
	state := ui.ui_interact(&ctx, id, {disabled = icon < 0 || cooldown > 0})
	decl := skin_decl(state, chosen, chosen || state.focused ? 14 : 11)
	decl.id = clay.ID(id)
	decl.layout = {sizing = {width = clay.SizingFixed(size), height = clay.SizingFixed(size)},
		childAlignment = {x = .Center, y = .Center}}
	inset: f32 = chosen || state.focused ? 2 : 1
	if clay.UI()(decl) {
		if clay.UI()(clay.ElementDeclaration{
			layout = {sizing = {width = clay.SizingFixed(size - inset * 2),
				height = clay.SizingFixed(size - inset * 2)},
				childAlignment = {x = .Center, y = .Center}},
		}) {
			if icon >= 0 {
				ui.ui_image(&ctx, icon_sub(icon), size - 20, size - 20)
			}
			if cooldown > 0 {
				if clay.UI()(clay.ElementDeclaration{
					id = clay.ID(id, 20),
					layout = {sizing = {width = clay.SizingFixed(size - 8),
						height = clay.SizingFixed((size - 8) * fraction)}},
					backgroundColor = {0.015, 0.025, 0.03, 0.8},
					cornerRadius = clay.CornerRadiusAll(8),
					floating = {attachTo = .Parent, zIndex = 11,
						attachment = {element = .CenterBottom, parent = .CenterBottom},
						offset = {0, -3}, pointerCaptureMode = .Passthrough},
				}) {}
				if clay.UI()(clay.ElementDeclaration{
					id = clay.ID(id, 21),
					floating = {attachTo = .Parent, zIndex = 12,
						attachment = {element = .CenterCenter, parent = .CenterCenter},
						pointerCaptureMode = .Passthrough},
				}) {
					label(fmt.aprintf("%.1f", cooldown, allocator = context.temp_allocator), 18, PAPER)
				}
			}
			if len(key) > 0 {
				badge(fmt.aprintf("%s-key", id, allocator = context.temp_allocator), key, false)
			}
			if len(amount) > 0 {
				badge(fmt.aprintf("%s-qty", id, allocator = context.temp_allocator), amount, true)
			}
		}
	}
	return state.clicked
}

menu_button :: proc(id, text: string, important: bool = false) -> bool {
	state := ui.ui_interact(&ctx, id)
	decl := skin_decl(state, important)
	decl.id = clay.ID(id)
	decl.layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(52)},
		padding = {top = state.active ? 2 : 0}, childAlignment = {x = .Center, y = .Center}}
	if clay.UI()(decl) {
		label(text, 16, PAPER)
	}
	return state.clicked
}

close_button :: proc(id: string) -> bool {
	state := ui.ui_interact(&ctx, id)
	decl := skin_decl(state, border = 9)
	decl.id = clay.ID(id)
	decl.layout = {sizing = {width = clay.SizingFixed(32), height = clay.SizingFixed(32)},
		childAlignment = {x = .Center, y = .Center}}
	if clay.UI()(decl) {
		label("X", 13, PAPER)
	}
	return state.clicked
}

declare_hud :: proc() {
	if clay.UI()(clay.ElementDeclaration{
		layout = {sizing = {width = clay.SizingFixed(ctx.width), height = clay.SizingFixed(ctx.height)}},
	}) {}
	if clay.UI()(anchor("vitals", 28, 26, 338)) {
		if clay.UI()(ui.ui_row_decl(12)) {
			if clay.UI()(clay.ElementDeclaration{
				layout = {padding = clay.PaddingAll(6)}, backgroundColor = {0.07, 0.10, 0.10, 0.95},
				cornerRadius = clay.CornerRadiusAll(16),
			}) {
				ui.ui_image(&ctx, icon_sub(6), 52, 64)
			}
			if clay.UI()(ui.ui_column_decl(6)) {
				label("THE WARDEN    /    LV. 12", 13, GOLD)
				meter(health, 238, 19, {151, 56, 47, 255})
				meter(energy, 218, 12, {55, 123, 140, 255})
				label(fmt.aprintf("%d / 1240 HP     %d / 180 MP", int(health * 1240), int(energy * 180), allocator = context.temp_allocator), 11, PAPER)
			}
		}
	}
	location := anchor("location", ctx.width * 0.5 - 150, 28, 300)
	location.layout.childAlignment.x = .Center
	if clay.UI()(location) {
		label("A S H E N   V A L E", 22, PAPER)
		label("THE SUNKEN SANCTUM", 11, GOLD)
		label("-  DEPTH III  -", 11, MUTED)
	}
	if clay.UI()(anchor("quest", 30, 166, 230)) {
		label("A LIGHT BENEATH", 14, GOLD)
		label("Find the sealed shrine", 17, PAPER)
		label("Collect the scattered sigils", 13, MUTED)
		label("II / III     SIGILS RECOVERED", 11, JADE)
	}
	minimap :=  frame_decl("map", ctx.width - 176, 24, 148)
	minimap.layout.padding = clay.PaddingAll(8)
	minimap.layout.childAlignment.x = .Center
	if clay.UI()(minimap) {
		label("N", 10, GOLD)
		ui.ui_image(&ctx, icon_sub(7), 80, 80)
		label("SANCTUM  /  03", 10, MUTED)
	}
	if bag_open {
		declare_inventory()
	}
	if clay.UI()(anchor("notice", ctx.width * 0.5 - 210, ctx.height - 154, 420)) {
		label(notice, 13, GOLD)
	}
	bar := frame_decl("hotbar", ctx.width * 0.5 - 217, ctx.height - 119, 434)
	bar.layout.padding = clay.PaddingAll(12)
	if clay.UI()(bar) {
		if clay.UI()(ui.ui_row_decl(10)) {
			for i in 0..<6 {
				id := fmt.aprintf("skill-%d", i, allocator = context.temp_allocator)
				key := fmt.aprintf("%d", i + 1, allocator = context.temp_allocator)
				if slot(id, i, 58, i == 0, key, i == 4 ? "3" : "",
					cooldowns[i], cooldowns[i] / cooldown_lengths[i]) {
					activate_skill(i)
				}
			}
		}
	}
	if clay.UI()(anchor("controls", ctx.width * 0.5 - 208, ctx.height - 25, 450)) {
		label("CLICK TO MOVE     1-6 ABILITIES     B INVENTORY", 10, MUTED)
	}
	if clay.UI()(anchor("currency", 30, ctx.height - 76, 240)) {
		label("1,248  GOLD", 18, GOLD)
		label("SANCTUM OF THE FIRST FLAME", 10, MUTED)
	}
	if clay.UI()(anchor("pause-button", ctx.width - 168, ctx.height - 66, 140)) {
		if menu_button("pause-open", "ESC  /  PAUSE") {
			paused = true
		}
	}
	if ctx.modal_id != 0 {
		declare_pause()
	}
}

declare_inventory :: proc() {
	height := min(440, ctx.height - 312)
	panel := frame_decl("inventory", ctx.width - 354, 182, 326, height)
	if clay.UI()(panel) {
		if clay.UI()(ui.ui_row_decl(8)) {
			label("SATCHEL", 24, PAPER)
			ui.ui_spacer()
			if close_button("bag-close") {
				bag_open = false
			}
		}
		label("18 / 24 SLOTS                 23.4 / 40 KG", 11, MUTED)
		ui.ui_separator(&ctx, &theme)
		if clay.UI()(ui.ui_scroll_decl(&ctx, "bag-scroll", height - 212, gap = 8)) {
			for row in 0..<6 {
				if clay.UI()(ui.ui_row_decl(8)) {
					for col in 0..<4 {
						i := row * 4 + col
						id := fmt.aprintf("item-%d", i, allocator = context.temp_allocator)
						amount := i % 3 == 0 ? fmt.aprintf("%d", i + 2, allocator = context.temp_allocator) : ""
						if slot(id, i < 18 ? i % 6 : -1, 62, selected == i, "", i < 18 ? amount : "") {
							selected = i
						}
					}
				}
			}
		}
		ui.ui_separator(&ctx, &theme)
		label(item_names[selected % 6], 16, selected % 6 == 3 ? foster.Color{139, 176, 218, 255} : GOLD)
		label(item_types[selected % 6], 10, MUTED)
		label("Recovered from the old sanctum.", 12, PAPER)
		label("SCROLL TO BROWSE     /     B TO CLOSE", 10, MUTED)
	}
}

declare_pause :: proc() {
	ui.ui_set_scope(&ctx, "pause")
	if clay.UI()(ui.ui_modal_decl(&ctx, "pause")) {
		panel := ui.ui_panel_decl(&theme, 14, 340)
		panel.layout.padding = clay.PaddingAll(28)
		panel.cornerRadius = clay.CornerRadiusAll(22)
		if clay.UI()(panel) {
			label("A S H E N   V A L E", 21, GOLD)
			label(settings ? "SOUND & AMBIENCE" : "JOURNEY PAUSED", 12, MUTED)
			ui.ui_separator(&ctx, &theme)
			if settings {
				label("Master volume", 15, PAPER)
				ui.ui_slider(&ctx, &theme, "volume", &volume, width = 280)
				label("Ambient music", 15, PAPER)
				ui.ui_toggle(&ctx, &theme, "music", &music)
				if menu_button("settings-back", "BACK") {
					settings = false
				}
			} else {
				label("The ruins can wait a little longer.", 13, PAPER)
				if menu_button("resume", "CONTINUE JOURNEY", true) {
					paused = false
				}
				if menu_button("settings", "SOUND & AMBIENCE") {
					settings = true
				}
				if menu_button("quit", "LEAVE THE RUINS") {
					app.game_app_exit(&game)
				}
			}
		}
	}
	ui.ui_set_scope(&ctx, "")
}
