# kit/ui 补齐玩家 UI 常用控件

## 背景

kit/ui 的 ROADMAP 列着文本输入 / IME、下拉框、拖放、列表虚拟化与焦点自动滚动。编辑器已改用 ImGui，
这里只补玩家 UI 常用的部分；富文本、字体回退、过渡动画、圆角遮罩不在本次范围。

## 已定决策

1. **焦点自动滚动**：导航或 `ui_focus` 改变焦点后，按上一帧布局把包含该控件的滚动区滚到可见范围。
2. **下拉框** `ui_dropdown`：按钮显示当前项，点开后在按钮下方浮层列出选项（超过 6 项时可滚动）；
   点选、点外面或取消导航关闭；同一时间只开一个。
3. **列表虚拟化**：`ui_virtual_range` 按滚动位置和固定行高算出可见区间，调用方只声明这几行，
   前后用 `ui_virtual_spacer` 占位；滚动条长度与完整列表一致。
4. **拖放**：`ui_drag_source`（基于 `ui_interact` 的结果，按下后移动超过阈值才开始）与
   `ui_drop_target`（松开时指针在目标上返回载荷）；载荷是调用方定义的 int。拖动结束的那次松开不算点击；
   跟随指针的预览由调用方用 `ui_drag_position` 画浮层。
5. **文本输入** `ui_text_input`：单行，UTF-8 写入调用方的 `[dynamic]u8`，有长度上限；光标、点击定位、
   退格/删除/左右/Home/End、Enter 提交、Escape 失焦、粘贴文本；长文本水平滚动跟随光标；占位文字。
   键盘输入由宿主每帧经 `ui_set_text_edit` 传入（本帧键入文字含输入法提交、编辑键、剪贴板）。
   `ui_text_editing` 告诉宿主何时打开系统文字输入、不把按键给游戏；`ui_text_input_area` 给出光标的
   渲染目标像素矩形，宿主交给 foster 新增的 `SetTextInputArea`（L-022），定位输入法候选框。
   不做选区、多行和密码掩码。
6. 演示放进 olib_sample 的 ui_gallery（不碰正在修改的 ui_motion 和 README）。

## 执行步骤

1. kit/ui：焦点自动滚动、下拉框、虚拟列表、拖放，配 CPU 单元测试。提交 `ui: 下拉框、虚拟列表、拖放与焦点自动滚动`。
2. foster `SetTextInputArea`（L-022）；kit/ui 文本输入与测试。提交 `foster(local): L-022 …` 与 `ui: 单行文本输入与输入法候选框定位`。
3. olib_sample ui_gallery 演示新控件并截图；kit/ui README、ROADMAP、new-project 控件表更新。
   提交 `samples: ui_gallery 演示新控件` 与 `docs: kit/ui 新控件`。
4. 按 docs/plans/README.md 归档本计划。

## 验收

- `odin run tools/check` 全部通过（含 kit/ui 单元测试与示例编译）。
- ui_gallery `shot` 截图显示下拉框展开、文本框、拖放背包和虚拟列表；本机输入法候选框位置由用户手动验收。

## 禁止事项

- 不改 foster 默认行为；不提交两个仓库中与本计划无关的已有改动。

## 汇报内容

- 每步 commit、测试与 check 结果、截图路径、未实现的部分。
