# 模板离线字体

PNG 与 JSON 来自 Noto Sans CJK SC Regular 的离线 MSDF 图集，按同目录 OFL.txt 分发。
模板自身携带图集、字符集与许可，生成时不读取 olib_sample，也不下载或依赖系统字体。

源字体：NotoSansCJKsc-Regular.otf（notofonts/noto-cjk，Sans/OTF/SimplifiedChinese）。
源 SHA-256：`2C76254F6FC379FDDFCE0A7E84FB5385BB135D3E399294F6EEB6680D0365B74B`。
图集由 msdf-atlas-gen 1.4 生成：

```text
msdf-atlas-gen -font NotoSansCJKsc-Regular.otf -charset charset.txt -type msdf -format png -size 48 -pxrange 8 -yorigin top -seed 0 -imageout ui.png -json ui.json
```

初始图集从 olib_sample 的共用离线资产整理而来，包含 ASCII 与有限中文字符，不是完整 CJK 字库。
增加文本前更新 charset.txt 并重新生成 PNG/JSON；宿主嵌入字体，需要重编并重启。
