// olib:engine/asset 示例 —— 完整走一遍资源管线：
//
//   首跑：没有 Assets/demo.qoi 就程序生成一张渐变图
//         -> import_all（发 .meta GUID、写 Library/<guid>.blob）
//         -> assets_init（device 传入，贴图自动上 GPU）
//         -> assets_load_path -> 渲染
//   二跑：import_all 全部 skipped（新鲜度命中）
//
// 运行 3 秒后自动退出，方便连跑验证不变量：
//   删除 Library/ 再跑 -> imported=1 完整重建
//   移动 demo.qoi + demo.qoi.meta 到子目录再跑 -> GUID 不变、不重导
//
// 构建：run.bat（或）
//   odin build . -collection:olib=..\..\..\.. -collection:ofoster=<ofoster src 根>
package asset_example

import "core:fmt"
import "core:math"
import "core:os"

import foster "ofoster:."
import asset ".."

ASSETS_DIR  :: "Assets"
LIBRARY_DIR :: "Library"

assets:  asset.Asset_Manager
batcher: foster.Batcher
demo:    asset.Asset_Handle
spin:    f32

main :: proc() {
	app: foster.App
	foster.InitApp(&app, foster.DefaultAppConfig("olib asset example", 1280, 720))
	app.StartupProc = startup
	app.UpdateProc  = update
	app.RenderProc  = render
	app.ShutdownProc = shutdown
	defer foster.Dispose(&app)
	foster.Run(&app)
}

ensure_demo_source :: proc() {
	existing := foster.ImageLoadFile(ASSETS_DIR + "/demo.qoi")
	if existing.Width > 0 {
		delete(existing.Pixels)
		return
	}

	image := foster.ImageMake(256, 256, foster.Color{0, 0, 0, 255})
	for y in 0..<256 {
		for x in 0..<256 {
			// 左上到右下的青-品红渐变
			t := f32(x + y) / 510
			image.Pixels[x + y * 256] = foster.Color{
				R = u8(255 * t),
				G = u8(255 * (1 - t) * 0.6),
				B = u8(255 * (1 - t)),
				A = 255,
			}
		}
	}
	if !foster.ImageWriteQoi(&image, ASSETS_DIR + "/demo.qoi") {
		fmt.eprintln("生成 demo.qoi 失败")
	}
	delete(image.Pixels)
}

startup :: proc(app: ^foster.App) {
	_ = os.make_directory_all(ASSETS_DIR)
	ensure_demo_source()

	s1, err := asset.import_all(ASSETS_DIR, LIBRARY_DIR)
	fmt.println("import #1:", s1, "err:", err)
	// 立刻再导一次：新鲜度应全部命中（这就是二次启动的形态）
	s2, err2 := asset.import_all(ASSETS_DIR, LIBRARY_DIR)
	fmt.println("import #2 (应全 skipped):", s2, "err:", err)

	e := asset.assets_init(&assets, asset.Asset_Manager_Config{
		assets_root  = ASSETS_DIR,
		library_root = LIBRARY_DIR,
		device       = &app.GraphicsDevice,
	})
	if e != .None {
		fmt.eprintln("assets_init:", e)
		foster.Exit(app)
		return
	}

	demo, e = asset.assets_load_path(&assets, "demo.qoi")
	if e != .None {
		fmt.eprintln("assets_load_path demo.qoi:", e)
		foster.Exit(app)
		return
	}
	fmt.println("demo guid:", asset.guid_to_string(asset.assets_guid(&assets, demo)))

	foster.BatcherInit(&batcher, &app.GraphicsDevice, "asset example")
}

update :: proc(app: ^foster.App) {
	spin += app.Time.Delta

	if foster.KeyboardPressed(&app.Input.State.Keyboard, .Escape) {
		foster.Exit(app)
	}
	// 3 秒自动退出：示例只演示管线，不需要常驻
	if foster.TimeSecondsF(app.Time) > 3 {
		foster.Exit(app)
	}
}

render :: proc(app: ^foster.App) {
	target := foster.DrawableTargetFromWindow(&app.Window)
	foster.GraphicsDeviceClear(&app.GraphicsDevice, target, foster.Color{24, 28, 36, 255})

	foster.BatcherClear(&batcher)
	if tex := asset.assets_get_texture(&assets, demo); tex != nil {
		cx := f32(math.cos(spin * 0.5))
		sx := f32(math.sin(spin * 0.5))
		c: [2]f32 = {640, 360}
		r: f32 = 240
		tl := foster.Vec2{c[0] + (-cx + sx) * r, c[1] + (-sx - cx) * r}
		tr := foster.Vec2{c[0] + ( cx + sx) * r, c[1] + ( sx - cx) * r}
		br := foster.Vec2{c[0] + ( cx - sx) * r, c[1] + ( sx + cx) * r}
		bl := foster.Vec2{c[0] + (-cx - sx) * r, c[1] + (-sx + cx) * r}
		foster.BatcherQuadTexture(&batcher, tex,
			tl, tr, br, bl,
			{0, 0}, {1, 0}, {1, 1}, {0, 1},
			foster.White)
	}
	foster.BatcherRender(&batcher, target)
}

shutdown :: proc(app: ^foster.App) {
	foster.BatcherDispose(&batcher)
	asset.assets_dispose(&assets)
	fmt.println("bye")
}
