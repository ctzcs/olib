# 可嵌入的 Shader Lab

`olib:kit/tools/shader_lab` 提供 2D/3D Shader 预览、Odin 参数面板、纹理缩略图与选择、
调色板、参数预设、Odin 多 Pass、RenderTexture、上一帧反馈和热重载，支持宿主自定义模型与绘制。它依赖
`material / shaderdev / ui / rendering3d`，不依赖示例仓库。
独立启动入口位于同级 `olib_sample/src/shader_lab/main.odin`。

## 宿主接入

宿主持有地址稳定的 `Session`，提供 GraphicsDevice、MSDF 字体、项目路径和可选主题。
工具不创建窗口、不接管 App 回调、不读取全局输入、不调用 Exit，也不清空宿主渲染目标。

```odin
import lab "olib:kit/tools/shader_lab"

// editor.lab 是宿主中地址稳定的 lab.Session；字体与纹理由宿主加载。
ok := lab.init(&editor.lab, device, {
    source_root = "content/shaders",
    parameter_directory = "content/shader_params",
    generated_directory = "library/shader_dev",
    font = &editor.msdf_font,
    font_texture = editor.msdf_texture,
    // icons = &editor.icons, // 可选，共享已上传的 rendering.builtin_icons_load 图集。
    file_dialogs = true, // 宿主须处理下文的文件请求；不用对话框时保留 false。
    // theme = &editor.theme, // 可选，初始化时复制。
})

// Update：持续推进热重载。即使暂停预览时间，也会检测源码变化。
lab.update(&editor.lab, delta_time)

// Render：宿主按最终目标像素提供区域和已路由的输入。
consumed := lab.render(&editor.lab, target, panel_rect, lab.Input{
    pointer = pointer_in_target_pixels,
    delta = pointer_delta_in_target_pixels,
    scroll = wheel,
    left_down = left_down,
    right_down = right_down,
    right_pressed = right_pressed,
    focused = tool_has_input_focus,
    escape = escape_pressed,
    navigation = navigation,
    vertical_adjust = up_down_adjust,
    dropped_files = dropped_paths, // 本帧拖入的文件；只借用至 render 返回。
})
// consumed.pointer / consumed.keyboard 用于后续输入分配。

// 隐藏、停用面板时取消捕获与调色板预览；重新显示可继续使用原 Session。
lab.cancel(&editor.lab)

// 关闭工具时释放；随后才可释放宿主字体、图集纹理和 GraphicsDevice。
lab.dispose(&editor.lab)
```

- `init` 复制路径和主题；借用设备、字体及图集。失败返回 false，成功后 Session 不得复制/搬动。
- 字体始终以 `.MSDF` 注册，无 Bitmap 回退；宿主负责提供正确的距离场图集和所需字符。
  标签缺字会输出诊断，工具不会自行访问示例字体路径或运行系统字体烘焙。
- 图标使用仓库 `assets/icons` 的内置图集：folder、展开箭头、勾选、播放控制与常用操作均按名称取子图。
  默认每会话初始化时上传一次、关闭时释放；可通过 `Config.icons` 借用宿主图集，多个工具共享约 64 MiB
  的 GPU 纹理。借用图集须地址稳定并活到 `dispose` 之后，工具不会释放它；图标 tint 跟随主题与选中状态。
- `render` 的目标可以是窗口或宿主 Target。工具在区域大小的内部目标中绘制，按 1:1 合成到区域，
  非零原点和窗口 DPI 转换由输入坐标匹配。区域原点对齐整数像素，不随低分辨率场景放大 UI。
  场景预览直接取选中 Effect 的 Pass 目标，不保留额外的单 Shader 场景目标。
  只有当前选中效果分配 RenderTexture（包含深度、MSAA resolve 和 Previous 双缓冲）。
  切换后在本帧 UI/缩略图提交完毕时释放旧目标，新效果在下一帧渲染开始时创建，避免悬空纹理引用。
  无效果时直接在最终输出绘制背景；最终输出目标用于合成预览和原生像素 UI，仍保留。
- Texture 的 Clear、替换和参数恢复会保留本帧缩略图借用的旧纹理，最终 UI 提交后再释放。
  Clear 后恢复内置棋盘格，不让已排入绘制的图片引用失效。
