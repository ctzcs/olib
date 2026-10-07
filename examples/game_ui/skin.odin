package main

import ui "olib:engine/ui"
import clay "olib:thirdparty/clay-odin"
import foster "ofoster:."

// PNG 编译时嵌入，运行目录不影响资源加载。仅转换上传所需的预乘 alpha。
make_button_skin :: proc(device: ^foster.GraphicsDevice) {
	image := foster.ImageFromEncoded(transmute([]u8)#load("assets/button-skin.png"))
	defer foster.ImageDispose(&image)
	assert(image.Width > 0 && image.Height > 0, "button skin PNG failed to decode")
	foster.ImagePremultiply(&image)
	button_skin = foster.TextureFromImage(device, &image, "bronze and leather button skin")
}

skin_decl :: proc(state: ui.UI_Interaction, important: bool = false, border: f32 = 13) -> clay.ElementDeclaration {
	tint := important ? foster.Color{255, 245, 218, 255} : foster.Color{180, 205, 212, 255}
	if state.disabled {
		tint = {90, 105, 112, 255}
	} else if state.active {
		tint = {145, 158, 168, 255}
	} else if state.hovered || state.focused {
		tint = foster.White
	}
	return ui.ui_nine_slice_decl(&ctx, &button_skin,
		f32(min(button_skin.Width, button_skin.Height)) * 0.18, border, tint)
}
