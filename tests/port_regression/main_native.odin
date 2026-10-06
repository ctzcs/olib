#+build !js
package main
import foster "ofoster:."
import SDL "vendor:sdl3"
import "core:fmt"

flush_native :: proc(device: ^foster.GraphicsDevice) {
	foster.end_render_pass(device)
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
	defer foster.graphics_device_dispose_caches(&device)
	device.CommandBuffer = SDL.AcquireGPUCommandBuffer(device.Device)
	assert(device.CommandBuffer != nil)
	fmt.println("Testing", driver)
	verify_graphics(&device, flush_native)
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
