# ImGui 内置字体

`NotoSansCJKsc-Regular-subset.otf` 是 Noto Sans CJK SC Regular 的子集，与 kit/ui 的 MSDF 图集同一字体，
供 `thirdparty/odin-imgui/imgui_impl_ofoster` 在 Init 时加载为 ImGui 主字体。按同目录 `OFL.txt` 分发。

- 源字体：NotoSansCJKsc-Regular.otf（notofonts/noto-cjk，Sans/OTF/SimplifiedChinese），
  SHA-256 `2C76254F6FC379FDDFCE0A7E84FB5385BB135D3E399294F6EEB6680D0365B74B`。
- 码点：ASCII、Latin-1、U+2026 与 GB2312 全部双字节字符（6763 个汉字及全角符号），共 7619 个。
- 去掉 hinting 与 GSUB/GPOS（ImGui 只按码点取字形，不做塑形），保留 name 表的版权与许可信息。

ImGui 1.92 按需光栅化字形，不需要像 MSDF 那样预先列出字符集；GB2312 以外的字（生僻字、繁体）
会显示为缺字。重建需要 Python 3 和 fontTools（本次使用 4.64.0），在 olib 根目录运行：

```powershell
python -m pip install fonttools==4.64.0
python tools/fonts/imgui_font.py path/to/NotoSansCJKsc-Regular.otf
```

脚本先校验源字体哈希，保留源 `head.modified`，同一版本重复生成字节一致。正式资产保留在 assets，
不按临时文件清理。
