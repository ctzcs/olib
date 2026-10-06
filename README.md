# olib

Odin 游戏库集合，配合 [OFoster](https://github.com/ctzcs)（Foster 框架的 Odin 移植）使用。
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

engine/      引擎层（依赖 ofoster）
├── asset/     资源管线：.meta 管身份、Library 管派生、blob 为边界、manifest 打包零改动
├── world/     Camera2D（惰性矩阵）/ SceneRouter（屏幕路由）
└── messaging/ CommandQueue（单消费者）/ BroadcastChannel（延迟一帧广播）

thirdparty/  外部绑定：clay-odin / odin-imgui（含 ofoster 后端）/ oflecs
```

## 使用

以 collection 方式引用（olib 根 = 仓库根）：

```sh
odin build <app> -collection:olib=<olib 路径> -collection:ofoster=<OFoster/src 路径>
```

```odin
import ha    "olib:core/handle/array"
import asset "olib:engine/asset"
import world "olib:engine/world"
```

各模块文档见包内注释与 `engine/asset/README.md`。

## 测试

```sh
odin test core/handle/array -collection:olib=. -collection:ofoster=<OFoster/src>
# 其余包同理：core/entities core/tween engine/asset engine/messaging engine/world ...
```

编码规范：[docs/CODE_STYLE.md](docs/CODE_STYLE.md)
移植路线图：[docs/ROADMAP.md](docs/ROADMAP.md)
