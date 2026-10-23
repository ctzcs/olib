package foster_framework

// olib 对 Foster 的纯新增能力（无上游对应），每项登记于 docs/LOCAL_CHANGES.md。

import "core:c"
import "core:math"
import SDL "vendor:sdl3"

// 文件内导航
//   Framework / App
//   Framework / Window Logical Size / Text Input Area
//   Storage / Atomic Write
//   Graphics / Texture Sampling

// ==============================================================================
// Framework / App — 用户数据
// ==============================================================================

// [olib L-004] 按类型取回 AppSetUserData 挂上的状态，省去每个回调里的 cast。
// 不做类型校验：T 必须与 AppSetUserData 传入的指针类型一致；未设置时返回 nil。
AppGetUserDataAs :: proc(app: ^App, $T: typeid) -> ^T {
	return cast(^T)AppGetUserData(app)
}

// ==============================================================================
// Framework / Window Logical Size — 配置尺寸按逻辑单位
// ==============================================================================

// [olib L-020] AppFlag.LogicalWindowSize：窗口坐标在 Windows/X11 是物理像素，在 macOS/Wayland 是点。
// 打开后按“显示缩放 ÷ 像素密度”放大配置宽高（Windows 150% 为 1.5，macOS 为 1），不超过显示器可用区域，
// 并在所在显示器居中。只在创建时做一次；跨缩放不同的显示器移动由 SDL 处理，界面按 ContentScale 每帧跟随。
@(private)
window_apply_logical_size :: proc(window: ^Window, config: AppConfig) {
	when ODIN_OS != .JS {
		if .LogicalWindowSize not_in config.Flags || config.Fullscreen || window.Handle == nil {
			return
		}
		density := SDL.GetWindowPixelDensity(window.Handle)
		scale := SDL.GetWindowDisplayScale(window.Handle)
		if density <= 0 || scale <= 0 || abs(scale/density - 1) < 0.01 {
			return
		}
		factor := scale/density
		w := c.int(math.round(f32(config.Width)*factor))
		h := c.int(math.round(f32(config.Height)*factor))
		display := SDL.GetDisplayForWindow(window.Handle)
		usable: SDL.Rect
		if SDL.GetDisplayUsableBounds(display, &usable) {
			w = min(w, usable.w)
			h = min(h, usable.h)
		}
		_ = SDL.SetWindowSize(window.Handle, w, h)
		center := SDL.WINDOWPOS_CENTERED_DISPLAY(c.int(display))
		_ = SDL.SetWindowPosition(window.Handle, center, center)
	}
}

// [olib L-022] 告诉系统输入法光标所在的矩形，候选框跟着它。rect 用渲染目标像素（与 SizeInPixels 同一坐标），
// 这里换算成 SDL 窗口坐标。在 StartTextInput / SetTextInput 打开文字输入后调用，光标移动时再调用；Web 无操作。
SetTextInputArea :: proc(window: ^Window, rect: Rect) {
	when ODIN_OS != .JS {
		if window.Handle == nil {
			return
		}
		size, pixels := Size(window), SizeInPixels(window)
		sx := pixels.X > 0 ? f32(size.X)/f32(pixels.X) : 1
		sy := pixels.Y > 0 ? f32(size.Y)/f32(pixels.Y) : 1
		area := SDL.Rect{c.int(math.round(rect.X*sx)), c.int(math.round(rect.Y*sy)),
			c.int(max(math.round(rect.Width*sx), 1)), c.int(max(math.round(rect.Height*sy), 1))}
		_ = SDL.SetTextInputArea(window.Handle, &area, 0)
	}
}

// ==============================================================================
// Storage / Atomic Write — 完整替换单个文件
// ==============================================================================

// [olib L-015] 桌面先写同目录临时文件并同步，再替换；Web 原子替换虚拟文件单键。
// 只读/ZIP 容器拒绝写入。失败保留原文件，不保证断电持久性或多文件事务。
// Web 文件选择器的外部文件仍需 FlushStorageFileAsync 确认，true 只表示虚拟文件已更新。
WriteAllBytesAtomic :: proc(container: ^StorageContainer, path: string, data: []byte) -> bool {
	if container == nil || !container.Writable || container.ZipEntries != nil || path == "" {
		return false
	}
	full := StorageJoinPath(container, path)
	parent, _ := storage_path_split(full)
	if parent != "" && !storage_os_make_directory_all(parent) {
		return false
	}
	if storage_os_is_directory(full) {
		return false
	}
	return storage_os_write_file_atomic(full, data)
}

// [olib L-015] UTF-8 文本沿用相同的单文件替换语义。
WriteAllTextAtomic :: proc(container: ^StorageContainer, path, data: string) -> bool {
	return WriteAllBytesAtomic(container, path, transmute([]byte)data)
}

// ==============================================================================
// Graphics / Texture Sampling — 贴图能否绑定到材质采样器
// ==============================================================================

// [olib L-018] 贴图能否绑定到采样器。普通贴图总带 SAMPLER 用途；多采样颜色附件采样其解析纹理；
// 深度附件须单采样且格式支持采样，与 Target 创建时是否加 SAMPLER 用途是同一条规则。
TextureIsSampleable :: proc(tex: ^Texture) -> bool {
	if tex == nil || tex.Resource == nil || tex.Disposed {
		return false
	}
	if !tex.IsTargetAttachment {
		return true
	}
	if TextureFormatIsColorFormat(tex.Format) {
		return tex.SampleCount == .One || tex.ResolveResource != nil
	}
	return depth_attachment_sampleable(tex.GraphicsDevice, tex.Format, tex.SampleCount)
}

// [olib L-018] SDL 没有深度解析纹理，多采样深度不能采样；单采样时按设备是否支持该格式的采样判定。
@(private)
depth_attachment_sampleable :: proc(device: ^GraphicsDevice, format: TextureFormat, sample_count: SampleCount) -> bool {
	return sample_count == .One && GraphicsDeviceIsTextureFormatSupported(device, format)
}
