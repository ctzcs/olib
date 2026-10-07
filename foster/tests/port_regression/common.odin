package main

import "core:fmt"
import "core:io"
import foster "ofoster:."

verify_common :: proc() {
	verify_api_completion()
	verify_font_memory()
	polygon := foster.PolygonMake({0, 0}, {4, 0}, {4, 1}, {1, 1}, {1, 4}, {0, 4})
	defer delete(polygon.Vertices)
	defer delete(polygon.Indices)
	assert(foster.PolygonArea(&polygon) == 7)
	assert(len(polygon.Indices) == 12)
	area: f32
	for i := 0; i < len(polygon.Indices); i += 3 {
		triangle := foster.Triangle {
			polygon.Vertices[polygon.Indices[i]],
			polygon.Vertices[polygon.Indices[i + 1]],
			polygon.Vertices[polygon.Indices[i + 2]],
		}
		area += foster.TriangleArea(triangle)
		assert(foster.PolygonContains(polygon, (triangle.A + triangle.B + triangle.C) / 3))
	}
	assert(area == 7)
	// Reversing winding must preserve the same concave region.
	for i in 0 ..< len(polygon.Vertices) / 2 {
		j := len(polygon.Vertices) - 1 - i
		polygon.Vertices[i], polygon.Vertices[j] = polygon.Vertices[j], polygon.Vertices[i]
	}
	foster.PolygonTriangulate(&polygon)
	assert(len(polygon.Indices) == 12 && foster.PolygonArea(&polygon) == 7)
	assert(foster.RectClosestPointOnEdges({0, 0, 10, 10}, {3, 4}) == foster.Vec2{0, 4})
	assert(foster.RectClosestPointOnEdges({0, 0, 10, 10}, {13, -4}) == foster.Vec2{10, 0})
	assert(foster.IntervalCount(1.1, .9, .25) == 4)
	assert(foster.DifferenceFromInterval(-.1, 1) > .099)
	assert(foster.EaseApply(foster.EaseCube, 0) == 0 && foster.EaseApply(foster.EaseCube, 1) == 1)
	assert(foster.EaseApply(foster.EaseCube, .5) == .5)
	assert(foster.EaseCube.Out(.5) == .875 && foster.EaseCube.InOut(.5) == .5)
	rng := foster.RngMake(0)
	assert(foster.RngU64(&rng) == 0xe220a8397b1dcdaf)
	rng = foster.RngMake(0)
	assert(foster.RngIntMax(&rng, 100) == 67)
	rng = foster.RngMake(0)
	assert(foster.RngFloat(&rng) == f32(.7666215896606445))
	rng = foster.RngMake(0)
	assert(foster.RngDouble(&rng) == .7666216164272852)
	vector, ok := foster.Vector2FromJson(`{"y":-2.5,"ignored":{},"x":4}`)
	assert(ok && vector == foster.Vec2{4, -2.5})
	vector, ok = foster.Vector2FromJson(`[4,"skip",-2.5,100]`)
	assert(ok && vector == foster.Vec2{4, -2.5})
	serialized := foster.Vector2ToJson(vector)
	defer delete(serialized)
	parsed, parsed_ok := foster.Vector2FromJson(serialized)
	assert(parsed_ok && parsed == vector)
	_, ok = foster.Vector2FromJson(`invalid`)
	assert(!ok)
	transform, matrix_ok := foster.Matrix3x2FromJson(`[1,0,0,1,12,24]`)
	assert(matrix_ok && transform.M31 == 12 && transform.M32 == 24)
	integers: [2]int
	converter := foster.IntVectorJsonConverter {
		Components = {{"X", "Width"}, {"Y", "Height"}},
	}
	assert(
		foster.IntVectorJsonRead(converter, `{"height":7,"width":5}`, integers[:]) &&
		integers == [2]int{5, 7},
	)
	values := [3]int{4, -2, 9}
	assert(foster.IndexOfSmallest(values[:]) == 1 && foster.IndexOfLargest(values[:]) == 2)

	input: foster.Input
	foster.InputInit(&input, nil)
	defer foster.InputDispose(&input)
	provider := foster.InputProvider {
		Input = &input,
	}
	set: foster.AxisBindingSet
	defer delete(set.Entries)
	foster.AxisBindingSetAddKeys(&set, .Left, .Right)
	foster.InputProviderKey(&provider, .Right, true, 1)
	foster.InputProviderText(&provider, "hello")
	foster.InputProviderUpdate(&provider, foster.Time{Elapsed = 2, Delta = .016})
	assert(foster.AxisBindingSetValue(&set, &input, 0) == 1)
	assert(foster.AxisBindingSetPressedSign(&set, &input, 0) == 1)
	assert(input.State.Keyboard.Text == "hello")
	foster.InputProviderUpdate(&provider, foster.Time{Elapsed = 3, Delta = .016})
	assert(foster.AxisBindingSetValue(&set, &input, 0) == 1)
	assert(foster.AxisBindingSetPressedSign(&set, &input, 0) == 0)
	actions: foster.ActionBindingSet
	defer delete(actions.Entries)
	foster.ActionBindingSetAddKey(&actions, .Right, "menu")
	defer delete(actions.Entries[0].Masks)
	filters := [1]string{"game"}
	input.BindingFilters = filters[:]
	assert(!foster.ActionBindingSetGetState(&actions, &input, 0).Down)
	filters[0] = "menu"
	assert(foster.ActionBindingSetGetState(&actions, &input, 0).Down)
	motion := foster.BindingFromMouseMotion(foster.MouseMotionBindingMake({1, 0}, 1, 5, 25))
	input.State.Mouse.Delta = {15, 0}
	input.LastState.Mouse.Delta = {0, 0}
	state := foster.BindingGetState(motion, &input, 0)
	assert(state.Value == .5 && state.Pressed && !state.Released)
	input.LastState.Mouse.Delta = {15, 0}
	state = foster.BindingGetState(motion, &input, 0)
	assert(state.Down && !state.Pressed)
	input.State.Mouse.Delta = {0, 0}
	state = foster.BindingGetState(motion, &input, 0)
	assert(!state.Down && state.Released)
	fmt.println(
		"PASS: concave triangulation, spatial/time/ease helpers, JSON converters, input filters and press transitions",
	)
}