- 面板需要宽度至少 320、高度大于 180 像素；更小区域跳过绘制并取消捕获。
  侧栏的工作区、效果选择器和详情页签位置固定；Pass 列表与详情内容分别滚动。
  效果菜单使用浮层，展开菜单或 Shader folder 不挤动其它区域。详情滚动按工作区、效果和 Pass
  的稳定 ID 记忆，预览设置单独记忆；均只保留在当前 Session。支持拖动右侧分隔条调宽、收起/面板切换。
  逻辑宽度小于 760 时使用覆盖式侧栏，
  收起后可查看完整预览。布局只保留在当前 Session，拖动时 Escape 或失焦恢复原宽度。
- UI 比例取 `clamp(min(像素宽/1280, 像素高/800), 1, 1.6)`；1600×1000 为 125%。
  字体、控件、间距和命中统一缩放，MSDF 在最终输出目标直接绘制。小窗口不把正文缩到 16px 以下，
  采用滚动与覆盖侧栏；Shader 的低分辨率 RenderTexture 不影响 UI 字体采样。
- 工具拥有独立 UI_Context；在宿主自己的 `ui_begin / ui_end` 区间之外调用 `render`。
  多个工具实例可按顺序绘制，各自持有参数、相机和捕获状态；宿主负责分配焦点及区域。
- `focused=false` 停止工具交互并取消当前操作。拖动移出面板仍须把移动和松开送给捕获者；
  宿主文字输入或其他模态界面占用键盘时，不向工具转发导航动作。
- Escape 取消工具操作；是否关闭整个应用由宿主决定。调色板取消恢复打开时的颜色，
  数值和相机变化仅作用于预览；预设是显式保存的快照，不自动改写 Odin 默认值或宿主材质文档。
  工具不提供材质文档与撤销历史；将预览结果应用到游戏内容时，由宿主执行编辑事务。

## 预设与文件接入

- 图像效果的 Save/Load 保存或读取当前 Shader 组的参数预设；模型 `.Model` 效果的同一组按钮
  保存/载入**整个材质**（version=2：Effect 名、所有参数组及贴图），面板会显示范围提示。
  Reset all 仍只恢复当前参数组，每个字段右侧 R 恢复单项。
  默认值来自当前成功加载的 Odin 声明。也可直接调用 `save_preset / load_preset / reset_defaults`。
  整材质的显式 API 是 `save_material / load_material`，传入 Effect 索引。
  全部参数和 GPU 贴图准备成功才原子替换；失败保留旧材质。异步文件请求同时绑定 Effect 名和布局版本。
- 预设 JSON 由工具生成，无需手写。内容包含版本、组名、字段 ID/类型/值；图片尽量保存为相对
  预设文件的路径。加载按稳定 ID 匹配：新字段取默认值，已删除字段忽略，类型冲突拒绝加载。
  文件无效或新图片加载失败保留原值；保存使用同目录临时文件替换，失败保留原文件。
- 点击纹理卡片可 Browse file、从项目 textures 目录选择，或 Clear / checker 清空。
  也可把图片拖到卡片。已绑定图片修改后自动重载，失败保留上一次成功的图片。
  轮询每 0.25 秒检查修改时间/文件大小，连续两次稳定后加载。

文件对话框由宿主提供，库不依赖 SDL 窗口。启用 `Config.file_dialogs` 后，每次 Update 检查
`lab.file_request(&session)`；`id != 0` 时按 `action` 打开一次文件选择或保存对话框。
记录该 id，完成后在主线程、`render` 之外调用 `lab.file_reply(&session, id, path)`；
取消传空路径。组切换不会改变请求目标，声明布局更新后返回的旧请求会被拒绝。
请求字符串借用自 Session，异步代码如需使用须自行复制；回调不能直接操作已销毁的 Session。

独立示例已在 `olib_sample/shared/shader_lab_files` 接上 SDL 原生对话框与拖放。
文件路径由宿主保存到一次 `render` 返回；拖放坐标和普通 pointer 一样使用目标最终像素。
GPU 纹理、默认值和预设的直接 API 均须在主线程调用。

## 宿主自定义预览

通过 `Config.preview` 设置 `Preview_Hooks{user_data, prepare, draw}`。
`prepare` 接收当前组名、2d/3d、目标尺寸、材质和预览目标，填写零初始化的 `DrawCommand`：

