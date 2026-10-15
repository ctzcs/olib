#+build !js
package main
import foster "olib:foster"
import SDL "vendor:sdl3"
import "core:fmt"

flush_native :: proc(device: ^foster.GraphicsDevice) {
	foster.GraphicsDeviceEndRenderPass(device)
	assert(SDL.SubmitGPUCommandBuffer(device.CommandBuffer))
	assert(SDL.WaitForGPUIdle(device.Device))
	device.CommandBuffer = SDL.AcquireGPUCommandBuffer(device.Device)
	assert(device.CommandBuffer != nil)
}

verify_native_graphics :: proc(driver: foster.GraphicsDriver, name: cstring) {
	device := foster.GraphicsDevice {
		Driver  = driver,
		InFrame = true,
	}
	device.Device = SDL.CreateGPUDevice({.SPIRV, .DXIL}, false, name)
	assert(device.Device != nil, string(SDL.GetError()))
	defer SDL.DestroyGPUDevice(device.Device)
	defer foster.GraphicsDeviceDisposeCaches(&device)
	device.CommandBuffer = SDL.AcquireGPUCommandBuffer(device.Device)
	assert(device.CommandBuffer != nil)
	fmt.println("Testing", driver)
	verify_graphics(&device, flush_native)
	// [olib L-007] EndFrame 自己负责关闭最后一个通道，不能依赖外部 flush。
	final_target: foster.Target
	foster.TargetInit(&final_target, &device, 4, 4)
	defer foster.TargetDispose(&final_target)
	foster.GraphicsDeviceClear(&device, foster.DrawableTargetFromTarget(&final_target), foster.White)
	assert(device.RenderPass != nil)
	foster.GraphicsDeviceEndFrame(&device)
	assert(device.RenderPass == nil && device.CommandBuffer == nil && !device.InFrame)
	assert(SDL.WaitForGPUIdle(device.Device))
	final_pixels := foster.TextureDownloadData(foster.TargetAttachment(&final_target))
	defer delete(final_pixels)
	assert(len(final_pixels) == 64)
	for value in final_pixels do assert(value == 255)
	fmt.println("PASS: EndFrame closes and submits the final render pass")
	device.CommandBuffer = SDL.AcquireGPUCommandBuffer(device.Device)
	assert(SDL.CancelGPUCommandBuffer(device.CommandBuffer))
}

main :: proc() {
	assert(SDL.Init({.VIDEO}))
	defer SDL.Quit()
	verify_common()
	storage := foster.StorageContainer {
		Root     = "build/port-regression-storage",
		Writable = true,
	}
	verify_zip(&storage)
	verify_native_graphics(.D3D12, "direct3d12")
	verify_native_graphics(.Vulkan, "vulkan")
}
