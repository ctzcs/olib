# 默认图标打包

离线命令行工具，把 Game Icon Pack v1.4 的 `padding/128px/white` 目录合成一张
4096×4096 PNG 和 Kenney/Starling XML。使用方直接使用已生成资产，无需安装 Python。

重建需要 Python 3 和 Pillow（本次使用 Pillow 12.3.0）：

```powershell
python -m pip install Pillow==12.3.0
python tools/icons/build.py "../PatternWorld/Resources/Images/Game-Icon-Pack-v1.4-PNG/padding/128px/white"
```

默认输出固定到工具所在仓库的 `assets/icons/`，与当前工作目录无关。
临时比较使用 `--output library/tmp/icons`（在项目根执行），不另建根级输出目录。
正式图集仍保留在 assets，不能因为由工具生成就按缓存删除；遵循
[生成文件规则](../../prompts/new-project.md#生成文件与目录纪律)。按规范化名字排序，固定 128px 原图、
每边 2px 边缘扩展、每行 31 格；一张图最多容纳 961 个图标。
输入必须为 `分类/名称.png`，尺寸不是 128×128、名字重复、空输入或数量超限均报错。
新增/删除图标会改变后续坐标；应用只引用名字，不缓存原始坐标。

生成后自动核对全部图标的名称、SHA-256、原始像素与四边/四角隔离区。
只验证现有资产而不重写：

```powershell
python tools/icons/build.py "../PatternWorld/Resources/Images/Game-Icon-Pack-v1.4-PNG/padding/128px/white" --verify
```

PNG 保持 straight alpha，不做缩放、描边、去留白或预乘；运行时上传前预乘一次。
完整图集颜色不超过 256 种时使用精确调色板压缩，否则输出 RGBA；不做有损量化。
Pillow/zlib 版本变化可能改变压缩字节，但不应改变解码后的像素。
原图及其许可来自外部资源包；许可状态见 [资源说明](../../assets/icons/README.md)。
