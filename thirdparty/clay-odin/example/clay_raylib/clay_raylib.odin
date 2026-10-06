package clay_raylib
import "core:fmt"
import "core:math"
import clay "../../"
import raylib "vendor:raylib"

main :: proc() {
    raylib.SetConfigFlags({raylib.ConfigFlags.WINDOW_RESIZABLE})
    raylib.InitWindow(1280, 720, "clay example")
    
    min_memory_size := clay.MinMemorySize()
    memory := make([^]u8, min_memory_size)
    arena: clay.Arena = clay.CreateArenaWithCapacityAndMemory(uint(min_memory_size), memory)
    clay.Initialize(arena, {1280, 720}, { handler = error_handler })
    clay.SetMeasureTextFunction(measure_text, nil)
    delta :f32= 0.1
    elapsed_time :f32= 0.0
    cur_width:i32 = 1280
    cur_height:i32 = 720 
    for !raylib.WindowShouldClose() {
        // 获取当前窗口尺寸
        w := raylib.GetScreenWidth()
        h := raylib.GetScreenHeight()
        
        clay.SetLayoutDimensions({ width = f32(w), height = f32(h) })
        // 同步 clay 布局尺寸
        //clay.SetLayoutDimensions({ width = f32(w), height = f32(h) })
        
		raylib.BeginDrawing()
		raylib.ClearBackground(raylib.BLACK)

		mouse_pos := raylib.GetMousePosition()
        render_commands := create_layout()
	
        for i in 0..<i32(render_commands.length) {
            render_command := clay.RenderCommandArray_Get(&render_commands, i)

            #partial switch render_command.commandType {
            case .Rectangle:
                DrawRectangle(render_command.boundingBox, render_command.renderData.rectangle.backgroundColor)
            // ... Implement handling of other command types
            case .Image:
                DrawImage(render_command.boundingBox, render_command.renderData.image.imageData)
            case .Text:
                DrawText(render_command.boundingBox, render_command.renderData.text)
            case:
                fmt.printf("Unhandled command type: %d\n", render_command.commandType)
            }
        }

		/* for b in bodies {
			position := b2.Body_GetPosition(b.body)
			a := b2.Rot_GetAngle(b2.Body_GetRotation(b.body))
			
			// There's a negation of
			// position.y because Box2D is
			// Y up and Raylib is Y down.
			raylib.DrawRectanglePro({position.x, -position.y, BOX_SIZE*2, BOX_SIZE*2}, {BOX_SIZE, BOX_SIZE}, -a*math.DEG_PER_RAD, raylib.YELLOW)
		} */

		raylib.DrawCircleV(mouse_pos, 40, raylib.MAGENTA)
		raylib.DrawFPS(10, 10)
		raylib.EndDrawing()	
    }

    raylib.CloseWindow()

    

    
}

// 顶部附近：添加工具函数与全局纹理变量
// 将 clay.Color 转为 raylib.Color
to_raylib_color :: proc(c: clay.Color) -> raylib.Color {
    return raylib.Color{u8(c[0]), u8(c[1]), u8(c[2]), u8(c[3])}
}

// 将 clay.BoundingBox 转为 raylib.Rectangle
to_raylib_rect :: proc(bb: clay.BoundingBox) -> raylib.Rectangle {
    return raylib.Rectangle{bb.x, bb.y, bb.width, bb.height}
}

// 使用 raylib 绘制矩形
DrawRectangle :: proc(bb: clay.BoundingBox, color: clay.Color) {
    raylib.DrawRectangleRec(to_raylib_rect(bb), to_raylib_color(color))
}

// 使用 raylib 绘制图片（按 boundingBox 缩放）
DrawImage :: proc(bb: clay.BoundingBox, image_data: rawptr) {
    tex := cast(^raylib.Texture)image_data
    src := raylib.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
    raylib.DrawTexturePro(tex^, src, to_raylib_rect(bb), raylib.Vector2{0, 0}, 0.0, raylib.WHITE)
}

DrawText::proc(bb: clay.BoundingBox, text: clay.TextRenderData) {
    raylib.DrawText(
        to_cstring(text.stringContents),
        i32(bb.x), i32(bb.y),
        i32(text.fontSize),
        to_raylib_color(text.textColor),
    )
}

