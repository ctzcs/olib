package clay_tests

import "base:runtime"
import "core:fmt"
import "core:strings"
import clay ".."

// The same scenarios run against the original v0.14 C object and this Odin port.
// Output contains public observable values only, never addresses or arena sizes.
Report :: struct {
	out: strings.Builder,
	errors: int,
	hovers: int,
}

measure :: proc "c" (text: clay.StringSlice, config: ^clay.TextElementConfig, data: rawptr) -> clay.Dimensions {
	width: f32
	for i in 0..<text.length {
		width += text.chars[i] == ' ' ? f32(config.fontSize)*0.3 : f32(config.fontSize)*0.6
	}
	return {width + f32(max(text.length - 1, 0))*f32(config.letterSpacing), f32(config.fontSize)}
}

on_error :: proc "c" (error: clay.ErrorData) {
	context = runtime.default_context()
	r := cast(^Report)error.userData
	r.errors += 1
	fmt.sbprintf(&r.out, "error %d\n", int(error.errorType))
}

on_hover :: proc "c" (id: clay.ElementId, pointer: clay.PointerData, data: rawptr) {
	context = runtime.default_context()
	r := cast(^Report)data
	r.hovers += 1
	fmt.sbprintf(&r.out, "hover %d %d %.4f %.4f\n", id.id, int(pointer.state), pointer.position.x, pointer.position.y)
}

