# Zed / ZedG 的 olib Shader 高亮

为 `.oshader` 提供 Properties、Pass、渲染状态与参数声明的高亮、文档大纲、括号匹配和缩进。
HLSLINCLUDE / HLSLPROGRAM 内部注入已有的 **HLSL** 语言，需要在 Zed 扩展中安装 HLSL。
不关联 Unity 的 `.shader`，也不需要项目级 file_types 配置。

## Windows 构建与安装

需要 PATH 中已有 Node.js / npm 和支持 WASI 的 Zig：

```powershell
./tools/zed-shader/build.ps1 -Install
```

脚本下载固定版本的 Tree-sitter CLI 与测试运行时到 `library/tmp/zed-shader-toolchain`，
在 `library/tmp/zed-shader-grammar` 生成解析器，在 `build/zed-shader` 输出扩展，
并运行语法、HLSL 区间、查询与 WASM 导入检查。
不带 `-Install` 时只构建和测试。

`-Install` 将构建结果复制到当前用户的 `%LOCALAPPDATA%/Zed/extensions/installed/olib-shader`。
ZedG 使用相同的扩展目录。编辑器会检测扩展变化；必要时重新打开 `.oshader` 文件，
右下角语言应为 **olib Shader**。如果手动选择过其他语言，改回 olib Shader。

这是本地预编译扩展，尚未发布到扩展市场。清单中的 `local-prebuilt` 是标记，
不能使用 Zed 的 Install Dev Extension 从该标记拉取语法仓库；请使用上面的脚本。

## 支持范围

外层语法来自 `grammar.js` 与 `scanner.c`，高亮与 HLSL 注入来自 `languages/olib-shader`。
HLSL 块的结束标记按独立行识别，注释和字符串中的 ENDHLSL 不会截断代码。

目前提供语法高亮，不提供 `.oshader` 的语言服务器、语义补全或跨块跳转。
不会把包含 Properties / Pass 的整个文件交给 HLSL 语言服务器。
Shader Lab 中的编译报错和热重载仍由原有开发流程提供。
