# 可嵌入的 Shader Lab

使用 [单文件 `.oshader`](../../rendering/shader/lang/README.md)：参数、默认值、Pass 状态和 HLSL 在同一文件维护。
示例在 `olib_sample/src/shader_lab/shaders/`，Zed 高亮见 [扩展说明](../../../tools/zed-shader/README.md)。
完整语法、当前每 Pass 独立参数值的语义与发布方式见链接。

`olib:kit/tools/shader_lab` 提供 2D/3D Shader 预览、Properties 参数面板、纹理缩略图与选择、
调色板、参数预设、多 Pass、RenderTexture、上一帧反馈和热重载，支持宿主自定义模型与绘制。它依赖
`rendering/material / rendering/2d / rendering/3d / rendering/shader/dev / ui`，不依赖示例仓库。
独立启动入口位于同级 `olib_sample/src/shader_lab/main.odin`。

## 宿主接入

宿主持有地址稳定的 `Session`，提供 GraphicsDevice、MSDF 字体、项目路径和可选主题。
工具不创建窗口、不接管 App 回调、不读取全局输入、不调用 Exit，也不清空宿主渲染目标。

```odin
import lab "olib:kit/tools/shader_lab"

// editor.lab 是宿主中地址稳定的 lab.Session；字体与纹理由宿主加载。
ok := lab.init(&editor.lab, device, {
    source_root = "content/shaders",
    font = &editor.msdf_font,
    font_texture = editor.msdf_texture,
    // icons = &editor.icons, // 可选，共享已上传的 r2d.builtin_icons_load 图集。
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
  数值和相机变化仅作用于预览；预设是显式保存的快照，不自动改写 Properties 默认值或宿主材质文档。
  工具不提供材质文档与撤销历史；将预览结果应用到游戏内容时，由宿主执行编辑事务。

## 预设与文件接入

- 图像效果的 Save/Load 保存或读取当前 Shader 组的参数预设；模型 `.Model` 效果的同一组按钮
  保存/载入**整个材质**（version=2：Effect 名、所有参数组及贴图），面板会显示范围提示。
  Reset all 仍只恢复当前参数组，每个字段右侧 R 恢复单项。
  默认值来自当前成功加载的 Properties。也可直接调用 `save_preset / load_preset / reset_defaults`。
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

通过 `Config.preview` 设置 `Preview_Hooks{user_data, record}`。材质效果（`.Model`、`.Sprite`）的预览由宿主用
游戏同一套 API 记录要画的东西，Shader Lab 负责提交到预览目标：

```odin
record_preview :: proc(data: rawptr, frame: lab.Preview_Frame, material: ^mat.Material,
    sprites: ^r2d.Render2D, models: ^r3d.Render3D) -> bool {
    host := cast(^Editor)data
    if models == nil do return false // 2D 效果使用内置预览
    return r3d.model(models, &host.preview_mesh, material, host.preview_transform) == .None
}
```

回调对每个要画的 Pass 调用一次；2D 记录时把 `frame.pass` 作为 `pass_id` 传入，3D 只管记录，Shader Lab 按该 Pass 提交。
`sprites` / `models` 按效果维度只给一个，返回 false 使用内置几何。材质借用到本次回调结束，宿主仍拥有网格和 `user_data`。
`Preview_Frame` 提供 Pass ID、参数组、维度、效果时间与目标尺寸。非材质效果（`.Fullscreen`、`.Preview_Model`）
总用内置几何；热重载的管线探测也只用内置几何，宿主几何须是渲染器支持的同一顶点格式。
顶部按钮可切换内置/宿主预览。

## 多 Pass 与历史帧

界面统一使用 Effect → Pass → 参数。每份 .oshader 是一个效果；每个 Pass 对应独立程序和参数实例。
Properties 声明是所有 Pass 的模板，值按各 Pass 分别保存。单 Pass 与多 Pass 共用同一流程，
追加 Pass 时保留原 ID 可延续选中、折叠与参数值。

语法与所有指令见 [shader/lang](../../rendering/shader/lang/README.md)。常用关系：

- Shader 的 Preview 2D/3D 决定工作区；Pass 的 Preview 决定顶点接口。
- Input 的 Current 自动按依赖排序；Previous 自动启用历史双缓冲。
- Target 指定分辨率、缩放、格式、MSAA 与清屏值。
- Value 按字段稳定 Id 覆盖本 Pass 数值，不改写面板值或预设。
- Label 仅改变显示名；Shader/Pass 名与字段 Id 用于状态迁移。

未连接的纹理字段使用图片选择器；已连接字段显示目标名称和缩略图。
图像效果每个目标只有一个生产 Pass；Model / Sprite 材质的 Pass 共用同一个目标并按顺序绘制。
每个 Pass 写一个颜色附件，可带深度；当前不提供 MRT、Compute 或深度纹理采样。
不同效果的目标和反馈互相独立。中文 Label 需要宿主字体包含相应字形。

### 模型材质 / 本体 + 描边

`olib_sample` 的 `Outlined.oshader` 使用两个 `.Model` Pass：本体背面剔除并写深度，描边
外扩顶点、正面剔除、只读深度。二者必须使用同一个 output 和 target 描述，不接受图目标输入。
预览与游戏的 `material3d` 示例一样用 `Render3D.model` 记录，再按 Pass `submit`。
这里的“当前 Pass”显示从首个 Pass 累积绘制到选中 Pass 的结果，关闭某 Pass 只跳过绘制，
不会清除其他 Pass 的颜色/深度。旧图像效果仍保留独立目标、输入拓扑和历史帧机制。

保存后的材质 JSON 在游戏中通过 `mat.material_load` 从 Foster StorageContainer 加载，
材质文件和贴图都归同一容器管理。游戏需要一起提供同一 Effect 定义和预编译 Shader；
参数文件本身不是 Shader 包。Pass 定义、预览启停和相机不会写进材质 JSON。
ShaderLab 的 `save_material/load_material` 仍接受桌面路径；预设使用 `save_preset/load_preset`。
路径适配集中在 [material_files.odin](material_files.odin)，均为包内私有函数。
读取使用 `foster.ReadAllBytes`，保存使用 `foster.WriteAllBytesAtomic`；同目录临时文件替换由
Storage 统一实现，ShaderLab 只处理相对贴图路径换算、编解码和将结果应用到会话。
保存失败不覆盖旧文件；这套安全保存也可直接用于游戏存档和配置。
公共 `kit/rendering/material` 同时提供参数编解码和基于 Foster StorageContainer 的材质加载；游戏不 import ShaderLab 来读资源。
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
折叠不改变执行，Pass 左侧 checkbox 才控制启停。`Disabled On` 可在 .oshader 中默认禁用，
省略则启用。运行时切换通过 `set_pass_enabled(session, effect_index, pass_index, enabled)`，
只改变会话预览，不自动写回 .oshader 或参数预设。热重载按效果名、Pass ID 保留启停和折叠状态；
源声明的 `disabled` 改变时以新声明为准。
禁用 Pass 时不执行其 Shader 或宿主绘制回调：有且只有一个 Current 输入则缩放直通到自身目标，
否则按该目标的 clear 清屏；Previous 输入不计入直通选择。下游仍能读取原输出名，启停重置反馈历史。

示例的 Preview2D / Preview3D 是单 Pass 效果 ID，参数组为 Preview2D_main / Preview3D_main，显示名为“流动纹理 / 模型表面”；
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
首次显示、目标 resize、Shader 成功重载、效果流程成功切换或手动重置都会清空历史。
UI 始终在全部 Pass 完成后按最终像素绘制，不进入模糊/反馈链。

源码改动仍先校验整包声明并编译 Shader，但只为当前选中效果分配候选目标、检查实际网格/格式/MSAA
管线，成功才统一替换。候选准备期间短暂保留当前效果的新旧两套目标，以便失败时保留有效预览；
其他效果不分配目标。编译期间继续调的参数在提交时迁移。
未选中效果使用的 Shader 仍编译并报告源码错误，首次使用前保持 `Ready`；选中后才创建 GPU Shader
和检查实际管线。已经使用过的 Shader 资源保留共享，切换时可直接用缓存代码检查新目标配置，
不重新编译 HLSL。切换中尚未就绪或检查失败的效果显示背景及诊断，不提交无效绘制。
当前帧循环、未知目标/字段和重复输出会拒绝加载。参数组和效果数量不设上限，每效果最多 32 个 Pass；
单轴目标尺寸最多 8192，目标格式/采样组合仍受所选 GPU 后端支持范围限制。

## 项目内容与生成文件

 .oshader、共享 HLSLI、图片和字体资产归项目；库仅提供工具代码。
发布使用 tools/shaders，同时生成材质清单与预编译字节码，不生成持久参数头文件。
编译器候选快照在私有临时目录中创建并清理。截图归入所属项目的 library/screenshots，
诊断副本归入 library/tmp，详见 [生成文件约定](../../../prompts/new-project.md#生成文件与目录纪律)。
参数组和效果按源码目录实际数量分配；候选整包成功后统一切换，失败保留上一版。

## 示例与检查入口

在 `olib_sample` 运行 `run.bat shader_lab`。可追加 `embedded` 查看带偏移的嵌入区域；
`source <目录>` 指定源码根目录。示例只负责启动接线，预览素材仍属于示例项目。
截图与故障注入代码位于示例仓库的 `tools/shader_lab_checks`，提供 `shot / colors / smoke / features / multipass`
入口；它们不进入库的工具包，也不是运行工具的必需依赖。仅选择与本次改动相关的检查，
不把这些示例作为新项目默认任务；旧入口若写到其他位置，留存产物应归并到上述固定目录。

检查期间只接受注入的输入，真实鼠标键盘被屏蔽，桌面上的操作不会混进自动点击。每一步都等明确状态
（注入已被一次渲染消费、候选包提交、效果就绪、窗口尺寸生效），不按帧数或经过的时间推测。
失败时完整状态与事件日志写到所属项目的 `library/tmp/shader-lab-<模式>-failure.txt`，每次运行开始时删除旧报告。

`features embedded d3d12` 集中检查预设往返、默认值、失败回滚、过期文件请求、图片热更新、
自定义预览和侧栏布局；不重复 smoke 的完整故障注入。原生对话框的实际选择由手动操作验收。

示例 `shaders/Trail2D.oshader` 和 `Trail3D.oshader` 定义拖尾效果：场景 → 半分辨率横向模糊 →
纵向模糊 → 上一帧反馈。`multipass embedded d3d12` 集中检查单 Pass 效果、2D/3D、HDR/MSAA、
反馈暂停/单步/重置/resize，以及循环依赖和错误 Shader 的回退恢复，不运行其它整套冒烟。

`hierarchy embedded d3d12` 集中检查显示名、folder、checkbox、最终/中间输出独立切换、显示名热改迁移，
效果列表只展示文件中声明的效果、显式单 Pass 扩成多 Pass 时的选择/参数保持，
2D/3D 列表隔离与状态恢复、浮层不挤动 Pass 列表、固定区域坐标及参数/设置滚动位置恢复，
以及普通、125% 和窄窗口的最终截图与输入命中；不运行其它完整故障注入。

`targets embedded d3d12` 集中检查仅选中效果持有目标、2D/3D 切换释放/重建、深度/MSAA、多 Pass resize、
反馈重置与参数保留、候选包按当前选择热重载、空效果包和恢复声明，以及实际点击 Texture Clear 后恢复棋盘格；
不跑完整 UI 点击序列或故障注入。

### 精灵材质 / 阴影 + 本体

`olib_sample` 的 `SpriteShadow.oshader` 使用 `.Sprite`：偏移阴影 + 本体。2D 工作区可选择该效果，
预览与游戏一样用 `r2d.image` 记录后 `submit`，游戏示例在 `src/material2d`。
`.Sprite` 和旧 `.Preview_Model` 的顶点 uniform 接口不同；不能只改 draw 类型而沿用旧 Shader。
整材质保存/载入同时适用于 Model 和 Sprite，按 Effect 名匹配，失败保留整个旧材质。
Shader 接口与业务接入见 [kit/rendering/2d](../../rendering/2d/README.md)。