Run :: proc() -> string {
	r: Report
	clay.SetCurrentContext(nil)
	clay.SetMaxElementCount(2048)
	clay.SetMaxMeasureTextCacheWordCount(4096)
	memory := make([]u8, int(clay.MinMemorySize()))
	defer delete(memory)
	clay.Initialize(
		arena = clay.CreateArenaWithCapacityAndMemory(capacity = uint(len(memory)), offset = raw_data(memory)),
		layoutDimensions = {640, 480}, errorHandler = {handler = on_error, userData = &r},
	)
	defer clay.SetCurrentContext(nil)
	clay.SetMeasureTextFunction(measure, nil)
	for label in ([]string{"", "root", "滚动容器", "é🙂"}) {
		for index: u32 = 0; index < 3; index += 1 {
			id := clay.GetElementIdWithIndex(id = clay.MakeString(label), index = index)
			fmt.sbprintf(&r.out, "id %s %d %d %d\n", label, id.id, id.baseId, id.offset)
		}
	}
	for scenario in 0..<40 {
		clay.SetDebugModeEnabled(scenario >= 38)
		clay.SetCullingEnabled(scenario % 2 == 0)
		clay.ResetMeasureTextCache()
		for frame in 0..<8 {
			width := f32(180 + (scenario*71 + frame*37)%650)
			height := f32(240 + (scenario*31)%250)
			clay.SetLayoutDimensions({width, height})
			clay.SetPointerState(position = {f32(15 + frame*9), f32(20 + frame*13)}, pointerDown = frame >= 2 && frame <= 4)
			clay.UpdateScrollContainers(scenario % 2 == 0, {0, frame == 1 ? -3 : 0}, 1.0/60)
			fmt.sbprintf(&r.out, "frame %d %d %.4f %.4f\n", scenario, frame, width, height)
			clay.BeginLayout()
			if clay.UI()(clay.ElementDeclaration{
				id = clay.ID("root"),
				layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					padding = {7, 11, 9, 13}, childGap = u16(scenario%9),
					layoutDirection = scenario%2 == 0 ? .TopToBottom : .LeftToRight,
					childAlignment = {x = clay.LayoutAlignmentX(scenario%3), y = clay.LayoutAlignmentY((scenario/3)%3)}},
				backgroundColor = {10, 20, 30, 255},
				cornerRadius = clay.CornerRadiusAll(4),
				border = {color = {255, 0, 0, 255}, width = {1, 2, 3, 4, 2}},
			}) {
				clay.OnHover(on_hover, &r)
				fmt.sbprintf(&r.out, "hovered %t local %d\n", clay.Hovered(), clay.ID_LOCAL("local").id)
				for child in 0..<6 {
					w := clay.SizingGrow({min = f32(10 + child*3), max = f32(60 + child*30)})
					switch (scenario + child)%4 {
					case 0: w = clay.SizingFixed(f32(20 + child*17))
					case 1: w = clay.SizingPercent(0.23)
					case 2: w = clay.SizingFit({min = 12, max = 170})
					}
					if clay.UI()(clay.ElementDeclaration{
						id = clay.ID("child", u32(child)),
						layout = {sizing = {width = w, height = clay.SizingFit({max = 160})},
							padding = clay.PaddingAll(u16(child)), childGap = 3,
							layoutDirection = .TopToBottom},
						backgroundColor = {f32(child*30), 80, 100, 255},
					}) {
						config := clay.TextConfig({fontId = u16(child%2), fontSize = u16(10 + child*3),
							letterSpacing = u16(scenario%3), lineHeight = u16(scenario%2*30),
							wrapMode = clay.TextWrapMode((scenario+child)%3),
							textAlignment = clay.TextAlignment(child%3), textColor = {240, 230, 220, 255}})
						texts := []string{"alpha beta gamma", "one\ntwo\nthree", "   leading  trailing  ", "", "supercalifragilistic", "中文 hello 世界"}
						clay.TextDynamic(texts[child], config)
						if clay.UI()(clay.ElementDeclaration{layout = {sizing = {width = clay.SizingFixed(31), height = clay.SizingFixed(17)}},
							backgroundColor = {20, 40, 60, 255}, image = {imageData = rawptr(uintptr(1))}, aspectRatio = {aspectRatio = 1.5}}) {}
					}
				}
				scroll := clay.GetScrollContainerData(clay.ID("scroll"))
				if clay.UI()(clay.ElementDeclaration{
					id = clay.ID("scroll"),
					layout = {sizing = {width = clay.SizingFixed(120), height = clay.SizingFixed(65)}, childGap = 2, layoutDirection = .TopToBottom},
					clip = {horizontal = true, vertical = true, childOffset = scroll.found ? scroll.scrollPosition^ : clay.Vector2{}},
				}) {
					for row in 0..<8 {
						if clay.UI()(clay.ElementDeclaration{id = clay.ID("row", u32(row)), layout = {sizing = {width = clay.SizingFixed(160), height = clay.SizingFixed(22)}}, backgroundColor = {10, 30, 90, 255}}) {}
					}
				}
				if clay.UI()(clay.ElementDeclaration{
					id = clay.ID("float"),
					layout = {sizing = {width = clay.SizingFixed(45), height = clay.SizingFixed(23)}},
					floating = {attachTo = .ElementWithId, parentId = clay.ID("child", 0).id,
						offset = {-3, 7}, expand = {2, 1}, zIndex = i16(scenario%3-1),
						attachment = {element = clay.FloatingAttachPointType(scenario%9), parent = clay.FloatingAttachPointType((scenario/2)%9)},
						pointerCaptureMode = scenario%2 == 0 ? .Capture : .Passthrough,
						clipTo = scenario%2 == 0 ? .AttachedParent : .None},
					custom = {customData = rawptr(uintptr(2))}, backgroundColor = {90, 80, 70, 128},
				}) {}
			}
			commands := clay.EndLayout()
			fmt.sbprintf(&r.out, "commands %d\n", commands.length)
			for i: i32 = 0; i < commands.length; i += 1 {
				c := clay.RenderCommandArray_Get(&commands, i)^
				b := c.boundingBox
				fmt.sbprintf(&r.out, "c %d %d %d %.4f %.4f %.4f %.4f", int(c.commandType), c.id, c.zIndex, b.x, b.y, b.width, b.height)
				#partial switch c.commandType {
				case .Text:
					t := c.renderData.text
					fmt.sbprintf(&r.out, " text %q %d %d %d %d %v", string(t.stringContents.chars[:t.stringContents.length]), t.fontId, t.fontSize, t.letterSpacing, t.lineHeight, t.textColor)
				case .Rectangle: fmt.sbprintf(&r.out, " rect %v %v", c.renderData.rectangle.backgroundColor, c.renderData.rectangle.cornerRadius)
				case .Border: fmt.sbprintf(&r.out, " border %v %v %v", c.renderData.border.color, c.renderData.border.width, c.renderData.border.cornerRadius)
				case .Image: fmt.sbprintf(&r.out, " image %v %v %d", c.renderData.image.backgroundColor, c.renderData.image.cornerRadius, uintptr(c.renderData.image.imageData))
				case .Custom: fmt.sbprintf(&r.out, " custom %v %v %d", c.renderData.custom.backgroundColor, c.renderData.custom.cornerRadius, uintptr(c.renderData.custom.customData))
				case:
				}
				fmt.sbprintf(&r.out, "\n")
			}
			for label in ([]string{"root", "child", "scroll", "float", "missing"}) {
				id := clay.GetElementId(id = clay.MakeString(label))
				d := clay.GetElementData(id)
				fmt.sbprintf(&r.out, "element %s %t %t %.4f %.4f %.4f %.4f\n", label, d.found, clay.PointerOver(id = id), d.boundingBox.x, d.boundingBox.y, d.boundingBox.width, d.boundingBox.height)
			}
			s := clay.GetScrollContainerData(clay.ID("scroll"))
			fmt.sbprintf(&r.out, "scroll %t %v %v %v\n", s.found, s.scrollPosition^, s.scrollContainerDimensions, s.contentDimensions)
		}
	}
	// Error handling and public queries must match as well as normal layouts.
	clay.SetDebugModeEnabled(false)
	clay.BeginLayout()
	for _ in 0..<2 {
		if clay.UI()(clay.ElementDeclaration{id = clay.ID("duplicate"), layout = {sizing = {width = clay.SizingPercent(1.2), height = clay.SizingFixed(10)}}, backgroundColor = {255, 0, 0, 255}}) {}
	}
	if clay.UI()(clay.ElementDeclaration{id = clay.ID("orphan"), floating = {attachTo = .ElementWithId, parentId = 123456}, layout = {sizing = {width = clay.SizingFixed(10), height = clay.SizingFixed(10)}}}) {}
	commands := clay.EndLayout()
	fmt.sbprintf(&r.out, "invalid-layout %d\n", commands.length)
	clay.SetMeasureTextFunction(nil, nil)
	clay.BeginLayout()
	clay.Text("no measurer", clay.TextConfig({fontSize = 12}))
	commands = clay.EndLayout()
	fmt.sbprintf(&r.out, "no-measurer %d\n", commands.length)
	clay.SetMeasureTextFunction(measure, nil)
	clay.BeginLayout()
	for i in 0..<2100 {
		if clay.UI()(clay.ElementDeclaration{id = clay.ID("overflow", u32(i)), layout = {sizing = {width = clay.SizingFixed(1), height = clay.SizingFixed(1)}}}) {}
	}
	commands = clay.EndLayout()
	fmt.sbprintf(&r.out, "overflow %d\n", commands.length)
	// Reinitializing in the same arena resets warnings and persistent state.
	first := clay.Initialize(clay.CreateArenaWithCapacityAndMemory(uint(len(memory)), raw_data(memory)), {100, 100}, {handler = on_error, userData = &r})
	clay.SetMeasureTextFunction(measure, nil)
	other_memory := make([]u8, int(clay.MinMemorySize()))
	defer delete(other_memory)
	second := clay.Initialize(clay.CreateArenaWithCapacityAndMemory(uint(len(other_memory)), raw_data(other_memory)), {200, 150}, {handler = on_error, userData = &r})
	for active in ([]^clay.Context{first, second, first, second}) {
		clay.SetCurrentContext(active)
		clay.BeginLayout()
		if clay.UI()(clay.ElementDeclaration{id = clay.ID("context"), layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}}, backgroundColor = {10, 20, 30, 255}}) {}
		commands = clay.EndLayout()
		d := clay.GetElementData(clay.ID("context"))
		fmt.sbprintf(&r.out, "context %t %d %v\n", clay.GetCurrentContext() == active, commands.length, d.boundingBox)
	}
	// Isolate scroll tests so the pointer definitely hits the scroll container.
	for frame in 0..<18 {
		clay.SetPointerState({30, f32(40 - min(frame, 10)*2)}, frame >= 4 && frame < 11)
		clay.UpdateScrollContainers(true, {frame == 2 ? -2 : 0, frame == 1 ? -3 : 0}, 1.0/60)
		previous := clay.GetScrollContainerData(clay.ID("scroll-test"))
		offset := previous.found ? previous.scrollPosition^ : clay.Vector2{}
		clay.BeginLayout()
		if clay.UI()(clay.ElementDeclaration{id = clay.ID("scroll-test"),
			layout = {sizing = {width = clay.SizingFixed(100), height = clay.SizingFixed(60)}, layoutDirection = .TopToBottom},
			clip = {horizontal = true, vertical = true, childOffset = offset}}) {
			fmt.sbprintf(&r.out, "offset %d %v\n", frame, clay.GetScrollOffset())
			for row in 0..<10 {
				if clay.UI()(clay.ElementDeclaration{id = clay.ID("scroll-row", u32(row)), layout = {sizing = {width = clay.SizingFixed(200), height = clay.SizingFixed(20)}}, backgroundColor = {20, 30, 40, 255}}) {}
			}
		}
		commands = clay.EndLayout()
		scroll := clay.GetScrollContainerData(clay.ID("scroll-test"))
		fmt.sbprintf(&r.out, "scroll-test %d %v %v %d\n", frame, scroll.scrollPosition^, scroll.contentDimensions, commands.length)
	}
	clay.SetMaxMeasureTextCacheWordCount(64)
	clay.Initialize(clay.CreateArenaWithCapacityAndMemory(uint(len(other_memory)), raw_data(other_memory)), {200, 150}, {handler = on_error, userData = &r})
	clay.BeginLayout()
	config := clay.TextConfig({fontSize = 16})
	clay.Text("00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69", config)
	commands = clay.EndLayout()
	fmt.sbprintf(&r.out, "cache-limit %d %d %d\n", clay.GetMaxElementCount(), clay.GetMaxMeasureTextCacheWordCount(), commands.length)
	invalid := clay.RenderCommandArray_Get(&commands, -1)
	fmt.sbprintf(&r.out, "invalid-command %d\n", int(invalid.commandType))
	fmt.sbprintf(&r.out, "totals %d %d\n", r.errors, r.hovers)
	return strings.to_string(r.out)
}

// Keep the checked-in oracle small. Each digest covers a full frame, including
// every command's geometry, order, color, text and the observable input state.
// Run() remains available to print the full frame on a regression.
Summarize :: proc(output: string) -> string {
	result: strings.Builder
	start := 0
	segment := 0
	for i in 0..<len(output) {
		if (i == 0 || output[i-1] == '\n') && strings.has_prefix(output[i:], "frame ") {
			if i > start {
				write_digest(&result, output[start:i], segment)
				segment += 1
			}
			start = i
		}
	}
	write_digest(&result, output[start:], segment)
	return strings.to_string(result)
}

write_digest :: proc(out: ^strings.Builder, value: string, index: int) {
	hash: u64 = 14695981039346656037
	for byte in transmute([]u8)value {
		hash = (hash ~ u64(byte))*1099511628211
	}
	end := strings.index_byte(value, '\n')
	first := end >= 0 ? value[:end] : value
	fmt.sbprintf(out, "%d %016x %d %s\n", index, hash, len(value), first)
}
