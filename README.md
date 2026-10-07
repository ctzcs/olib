# olib

Odin 游戏库集合，内置 `foster/`（Foster 框架的 Odin 移植，原 OFoster 仓库）。
结构对位 [DragonLib](https://github.com/ctzcs/DragonLib)（C#/Foster）。

## 布局

```
core/        基础库（无引擎依赖）
├── handle/    代数句柄池：array（可扩容）/ fixed（定容）/ growing（arena）/ virtual（虚存）
├── entities/  轻量实体容器（union 变体 + 按组件迭代，Ravn 同源）
├── encoding/  json（Value 树 + struct）/ csv（表驱动配置）
├── tween/     补间系统（manager / sequence / 插值原语）
├── debug/     Tracking_Allocator 的 defer 包装
└── profiler/  作用域计时统计

foster/      Foster 框架的 Odin 移植（原 OFoster；保留 API、源码组织与 Git 历史）

engine/      引擎层（依赖 foster/）
├── asset/       资源管线：.meta 管身份、Library 管派生、blob 为边界、manifest 打包零改动
├── world/       Camera2D/Camera3D + Frustum3D/Ray3D + Matrix4 / SceneRouter
├── messaging/   CommandQueue（单消费者）/ BroadcastChannel（延迟一帧广播）
├── rendering/   Sprite / SpriteAtlas + Grid/Kenney 图集源 + Aseprite 构建器
├── rendering3d/ 3D 数据与队列层：Mesh 上传 / 材质状态 / 渲染排序
├── animation/   骨骼动画采样 / palette / 混合
├── dasset/      .dasset 模型格式数据层（比特兼容 DragonLib v4）
├── storage/     资源根 / 用户存档路径策略
├── app/         CLI 参数 + 调试控制台 + Game_App（using 嵌入 App）
├── audio/       SDL3 音频（设备流 / WAV 装载 / 播放）
└── ui/          clay 布局 + 位图/MSDF/裁剪后端 + 游戏控件/输入/缩放

thirdparty/  外部绑定：clay-odin / odin-imgui（含 Foster 后端）/ oflecs
```

## 使用

以 collection 方式引用（olib 根 = 仓库根）：

```sh
odin build <app> -collection:olib=<olib 路径>
```

```odin
import ha    "olib:core/handle/array"
import asset "olib:engine/asset"
import world "olib:engine/world"
import foster "olib:foster"
```

各模块文档见包内注释、[资源管线](engine/asset/README.md)与 [游戏 UI](engine/ui/README.md)。
游戏 UI 示例见 `examples/game_ui`（遗迹场景、HUD、技能冷却、格子背包、暂停菜单）；
基础控件验收页见 `examples/ui_gallery`。

## 测试

```sh
odin test core/handle/array -collection:olib=.
# 其余包同理：core/entities core/tween engine/asset engine/messaging engine/world ...
```

编码规范：[docs/CODE_STYLE.md](docs/CODE_STYLE.md)
移植路线图：[docs/ROADMAP.md](docs/ROADMAP.md)
