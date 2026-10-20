# Shader 开发与热重载（2D / 3D）

Shader Lab 使用 [单文件 .oshader](../lang/README.md)：Properties、Pass、渲染状态和
HLSL 在同一文件维护。保存后参数与代码一起验证，失败保留上一版画面和参数。
旧的 Odin 参数包发现、临时生成程序与持久参数头文件流程已经移除。

shader/dev 是开发构建使用的桌面扩展，不持有 App、相机或场景。后台编译候选版本，
渲染线程使用实际 DrawCommand 检查管线，成功后替换两个 Shader。
发布入口不依赖本包；通过 tools/shaders 生成字节码和材质清单。

## 使用 Shader Lab

在同级 olib_sample 目录运行：

```bat
run.bat shader_lab d3d12
run.bat shader_lab vulkan
```

需要 odin 和 shadercross 在 PATH 中。首次启动自动编译；保存 .oshader 或共享 HLSLI 后自动重载。
使用 source <目录> 指定源码根目录。示例 Preview2D / Preview3D、拖尾、描边和精灵材质
都位于 src/shader_lab/shaders，参数与程序正文均在对应的 .oshader 内。
Zed / ZedG 高亮见 [扩展说明](../../../../tools/zed-shader/README.md)。

工具支持 2D 全屏/精灵、3D 球体/立方体、滑条、向量、调色板、贴图、预设、多 Pass 和历史帧。
面板操作只修改预览实例值，不写回源码。声明、布局与控件规则见 [shader/lang](../lang/README.md)，
宿主嵌入与输入规则见 [Shader Lab](../../../tools/shader_lab/README.md)。

## 候选包 API

- parameters_compile(source_directory) 同步读取目录中的 .oshader，返回 Parameter_Build。
- programs 与 schemas 按相同顺序排列，持有每个 Pass 的源码快照；effects 持有效果定义。
- parameters_init(watch, source_directory) / parameters_update / parameters_take / parameters_dispose
  提供后台发现与监听。Watch 必须保持地址稳定。
- parameters_take 返回拥有的数据；使用 parameter_build_dispose 释放。
- 使用程序的 source 初始化 Session，将程序快照复制到 source_text，并调用
  configure_parameters(session, texture_count) 保留生成布局的完整资源槽。片元至少保留 b0 帧块、b1 参数两个 uniform 槽；
  init 约定了更多槽时保留，例如 Shader Lab 给 Model 参数组约定顶点 2、片元 3 个槽（视图块）。
- 参数、纹理、目标与程序作为一个候选包提交。不要单独提交其中某个程序，避免布局不匹配。
  Shader Lab 已实现整包验证、旧值迁移、失败回退和过期候选丢弃。

参数的 HLSL 声明直接包含在源码快照中，无需写入或 include 头文件。
Properties 支持声明式默认值；不执行 Odin 默认值函数。

## 游戏开发入口接入

`Session` 必须保持地址稳定。它拥有两个 Shader 和对应字节码，材质借用其地址。
`init` 的资源数量应与宿主提供的 uniform 和纹理一致：

```odin
import dev "olib:kit/rendering/shader/dev"
import foster "olib:foster"

// state.live 与 state.material 是宿主持有的稳定字段。
ok := dev.init(&state.live, "content/shaders/MyEffect.hlsl", device.Driver,
    {uniform_buffers = 1},
    {uniform_buffers = 1, samplers = 1})
foster.MaterialInitWithShaders(&state.material, &state.live.vertex, &state.live.fragment)

// UpdateProc：检测保存，后台编译，不在渲染线程运行编译器。
dev.update(&state.live, f64(app.Time.Delta))

// RenderProc：在提交任何相关绘制、或向 Batcher 排队之前。
// probes 是宿主用实际 mesh/target/blend/depth/MSAA 构造的 DrawCommand 切片。
// 覆盖该 Shader 的全部绘制配置；通常在窗口离屏目标创建/更新后构造。
_ = dev.apply(&state.live, device, probes)
if state.live.revision > 0 {
    // 照常设置 state.material 的 uniform/纹理并绘制。
}

// ShutdownProc：先释放借用者，再释放 Session，最后释放 GraphicsDevice。
foster.MaterialDispose(&state.material)
dev.dispose(&state.live)
```

`init` 返回 false 时仍应调用 `dispose`。`diagnostic` 借用到下一次状态变化/销毁；
`retry` 重新尝试当前文件。内部跨线程数据使用系统 heap allocator，
不借用调用方的帧临时分配器。退出时等待正在运行的编译器结束。

## 重载契约与边界

- 每 250ms 检查源码散列，稳定至少 250ms 后编译；一个会话同时只有一个任务。
  编译期间再次保存会使过期结果被丢弃。
- 递归监测 .oshader / .hlsl / .hlsli。普通 include 必须位于源码目录树内；
  不支持外部 include 或符号链接依赖。两个阶段使用同一份私有临时快照，结束后清理。
- vertex_main / fragment_main 为固定入口。开发期只生成当前驱动需要的 SPIR-V、DXIL 或 MSL，
  不覆盖 Compiled 发布产物。底层 Session 仍支持普通 HLSL 热重载，用于引擎自身着色器。
- SPIR-V 反射验证资源数量，不自动检测手写 cbuffer 的字段偏移、语义或槽位重排。
  引擎接口修改后需同步宿主并重启。Properties 的 HLSL 与字节布局来自同一描述。
- 生成布局允许优化掉未使用的资源，但不允许超过声明上限；保留原槽位避免字段移位。
  GPU 检查仅覆盖调用方提供的 probes，必须涵盖实际顶点格式、目标、混合、深度与 MSAA。
- 桌面支持 Vulkan / D3D12 / Metal；Metal 仍需 macOS 实机验证。WebGL/JS、compute 不在范围内。

## 检查

```bat
odin run tools/check -- -only:kit/shader
odin run tools/check
```

olib_sample 的 smoke 验证 HLSL / Properties 错误恢复、布局迁移、纹理、发现与 UI；
multipass 验证拓扑、反馈、目标与整包回退；features / hierarchy / targets 提供针对性检查。
测试修改独立临时副本，最终输出截图保存到示例项目 library/screenshots。
