#!/bin/bash
odin run glfw_opengl3
# TODO[TS]: We should probably just have the native version of this available as well..
# odin run glfw_wgpu
odin run null
odin run sdl2_directx11
odin run sdl2_opengl3
# odin run sdl2_sdlrenderer2 (odin version too old)
odin run sdl3_sdlrenderer3
odin run sdl3_sdlgpu3

# These should be tested separately as they are more complicated to set up.
# cd js_webgl && ./build.sh (doesn't compile on my machine?)
# cd ..
# cd js_wgpu && ./build.sh
# cd ..