// 全局示例纹理
profile_picture: raylib.Texture
error_handler :: proc "c" (errorData: clay.ErrorData) {
    // Do something with the error data.
    /* fmt.printf("Error: %s\n", errorData) */
}

measure_text :: proc "c" (
    text: clay.StringSlice,
    config: ^clay.TextElementConfig,
    userData: rawptr,
) -> clay.Dimensions {
    // clay.TextElementConfig contains members such as fontId, fontSize, letterSpacing, etc..
    // Note: clay.String->chars is not guaranteed to be null terminated
    return {
        width = f32(text.length * i32(config.fontSize)),
        height = f32(config.fontSize),
    }
}


COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}
COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
COLOR_BLACK :: clay.Color{0, 0, 0, 255}

// Layout config is just a struct that can be declared statically, or inline

make_sidebar_item_layout :: proc() -> clay.LayoutConfig {
    return clay.LayoutConfig{
        sizing = {
            width = clay.SizingGrow({}),
            height = clay.SizingFixed(50),
            
        },
        childAlignment = clay.ChildAlignment{ x= .Center, y= .Center},
    }
}

// Re-useable components are just normal procs.
sidebar_item_component :: proc(index: u32) {
    if clay.UI(id = clay.ID("SidebarBlob", index))({
        layout = make_sidebar_item_layout(),
        backgroundColor = COLOR_ORANGE,
    }) {
        clay.Text(
                    "Clay",
                    clay.TextConfig({ textColor = COLOR_BLACK, fontSize = 16, textAlignment = .Center }),
                )
    }
}

// An example function to create your layout tree
create_layout :: proc() -> clay.ClayArray(clay.RenderCommand) {
    // Begin constructing the layout.
    clay.BeginLayout()

    // An example of laying out a UI with a fixed-width sidebar and flexible-width main content
    // NOTE: To create a scope for child components, the Odin API uses `if` with components that have children
    if clay.UI(clay.ID("OuterContainer"))({
        layout = {
            sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
            padding = { 16, 16, 16, 16 },
            childGap = 16,
        },
        backgroundColor = { 250, 250, 255, 255 },
    }) {
        if clay.UI(clay.ID("SideBar"))({
            layout = {
                layoutDirection = .TopToBottom,
                sizing = { width = clay.SizingFixed(300), height = clay.SizingGrow({}) },
                padding = { 16, 16, 16, 16 },
                childGap = 16,
            },
            backgroundColor = COLOR_LIGHT,
        }) {
            if clay.UI(clay.ID("ProfilePictureOuter"))({
                layout = {
                    sizing = { width = clay.SizingGrow({}) },
                    padding = { 16, 16, 16, 16 },
                    childGap = 16,
                    childAlignment = { y = .Center },
                },
                backgroundColor = COLOR_RED,
                cornerRadius = { 6, 6, 6, 6 },
            }) {
                if clay.UI(clay.ID("ProfilePicture"))({
                    layout = {
                        sizing = { width = clay.SizingFixed(60), height = clay.SizingFixed(60) },
                    },
                    image = {
                        // How you define `profile_picture` depends on your renderer.
                        imageData = &profile_picture,
                        /* sourceDimensions = {
                            width = 60,
                            height = 60,
                        }, */
                    },
                }) {}

                clay.Text(
                    "Clay - UI Library",
                    clay.TextConfig({ textColor = COLOR_BLACK, fontSize = 16, textAlignment = .Center }),
                )
            }

            // Standard Odin code like loops, etc. work inside components.
            // Here we render 5 sidebar items.
            for i in u32(0)..<5 {
                sidebar_item_component(i)
            }
        }

        if clay.UI(clay.ID("MainContent"))({
            layout = {
                sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
            },
            backgroundColor = COLOR_LIGHT,
        }) {}
    }

    // Returns a list of render commands
    return clay.EndLayout()
}

// 将 Clay 的 StringSlice 转为 cstring（追加 '\0'）
to_cstring :: proc(s: clay.StringSlice) -> cstring {
    // 分配长度 + 1 的缓冲区，用于存放内容和末尾的 0
    buf := make([]u8, int(s.length) + 1)
    for i in 0..<int(s.length) {
        buf[i] = u8(s.chars[i])
    }
    buf[int(s.length)] = 0
    return cast(cstring)&buf[0]
}