```odin
prepare_preview :: proc(data: rawptr, frame: lab.Preview_Frame, command: ^foster.DrawCommand) -> bool {
    host := cast(^Editor)data
    if frame.dimension != "3d" do return false // 使用内置预览。
    foster.DrawCommandFromMesh(command, frame.target, &host.preview_mesh, frame.material)
    command.DepthTestEnabled = true
    command.DepthWriteEnabled = true
    command.CullMode = .Back
    return true
}
```

同一 prepare 会用于热重载候选管线检查与实际绘制，因此它应只描述命令，不产生游戏状态副作用。
返回 true 后工具接管命令内部临时分配并释放；宿主仍拥有模型和 `user_data`，必须活到工具停止使用。
省略 `draw` 时工具直接绘制该命令；需要自定义相机或时间输入时，可在 draw 回调覆盖 b0，再调用
`GraphicsDeviceDraw(frame.device, command)`。回调使用 prepare 描述的管线配置，不清空宿主目标。
生成参数仍由工具绑定到片段 b1，Shader 入口/资源布局遵循当前 Shader Lab 协议。
回调作用于效果中的 `.Preview_Model`、`.Model` 和 `.Sprite` Pass；`.Fullscreen` 使用内置全屏网格。
对象材质的显式 `state` 在 prepare 后应用，候选管线探测和实际绘制遵循相同规则。
`Preview_Frame.pass` 为声明的 Pass ID，尺寸是该 Pass 的实际目标尺寸；
实际绘制回调还提供效果时间、delta_time 和 frame_index。顶部 Host 按钮可切换内置/宿主模型。

## Odin 多 Pass 与历史帧

界面和运行时统一使用 `Effect → Pass → Shader 参数`。一个 Effect 可以只有一个 Pass，
也可以有多个 Pass；多个 Pass 可以复用同一份 Shader，因此 Pass 数量不等于 Shader 数量。
只有明确声明了 `X_Passes / X_Output` 的效果才进入选择器。`X_Params / X_Shader` 只定义
可复用的 Shader 资源，不自动创建效果；例如模糊和反馈参数组只在引用它们的 Pass 下显示。
没有效果声明时，工作区为空，不自动回退到 Shader 预览。参数值继续共享，Shader 不重复编译。

现有参数结构和 HLSL 无需改动；需要独立预览的组必须额外在同一参数包声明
`X_Passes` 和 `X_Output`，生成器会把它识别成效果；类型来自纯数据包 `kit/material`，
声明包不用 import 工具或 GPU。所有声明仍只编译一个临时生成程序。
单 Pass 也显式声明，之后追加 Pass 时保留原 ID 可延续选中和折叠状态。
单 Pass 和多 Pass 共用启停、参数、预设、热重载及渲染路径。例如已有 `Water_Params / Water_Shader`：

```odin
Water_Ref :: mat.Params_Ref("Water")
Water_Output :: mat.Target_Ref("color")
Water_Passes := []mat.Pass_Desc{
    {id = "main", params = Water_Ref, draw = .Preview_Model, output = Water_Output},
}
```

```odin
package shader_params
import mat "olib:kit/material"

// Surface、Composite 是现有的参数组名；Composite_Params 包含 source/history 纹理字段。
Trail_Label :: "拖尾效果" // 可选；省略时显示 Trail。
Trail_Preview :: mat.Preview_Mode.Three_D // 整个效果属于 3D 工作区。
Surface_Ref :: mat.Params_Ref("Surface")
Composite_Ref :: mat.Params_Ref("Composite")
Scene_Color :: mat.Target_Ref("scene_color")
Trail_Output :: mat.Target_Ref("result")
Source_Field :: mat.Field_Ref("source")
History_Field :: mat.Field_Ref("history")
Trail_Passes := []mat.Pass_Desc{
	{id = "scene", label = "绘制场景", params = Surface_Ref, draw = .Preview_Model, output = Scene_Color,
		target = {format = .Float16}},
	{id = "compose", label = "上一帧反馈", params = Composite_Ref, draw = .Fullscreen, output = Trail_Output,
		inputs = {
			{field = Source_Field, target = Scene_Color},
			{field = History_Field, target = Trail_Output, frame = .Previous},
		}},
}

Surface_Label :: "水面着色器"
Surface_Folder :: "材质" // 可选的 folder 标题前缀。
Composite_Label :: "反馈着色器"
```