verify_zip :: proc(storage: ^foster.StorageContainer) {
	writer, write_err := foster.Create(storage, "stream.bin")
	assert(write_err == .None)
	count, write_error := io.write_string(writer, "hello world")
	assert(count == 11 && write_error == .None)
	assert(io.flush(writer) == .None)
	_, seek_error := io.seek(writer, 6, .Start)
	assert(seek_error == .None)
	count, write_error = io.write_string(writer, "Odin")
	assert(count == 4 && write_error == .None)
	binary := [2]u8{0, 255}
	count, write_error = io.write_at(writer, binary[:], 14)
	assert(count == 2 && write_error == .None)
	assert(io.close(writer) == .None)
	assert(io.destroy(writer) == .None)
	written := foster.ReadAllBytes(storage, "stream.bin")
	defer delete(written)
	assert(len(written) == 16 && string(written[:11]) == "hello Odind")
	assert(
		written[11] == 0 &&
		written[12] == 0 &&
		written[13] == 0 &&
		written[14] == 0 &&
		written[15] == 255,
	)
	assert(foster.Remove(storage, "stream.bin"))
	archive_bytes :: #load("storage.zip")
	assert(foster.WriteAllBytes(storage, "archive.zip", archive_bytes))
	archive: foster.ZipStorage
	foster.ZipStorageInit(&archive, fmt.tprintf("%s/archive.zip", storage.Root))
	defer foster.ZipStorageDispose(&archive)
	container := foster.ZipStorageContainer(&archive)
	assert(!container.Writable)
	_, denied := foster.Create(container, "denied.txt")
	assert(denied == .Permission_Denied)
	// ZIP names must remain valid after the archive input buffer is released.
	free_all(context.temp_allocator)
	assert(
		foster.FileExists(container, "raw.bin") && foster.DirectoryExists(container, "emptydir"),
	)
	assert(foster.DirectoryExists(container, "nested") && !foster.FileExists(container, "nested"))
	relative: foster.RelativeStorage
	foster.RelativeStorageInit(&relative, container^, "nested")
	nested := foster.RelativeStorageContainer(&relative)
	message := foster.ReadAllText(&nested, "message.txt")
	defer delete(message)
	assert(message == "hello from deflate")
	names := foster.EnumerateDirectory(container, "")
	assert(len(names) == 4)
	for name in names {
		delete(name)
	}
	delete(names)
	filtered := foster.EnumerateDirectory(container, search_pattern = "*.txt", recursive = true)
	assert(len(filtered) == 2)
	found_nested, found_empty := false, false
	for name in filtered {
		found_nested |= name == "nested/message.txt"
		found_empty |= name == "empty.txt"
		delete(name)
	}
	delete(filtered)
	assert(found_nested && found_empty)
	stream, err := foster.OpenRead(container, "nested/message.txt")
	assert(err == .None)
	defer io.destroy(stream)
	buffer: [5]u8
	n, read_err := io.read(stream, buffer[:])
	assert(n == 5 && read_err == .None && string(buffer[:]) == "hello")
	pos, seek_err := io.seek(stream, -7, .End)
	assert(pos == 11 && seek_err == .None)
	n, read_err = io.read(stream, buffer[:])
	assert(n == 5 && string(buffer[:]) == "defla")
	assert(foster.Remove(storage, "archive.zip"))
	fmt.println(
		"PASS: Store/Deflate ZIP, directories, relative roots, owned names, wildcard recursion, seekable reads and writable streams",
	)
}
