# 窗口与 UI 跟随系统显示缩放

## 背景

Windows 上 SDL3 的窗口坐标是物理像素：系统缩放 150% 的 4K 屏上，配置 960×720 的窗口真的只有
960×720 像素，看起来是设计尺寸的 2/3。模板游戏 UI 的缩放固定为 `services.scale`（1，测试参数 1.25），
不乘系统缩放；ImGui 后端只在 Init 读一次 DPI，窗口换到缩放不同的屏幕不会更新。macOS 的窗口坐标是点，
系统已放大，不能再乘。

## 已定决策

1. 唯一缩放来源：`foster.ContentScale(window)`（SDL GetWindowDisplayScale，逻辑单位到绘制像素）。
   窗口要放大的倍数 = 显示缩放 ÷ 像素密度（Windows 150% 为 1.5，macOS Retina 为 1）。
2. foster 增加默认关闭的 `AppFlag.LogicalWindowSize`：窗口创建后（仍隐藏）按上式放大配置尺寸并重新居中，
   再由 Run 显示，不闪。登记 LOCAL_CHANGES。示例与截图检查不打开，像素尺寸不变。
3. ImGui 后端每帧按“显示缩放 ÷ 像素密度”更新字体与间距：第一帧捕获宿主定制后的样式作为基准，
   缩放变化时从基准重算，不累乘；宿主每帧设置的字号（FontSizeBase / FontScaleMain）保留。
4. 模板游戏 UI 与常驻入口的失败提示、性能面板：kit/ui 缩放 = `foster.ContentScale` × `services.scale`
   （测试参数），集中在 core 的一个函数里，玩家 UI 缩放设置以后乘在这里。
5. 模板 editor / game 入口打开 `LogicalWindowSize`；Web 不受影响。

## 执行步骤

1. foster：`LogicalWindowSize` 与 LOCAL_CHANGES 登记。提交 `foster: 可选按逻辑尺寸创建窗口`。
2. imgui_ofoster：每帧跟随显示缩放。提交 `imgui_ofoster: 每帧跟随显示缩放`。
3. 模板：入口开启开关，游戏 UI / 失败提示 / 性能面板乘显示缩放；README、AGENTS、new-project、kit/ui 文档。
   提交 `new-game: 窗口与 UI 跟随系统显示缩放`。
4. 按 docs/plans/README.md 归档本计划。

## 验收

- `odin run tools/check` 全部通过；Shader Lab 检查模式不受影响（开关关闭）。
- 本机（4K 150%）生成项目运行：窗口为 1440×1080 像素且居中，游戏文字与编辑器文字都按 1.5 倍；截图存 library/screenshots。

## 禁止事项

- 不改 foster 默认行为；不提交两个仓库里与本计划无关的改动。

## 汇报内容

- 每步 commit、check 结果、截图路径、未能验证的平台与场景。