`field` 按参数的稳定 ID 匹配，纹理输入对应 `mat.Texture_Path` 字段，默认路径通常留空。
兼容旧的 string + `ui:"texture"`。重复连线推荐使用具名常量，专用类型阻止不同用途的引用混用；
名字是否存在由生成器检查。所有声明类型见 [material](../../material/README.md#数据与所有权)。
HLSL 继续使用生成的 `_source / _history` 和对应 Sampler；不需要手写资源寄存器。
未连接的 Texture 字段继续使用图片选择器，连接的字段显示目标名称和缩略图。

| 声明 | 行为 |
| --- | --- |
| `draw = .Fullscreen`（默认） | 全屏四边形，参数组采用现有 2d 顶点接口；禁用混合，完整写入目标 |
| `draw = .Preview_Model` | 按参数组 2d/3d 使用当前模型或宿主回调；3D 自动带深度附件 |
| `draw = .Sprite` | 游戏精灵材质 Pass；共享单个目标，使用 kit/rendering 的 Sprite 接口、默认预乘 Alpha |
| `draw = .Model` | 可用于游戏模型的材质 Pass；整个 Effect 共用一个颜色/深度目标，按声明顺序绘制 |
| `inputs[].frame = .Current`（默认） | 读取本帧生产者结果，自动按依赖排序，不要求声明顺序正确 |
| `inputs[].frame = .Previous` | 读取上一模拟帧，目标自动启用双缓冲，允许跨帧循环 |
| `target.width / height` | 同时指定固定像素尺寸；均为 0 时跟随预览尺寸 |
| `target.scale` | 跟随尺寸的比例，如 0.5；0 表示 1，固定尺寸时不使用 |
| `target.format` | `.Color`（RGBA8）、`.Float16`、`.Float32`；浮点值保留在中间目标，最终窗口仍是普通颜色显示 |
| `target.samples` | 0 自动：模型 4x、全屏 1x；可指定 1 或 4，采样时使用解析后的纹理 |
| `target.depth / clear` | 可额外启用深度；每次绘制前清屏，RGBA 默认为透明黑，深度为 1 |
| `values` | 按字段 ID 覆盖数值，如 `{field="direction", number={1,0,0,0}}`；面板只读展示 |

同一参数组可供多个 Pass 使用，Shader 只编译一份；组参数共享，`values` 只在该 Pass 绘制时覆盖，
不改写面板值或预设。示例的横向/纵向模糊共用 TrailBlur，通过 direction 覆盖区分方向。
每个目标只有一个生产 Pass；本版本每 Pass 写一个颜色附件，可带深度，尚不提供 MRT、Compute、
深度纹理采样或追加绘制到同一目标。不同效果的目标和反馈互相独立。

界面按效果 → Pass → Shader folder → 参数显示。`X_Label` 是效果或 Shader 的可选显示名，
`Pass_Desc.label` 是 Pass 显示名，省略或空字符串时回退到内部名；`X_Folder` 是可选 Shader
folder 标题前缀。均支持中文，字形须包含在宿主 MSDF 图集中；示例已补齐演示名称所需字形。
内部前缀、`id / params / output` 仍用于连接、生成文件和状态迁移，不要用显示名代替它们。
同名显示标签允许重复；修改显示名不会改变绑定、预设组名或生成路径。

正常流程为：选择 2D / 3D 工作区 → 选择效果 → 点击 Pass → 在下方调参数 → 右侧查看最终效果。
工作区只显示对应维度的效果，分别记住效果、Pass、最终/中间输出、预览载体、相机和页签。
`X_Preview :: mat.Preview_Mode.Two_D / Three_D` 指定整个效果的工作区；它不改变各 Pass 的顶点接口。
旧的 `"2d" / "3d"` 仍兼容，`.Auto` 与省略效果 Preview 一样按模型 Pass 推断。
省略时兼容旧声明：含 3D `.Preview_Model` 或 `.Model` Pass 的效果归 3D，其余归 2D。

### 模型材质 / 本体 + 描边

`olib_sample` 的 `Outlined_Passes` 使用两个 `.Model` Pass：本体背面剔除并写深度，描边
外扩顶点、正面剔除、只读深度。二者必须使用同一个 output 和 target 描述，不接受图目标输入。
库会调用 `rendering3d.model_material_draw`；游戏里的 `material3d` 示例也使用它。
这里的“当前 Pass”显示从首个 Pass 累积绘制到选中 Pass 的结果，关闭某 Pass 只跳过绘制，
不会清除其他 Pass 的颜色/深度。旧图像效果仍保留独立目标、输入拓扑和历史帧机制。

保存后的材质 JSON 可由 `material.instance_load` 直接装载。游戏需要一起提供同一 Effect 定义和
预编译 Shader；参数文件本身不是 Shader 包。Pass 定义、预览启停和相机不会写进材质 JSON。
示例的描边颜色可在面板修改；宽度目前是 HLSL 常量，可以修改源码热重载，不是材质数值字段。
3D 效果可以包含使用 2D 顶点接口的全屏模糊、合成和反馈，它们不会被拆到 2D 工作区；
显式声明为 2D 的效果不能包含 3D 模型 Pass。`select_workspace(session, 0 / 1)` 可从宿主切换。
首次加载默认进入 2D，打开其中第一个已声明效果；该维度没有效果则显示空工作区。
完整 Pass 列表始终在固定高度的独立区域内，点击只改变
`inspect_pass`，不会从最终效果跳到中间输出。多个 Pass 时预览区提供“最终效果 / 当前 Pass”切换；
只有一个 Pass 时直接展示最终效果，省略两者相同的切换按钮。
`preview_pass=-1` 为最终效果，非负值为中间输出。在“当前 Pass”模式下，选择跟随编辑项。
`select_effect(session, effect_index, pass_index=-1)` 选择编辑项，省略 Pass 时选择执行顺序的第一个。
同一时间编辑一个 Pass；再点击已选 Pass 可折叠，Shader folder 也可独立折叠。
折叠不改变执行，Pass 左侧 checkbox 才控制启停。`disabled = true` 可在 Odin 声明默认禁用，
省略则启用。运行时切换通过 `set_pass_enabled(session, effect_index, pass_index, enabled)`，
只改变会话预览，不自动写回 Odin 或参数预设。热重载按效果名、Pass ID 保留启停和折叠状态；
源声明的 `disabled` 改变时以新声明为准。
禁用 Pass 时不执行其 Shader 或宿主绘制回调：有且只有一个 Current 输入则缩放直通到自身目标，
否则按该目标的 clear 清屏；Previous 输入不计入直通选择。下游仍能读取原输出名，启停重置反馈历史。

示例的 Preview2D / Preview3D 是参数组及显式单 Pass 效果 ID，显示名为“流动纹理 / 模型表面”；
它们与拖尾等多 Pass 效果使用同一套选择和编辑流程。
“参数 / 预览设置”替换下方详情内容，不改变上方选择区的位置。
“预览设置”中的全屏/精灵或球体/立方体只改变载体，仅显示与当前工作区兼容的选项，不切换 Shader。
顶部播放/暂停冻结时间和 Previous；调参数仍可重新计算当前输出。
Step 暂停并推进一次完整流程（1/60 秒），Reset history 重置该效果时间、帧号和历史。
程序接入可调用 `select_effect / step / reset_history`；重置可从 Update 调用，GPU 清屏延迟到 Render。
切走效果释放目标，再次选中时重新分配并重置该效果时间、帧号和 Previous 历史；参数值、
Pass 启停/折叠、工作区书签继续保留，不补算隐藏期间的时间。

时间输入仍为片段 b0：第一个 float4 是 `time / delta_time / frame_index / sprite_flag`，
第二个 float4 是鼠标 UV 与**当前 Pass** 的目标宽高，第三个保留为白色 Tint。
暂停重绘保留最近一次模拟步的 delta_time；不能仅以是否发生 render 判断模拟是否推进。
首次显示、目标 resize、Shader 成功重载、Odin 流程成功切换或手动重置都会清空历史。
UI 始终在全部 Pass 完成后按最终像素绘制，不进入模糊/反馈链。

Odin 改动仍先校验整包声明并编译 Shader，但只为当前选中效果分配候选目标、检查实际网格/格式/MSAA
管线，成功才统一替换。候选准备期间短暂保留当前效果的新旧两套目标，以便失败时保留有效预览；
其他效果不分配目标。编译期间继续调的参数在提交时迁移。
未选中效果使用的 Shader 仍编译并报告源码错误，首次使用前保持 `Ready`；选中后才创建 GPU Shader
和检查实际管线。已经使用过的 Shader 资源保留共享，切换时可直接用缓存代码检查新目标配置，
不重新编译 HLSL。切换中尚未就绪或检查失败的效果显示背景及诊断，不提交无效绘制。
当前帧循环、未知目标/字段和重复输出会拒绝加载。最多 16 组参数、16 个显式效果，每效果 32 个 Pass；
单轴目标尺寸最多 8192，目标格式/采样组合仍受所选 GPU 后端支持范围限制。

## 项目内容与生成文件

Odin 参数声明、HLSL、图片和字体资产归项目；库仅提供工具代码。声明约定见
[shaderdev](../../shaderdev/README.md)，参数布局见 [material](../../material/README.md)。

`generated_directory` 通常设为项目的 `library/shader_dev`。每组生成
`<组名>/params.generated.hlsli`，HLSL 使用相对于自身的 include 路径，保留 IDE 可读副本。
传空字符串时只生成编译快照中的临时头文件，HLSL 应使用 `#include "params.generated.hlsli"`。
截图归入所属项目的 `library/screenshots/`，需要留存的诊断副本归入 `library/tmp/`；
同目录预设替换文件和编译器私有快照仍由工具按生命周期管理。完整规则见
[生成文件约定](../../../prompts/new-project.md#生成文件与目录纪律)。
默认最多 16 组；Odin 参数布局和效果整包成功后统一切换，失败保留上一版。

## 示例与检查入口

在 `olib_sample` 运行 `run.bat shader_lab`。可追加 `embedded` 查看带偏移的嵌入区域；
`source / params / cache` 参数指定项目路径。示例只负责启动接线，预览素材仍属于示例项目。
截图与故障注入代码位于示例仓库的 `tools/shader_lab_checks`，提供 `shot / colors / smoke / features / multipass`
入口；它们不进入库的工具包，也不是运行工具的必需依赖。仅选择与本次改动相关的检查，
不把这些示例作为新项目默认任务；旧入口若写到其他位置，留存产物应归并到上述固定目录。

`features embedded d3d12` 集中检查预设往返、默认值、失败回滚、过期文件请求、图片热更新、
自定义预览和侧栏布局；不重复 smoke 的完整故障注入。原生对话框的实际选择由手动操作验收。

示例 `shader_params/multipass.odin` 定义 Trail2D / Trail3D：场景 → 半分辨率横向模糊 →
纵向模糊 → 上一帧反馈。`multipass embedded d3d12` 集中检查旧单 Shader、2D/3D、HDR/MSAA、
反馈暂停/单步/重置/resize，以及循环依赖和错误 Shader 的回退恢复，不运行其它整套冒烟。

`hierarchy embedded d3d12` 集中检查显示名、folder、checkbox、最终/中间输出独立切换、显示名热改迁移，
效果列表排除仅有 Shader 的资源、显式单 Pass 扩成多 Pass 时的选择/参数保持，
2D/3D 列表隔离与状态恢复、浮层不挤动 Pass 列表、固定区域坐标及参数/设置滚动位置恢复，
以及普通、125% 和窄窗口的最终截图与输入命中；不运行其它完整故障注入。

`targets embedded d3d12` 集中检查仅选中效果持有目标、2D/3D 切换释放/重建、深度/MSAA、多 Pass resize、
反馈重置与参数保留、候选包按当前选择热重载、空效果包和恢复声明，以及实际点击 Texture Clear 后恢复棋盘格；
不跑完整 UI 点击序列或故障注入。

### 精灵材质 / 阴影 + 本体

`olib_sample` 的 `SpriteShadow_Passes` 使用 `.Sprite`：偏移阴影 + 本体。2D 工作区可选择该效果，
预览直接调用 `rendering.sprite_material_draw`，游戏示例在 `src/material2d`。
`.Sprite` 和旧 `.Preview_Model` 的顶点 uniform 接口不同；不能只改 draw 类型而沿用旧 Shader。
整材质保存/载入同时适用于 Model 和 Sprite，按 Effect 名匹配，失败保留整个旧材质。
Shader 接口与业务接入见 [kit/rendering](../../rendering/README.md)。
