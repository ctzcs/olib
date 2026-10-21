"""把 Noto Sans CJK SC Regular 裁成 ImGui 内置字体子集（ASCII、Latin-1、GB2312）。"""

import argparse
import hashlib
from pathlib import Path
import sys

from fontTools import subset
from fontTools.ttLib import TTFont


SOURCE_SHA256 = "2C76254F6FC379FDDFCE0A7E84FB5385BB135D3E399294F6EEB6680D0365B74B"
DEFAULT_OUTPUT = Path(__file__).resolve().parents[2] / "assets" / "fonts" / "NotoSansCJKsc-Regular-subset.otf"


def charset():
	"""ImGui 只按码点取字形、不做塑形；GB2312 双字节区覆盖常用汉字与全角符号。"""
	codepoints = set(range(0x20, 0x7F)) | set(range(0xA0, 0x100)) | {0x2026}
	for high in range(0xA1, 0xF8):
		for low in range(0xA1, 0xFF):
			try:
				codepoints.add(ord(bytes([high, low]).decode("gb2312")))
			except UnicodeDecodeError:
				pass
	return sorted(codepoints)


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("source", type=Path, help="NotoSansCJKsc-Regular.otf")
	parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
	args = parser.parse_args()

	digest = hashlib.sha256(args.source.read_bytes()).hexdigest().upper()
	if digest != SOURCE_SHA256:
		sys.exit(f"源字体 SHA-256 不符：{digest}")
	options = subset.Options()
	options.layout_features = []  # ImGui 不做 GSUB/GPOS 塑形
	options.hinting = False
	options.name_IDs = ["*"]  # 保留版权与许可说明
	font = TTFont(args.source, recalcTimestamp=False)  # 保留源 head.modified，重复生成字节一致
	subsetter = subset.Subsetter(options)
	codepoints = charset()
	subsetter.populate(unicodes=codepoints)
	subsetter.subset(font)
	args.output.parent.mkdir(parents=True, exist_ok=True)
	font.save(args.output)
	covered = set(TTFont(args.output).getBestCmap())
	missing = [cp for cp in codepoints if cp not in covered]
	print(f"{args.output}: {args.output.stat().st_size} bytes, {len(covered)} codepoints")
	if missing:
		print("源字体没有的码点：" + " ".join(f"U+{cp:04X}" for cp in missing))


if __name__ == "__main__":
	main()
