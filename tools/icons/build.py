"""把 Game Icon Pack 的 padding/128px/white 目录打包成内置图集。"""

import argparse
import hashlib
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from PIL import Image


ATLAS_SIZE = 4096
ICON_SIZE = 128
PADDING = 2
STRIDE = ICON_SIZE + PADDING * 2
COLUMNS = ATLAS_SIZE // STRIDE
DEFAULT_OUTPUT = Path(__file__).resolve().parents[2] / "assets" / "icons"


def collect(source: Path):
	"""名字保留分类，去掉原目录中的排序前缀；拒绝覆盖同名图标。"""
	entries = {}
	for path in sorted(source.rglob("*.png")):
		relative = path.relative_to(source)
		if len(relative.parts) != 2:
			raise ValueError(f"预期 分类/名称.png：{relative}")
		category = re.sub(r"^\d+-", "", relative.parts[0])
		name = f"{category}/{path.stem}"
		if name in entries:
			raise ValueError(f"重复图标名：{name}")
		entries[name] = (path, relative.as_posix())
	if not entries:
		raise ValueError(f"没有找到 PNG：{source}")
	if len(entries) > COLUMNS * COLUMNS:
		raise ValueError(f"图标数量 {len(entries)} 超过容量 {COLUMNS * COLUMNS}")
	return sorted(entries.items())


def extrude(atlas: Image.Image, icon: Image.Image, x: int, y: int):
	"""保留完整原图，向隔离区复制边缘，避免线性采样读到相邻图标。"""
	atlas.paste(icon, (x, y))
	for offset in range(1, PADDING + 1):
		atlas.paste(icon.crop((0, 0, 1, ICON_SIZE)), (x - offset, y))
		atlas.paste(icon.crop((ICON_SIZE - 1, 0, ICON_SIZE, ICON_SIZE)),
			(x + ICON_SIZE - 1 + offset, y))
		atlas.paste(icon.crop((0, 0, ICON_SIZE, 1)), (x, y - offset))
		atlas.paste(icon.crop((0, ICON_SIZE - 1, ICON_SIZE, ICON_SIZE)),
			(x, y + ICON_SIZE - 1 + offset))
	for dx, sx in ((-PADDING, 0), (ICON_SIZE, ICON_SIZE - 1)):
		for dy, sy in ((-PADDING, 0), (ICON_SIZE, ICON_SIZE - 1)):
			atlas.paste(icon.getpixel((sx, sy)),
				(x + dx, y + dy, x + dx + PADDING, y + dy + PADDING))


def build(source: Path, output: Path):
	entries = collect(source)
	atlas = Image.new("RGBA", (ATLAS_SIZE, ATLAS_SIZE), (0, 0, 0, 0))
	root = ET.Element("TextureAtlas", {
		"imagePath": "game-icons.png", "width": str(ATLAS_SIZE),
		"height": str(ATLAS_SIZE), "padding": str(PADDING),
		"sourcePack": "Game-Icon-Pack-v1.4-PNG/padding/128px/white",
	})
	for index, (name, (path, relative)) in enumerate(entries):
		with Image.open(path) as original:
			if original.size != (ICON_SIZE, ICON_SIZE):
				raise ValueError(f"{relative} 尺寸为 {original.size}，预期 128x128")
			icon = original.convert("RGBA")
		x = index % COLUMNS * STRIDE + PADDING
		y = index // COLUMNS * STRIDE + PADDING
		extrude(atlas, icon, x, y)
		ET.SubElement(root, "SubTexture", {
			"name": name, "x": str(x), "y": str(y),
			"width": str(ICON_SIZE), "height": str(ICON_SIZE),
			"source": relative, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
		})
	ET.indent(root, space="\t")
	xml_bytes = ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"
	output.mkdir(parents=True, exist_ok=True)
	png_path = output / "game-icons.png"
	xml_path = output / "game-icons.xml"
	# 原图颜色数不超过 256 时用精确调色板压缩，不做有损量化。
	colors = atlas.getcolors(256)
	if colors is not None:
		palette = sorted(color for _, color in colors)
		lookup = {int.from_bytes(bytes(color), sys.byteorder): index
			for index, color in enumerate(palette)}
		pixels = memoryview(atlas.tobytes()).cast("I")
		indexed = Image.frombytes("P", atlas.size, bytes(lookup[pixel] for pixel in pixels))
		indexed.putpalette(bytes(channel for color in palette for channel in color[:3]))
		indexed.save(png_path, optimize=True, transparency=bytes(color[3] for color in palette))
	else:
		atlas.save(png_path, optimize=True)
	xml_path.write_bytes(xml_bytes)
	verify(source, output)
	print(f"{len(entries)} icons -> {png_path} ({png_path.stat().st_size:,} bytes)")
	print(f"Index: {xml_path} ({len(xml_bytes):,} bytes); GPU: 64 MiB RGBA8, no mipmaps")


def verify(source: Path, output: Path):
	"""核对覆盖范围、源文件指纹和全部像素（包括采样隔离区）。"""
	expected = dict(collect(source))
	root = ET.parse(output / "game-icons.xml").getroot()
	seen = set()
	with Image.open(output / "game-icons.png") as encoded:
		atlas = encoded.convert("RGBA")
	if atlas.size != (ATLAS_SIZE, ATLAS_SIZE):
		raise ValueError("图集尺寸不符")
	for index, entry in enumerate(root.findall("SubTexture")):
		name = entry.attrib["name"]
		if name in seen or name not in expected:
			raise ValueError(f"索引重名或缺少源文件：{name}")
		seen.add(name)
		path, relative = expected[name]
		if entry.attrib["source"] != relative:
			raise ValueError(f"源路径不符：{name}")
		if entry.attrib["sha256"] != hashlib.sha256(path.read_bytes()).hexdigest():
			raise ValueError(f"源文件指纹不符：{name}")
		x, y, width, height = (int(entry.attrib[k]) for k in ("x", "y", "width", "height"))
		if (x, y, width, height) != (
			index % COLUMNS * STRIDE + PADDING,
			index // COLUMNS * STRIDE + PADDING, ICON_SIZE, ICON_SIZE,
		):
			raise ValueError(f"索引坐标不符：{name}")
		with Image.open(path) as original:
			icon = original.convert("RGBA")
		if atlas.crop((x, y, x + width, y + height)).tobytes() != icon.tobytes():
			raise ValueError(f"图标像素不符：{name}")
		# 独立逐像素校验四边与四角，不复用 extrude 实现。
		for local_y in range(-PADDING, ICON_SIZE + PADDING):
			for local_x in range(-PADDING, ICON_SIZE + PADDING):
				if 0 <= local_x < ICON_SIZE and 0 <= local_y < ICON_SIZE:
					continue
				sample = icon.getpixel((max(0, min(ICON_SIZE - 1, local_x)),
					max(0, min(ICON_SIZE - 1, local_y))))
				if atlas.getpixel((x + local_x, y + local_y)) != sample:
					raise ValueError(f"隔离区像素不符：{name}")
	if seen != expected.keys():
		raise ValueError("索引未包含全部源图标")
	print(f"Verified {len(seen)} icons: names, source hashes, pixels and gutters")


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("source", type=Path, help="原包的 padding/128px/white 目录")
	parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
	parser.add_argument("--verify", action="store_true", help="仅核对已有图集，不重写")
	args = parser.parse_args()
	try:
		if args.verify:
			verify(args.source, args.output)
		else:
			build(args.source, args.output)
	except (OSError, ValueError, KeyError, ET.ParseError) as error:
		parser.exit(1, f"{error}\n")


if __name__ == "__main__":
	main()
