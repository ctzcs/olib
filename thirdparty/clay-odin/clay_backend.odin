// olib backend extensions. These leave layout and default hit testing unchanged.
package clay

// A copy of the layout identity and ancestry; valid after EndLayout.
LayoutElementInfo :: struct {
	id, parentId, clipId: u32,
	boundingBox: BoundingBox,
}

PointerHitTest :: #type proc "c" (
	id: u32, position: Vector2, bounds: BoundingBox, clip: bool, userData: rawptr,
) -> bool

SetPointerHitTestFunction :: proc(callback: PointerHitTest, userData: rawptr) {
	ctx := GetCurrentContext()
	ctx.pointerHitTest = callback
	ctx.pointerHitTestUserData = userData
}

@(private)
_BackendPointInside :: proc "contextless" (id: u32, position: Vector2, bounds: BoundingBox, clip: bool) -> bool {
	ctx := GetCurrentContext()
	if ctx.pointerHitTest != nil {
		return ctx.pointerHitTest(id, position, bounds, clip, ctx.pointerHitTestUserData)
	}
	return _PointIsInsideRect(position, bounds)
}

// Returns required length; writes only if the caller's buffer is large enough.
// Floating roots inherit their attachment parent's visual transform.
GetLayoutElementInfo :: proc(output: []LayoutElementInfo) -> int {
	ctx := GetCurrentContext()
	if ctx.booleanWarnings.maxElementsExceeded {
		return 0
	}
	count := int(ctx.layoutElements.length)
	if len(output) < count {
		return count
	}
	for i in 0..<count {
		element := &ctx.layoutElements.internalArray[i]
		output[i] = {id = element.id,
			clipId = u32(ctx.layoutElementClipElementIds.internalArray[i]),
			boundingBox = GetElementData(ElementId{id = element.id}).boundingBox}
	}
	for i in 0..<count {
		element := &ctx.layoutElements.internalArray[i]
		if _ElementHasConfig(element, cast(_ElementConfigType)CLAY__ELEMENT_CONFIG_TYPE_TEXT) {
			continue
		}
		children := element.childrenOrTextContent.children
		for j in 0..<int(children.length) {
			index := (cast([^]i32)children.elements)[j]
			output[index].parentId = element.id
		}
	}
	for i in 0..<ctx.layoutElementTreeRoots.length {
		root := ctx.layoutElementTreeRoots.internalArray[i]
		output[root.layoutElementIndex].parentId = root.parentId
	}
	return count
}
