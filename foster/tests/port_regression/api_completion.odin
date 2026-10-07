package main

import "core:fmt"
import "core:math"
import foster "olib:foster"

verify_api_completion :: proc() {
	assert(foster.ColorGrayscale(80, 128) == foster.Color{80, 80, 80, 128})
	assert(foster.CardinalFromString("lEfT") == foster.CardinalLeft)
	assert(foster.CardinalFromString("other") == foster.CardinalRight)
	assert(foster.SignsParse("-") == .Negative && foster.SignsFromInt(0, .Negative) == .Negative)
	overlaps, amount := foster.AxisOverlaps(0, 4, 3, 8)
	assert(overlaps && amount == -1)
	overlaps, _ = foster.AxisOverlaps(0, 4, 4, 8)
	assert(!overlaps)

	provider := foster.InputProviderMake()
	foster.InputProviderText(&provider, "hello")
	foster.InputProviderText(&provider, "😀中文")
	foster.InputProviderUpdate(&provider, {})
	assert(provider.Input.State.Keyboard.Text == "hello😀中文")
	foster.InputProviderText(&provider, "next")
	assert(provider.Input.State.Keyboard.Text == "hello😀中文")
	foster.InputProviderUpdate(&provider, {})
	assert(provider.Input.State.Keyboard.Text == "next")
	assert(provider.Input.LastState.Keyboard.Text == "hello😀中文")
	foster.InputProviderDispose(&provider)
	foster.InputProviderDispose(&provider)

	assert(foster.FromHexStringRGB("#12ABef") == foster.Color{0x12, 0xab, 0xef, 255})
	assert(foster.FromHexStringRGBA("0x01020380") == foster.Color{1, 2, 3, 128})
	assert(foster.FromHexString("ARGB", "8012ABef") == foster.Color{0x12, 0xab, 0xef, 128})
	hex := foster.ToHexString({0x12, 0xab, 0xef, 128}, "bgra")
	assert(hex == "EFAB1280")
	delete(hex)
	assert(foster.FromHexStringRGB("FFzz10") == foster.Color{255, 0, 16, 255})
	assert(foster.ColorToVector3({255, 0, 255, 128}) == [3]f32{1, 0, 1})

	list: foster.StackList4(int)
	foster.StackListAdd(&list, 1)
	foster.StackListAdd(&list, 3)
	foster.StackListInsert(&list, 1, 2)
	assert(list.Count == 3 && list.Data == [4]int{1, 2, 3, 0})
	assert(foster.StackListIndexOf(&list, 2) == 1)
	assert(foster.StackListRemove(&list, 2) && !foster.StackListContains(&list, 2))
	destination: [4]int
	foster.StackListCopyTo(&list, destination[:], 1)
	assert(destination == [4]int{0, 1, 3, 0})
	foster.StackList4Clear(&list)
	assert(list.Count == 0 && list.Data == [4]int{})

	polygon := foster.PolygonMake({0, 0}, {2, 0}, {0, 2})
	defer delete(polygon.Vertices)
	defer delete(polygon.Indices)
	foster.PolygonInsert(&polygon, 2, {2, 2})
	assert(foster.PolygonArea(&polygon) == 4 && len(polygon.Indices) == 6)
	assert(foster.PolygonIndexOf(&polygon, {2, 2}) == 2)
	foster.PolygonSetVertex(&polygon, 2, {4, 2})
	assert(foster.PolygonArea(&polygon) == 6)
	assert(foster.PolygonRemove(&polygon, {4, 2}) && len(polygon.Indices) == 3)

	triangles := foster.TriangulateOwned(polygon.Vertices[:])
	assert(len(triangles) == 3)
	delete(triangles)
	indices: [dynamic]int
	enumerable := foster.TriangulateAndEnumerate(polygon.Vertices[:], &indices)
	enumerator := foster.TriangulationEnumeratorGet(enumerable)
	assert(
		foster.TriangulationMoveNext(&enumerator) && foster.TriangleArea(enumerator.Current) == 2,
	)
	assert(!foster.TriangulationMoveNext(&enumerator))
	delete(indices)
	pooled := foster.TriangulateAndEnumeratePooled(polygon.Vertices[:])
	assert(len(pooled.Triangles) == 3)
	assert(foster.AsPoint3({1, -2, 3, 4}) == foster.Point3{1, -2, 3})

	archive: foster.ZipStorage
	data :: #load("storage.zip")
	foster.ZipStorageInitBytes(&archive, data)
	assert(foster.FileExists(foster.ZipStorageContainer(&archive), "raw.bin"))
	assert(archive.Error == .None)
	zip64 := #load("zip64.zip")
	foster.ZipStorageInitBytes(&archive, zip64)
	assert(archive.Error == .None)
	contents := foster.ZipStorageReadAllBytes(&archive, "nested/zip64.txt")
	assert(string(contents) == "zip64 payload")
	delete(contents)
	corrupt := make([]u8, len(zip64))
	copy(corrupt, zip64)
	corrupt[30 + len("nested\\zip64.txt") + 20] ~= 1
	foster.ZipStorageInitBytes(&archive, corrupt)
	assert(archive.Error == .ChecksumMismatch && len(archive.Entries) == 0)
	delete(corrupt)
	// Every incomplete prefix must fail cleanly, without leaving partially decoded entries.
	for size in 0 ..< len(zip64) {
		foster.ZipStorageInitBytes(&archive, zip64[:size])
		assert(archive.Error != .None && len(archive.Entries) == 0)
	}
	foster.ZipStorageDispose(&archive)

	texture := foster.Texture {
		Width  = 1,
		Height = 1,
	}
	font := foster.SpriteFontMake(nil, 10)
	defer foster.SpriteFontDispose(&font)
	font.LineHeight = 12
	font.Descent = -10
	codepoints := []int{'A', 'V'}
	for codepoint in codepoints {
		foster.SpriteFontAddCharacter(&font, {
			Codepoint  = codepoint,
			Subtexture = foster.SubtextureMake(&texture, {0, 0, 1, 1}, {0, 0, 1, 1}),
			Advance    = 10,
			Exists     = true,
		})
	}
	foster.SpriteFontSetKerning(&font, 'A', 'V', -2)
	assert(foster.SpriteFontWidthOf(&font, "AV", 20) == 36)
	batch := foster.BatcherMake()
	defer foster.BatcherDispose(&batch)
	foster.SpriteFontDraw(&batch, &font, "AV", {}, 20, foster.White)
	assert(len(batch.Vertices) == 8 && batch.Vertices[4].Pos[0] == 16)
	foster.BatcherClear(&batch)
	foster.SpriteFontDrawSineWave(
		&batch,
		&font,
		"A",
		{},
		{},
		20,
		foster.White,
		math.PI / 2,
		0,
		{3, 0},
	)
	assert(math.abs(batch.Vertices[0].Pos[0] - 3) < .0001)
	foster.BatcherClear(&batch)
	foster.SpriteFontDrawWrapped(&batch, &font, "A\nV", {}, 20, 20, foster.White)
	assert(len(batch.Vertices) == 8 && batch.Vertices[4].Pos[1] == 24)
	fmt.println(
		"PASS: hex component order, StackList mutation, polygon mutation, memory ZIP, scaled kerning and sine/wrapped text",
	)
}
