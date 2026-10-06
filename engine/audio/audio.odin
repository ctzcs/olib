// audio —— SDL3 音频的最小可用层（native；对位 DragonLib Foster.Audio 的用途）。
//
// 不改 OFoster 的原则下，音频直接绑 Odin vendor:sdl3：
//   audio_init        初始化 SDL audio 子系统
//   Audio_Device      默认回放设备 + 队列模式流（f32/2ch/48k，SDL 自动重采样）
//   Audio_Sound       WAV 装载并转换到设备格式；play 入队（音量在样本上缩放）
//
// 多路混音走"多次 play 各自缩放入队"——SDL 流内部排队播放；需要采样级
// 混合器/3D 空间化时再扩展。web 目标不适用（native only）。
package audio

import "core:mem"
import sdl3 "vendor:sdl3"

// 分区：
//   初始化 —— 子系统 / 设备
//   声音 —— WAV 装载 / 转换 / 播放
//   混音辅助 —— 样本级音量/裁剪

// ------------------------------------------------------------------------------
// 初始化
// ------------------------------------------------------------------------------

audio_init :: proc() -> bool {
	return sdl3.InitSubSystem(sdl3.InitFlags{.AUDIO})
}

audio_shutdown :: proc() {
	sdl3.QuitSubSystem(sdl3.InitFlags{.AUDIO})
}

// 默认回放设备 + 队列模式流。callback 为 nil：数据经 audio_play 入队，
// SDL 在音频线程拉取。失败返回 false（无音频设备的环境）。
Audio_Device :: struct {
	stream: ^sdl3.AudioStream,
	spec:   sdl3.AudioSpec, // 设备侧实际格式（声音转换目标）
}

AUDIO_DEVICE_SAMPLE_RATE :: 48000

audio_device_open :: proc(device: ^Audio_Device, channels: int = 2, sample_rate: int = AUDIO_DEVICE_SAMPLE_RATE) -> bool {
	desired := sdl3.AudioSpec{
		format = .F32,
		channels = i32(channels),
		freq = i32(sample_rate),
	}
	obtained: sdl3.AudioSpec
	stream := sdl3.OpenAudioDeviceStream(sdl3.AUDIO_DEVICE_DEFAULT_PLAYBACK, &desired, nil, nil)
	if stream == nil {
		return false
	}
	if !sdl3.ResumeAudioStreamDevice(stream) {
		sdl3.DestroyAudioStream(stream)
		return false
	}
	if !sdl3.GetAudioDeviceFormat(sdl3.AUDIO_DEVICE_DEFAULT_PLAYBACK, &obtained, nil) {
		obtained = desired
	}
	device.stream = stream
	device.spec = obtained
	return true
}

audio_device_close :: proc(device: ^Audio_Device) {
	if device.stream != nil {
		sdl3.DestroyAudioStream(device.stream)
	}
	device^ = {}
}

// ------------------------------------------------------------------------------
// 声音
// ------------------------------------------------------------------------------

// 已装载的声音：f32 样本（交错），格式为装载时的源格式（播放时转换到设备格式）。
Audio_Sound :: struct {
	samples:  []f32,
	channels: int,
	rate:     int,
}

audio_sound_dispose :: proc(sound: ^Audio_Sound) {
	if sound.samples != nil { delete(sound.samples) }
	sound^ = {}
}

// 从 WAV 文件装载（SDL_LoadWAV 解任意比特深度，再转 f32）。
audio_sound_load_wav :: proc(sound: ^Audio_Sound, path: string) -> bool {
	spec: sdl3.AudioSpec
	buf: [^]u8
	buf_len: u32

	if len(path) >= 4096 { return false }
	path_buf: [4096]u8
	copy(path_buf[:len(path)], transmute([]u8)path)
	path_buf[len(path)] = 0
	c_path := cstring(raw_data(path_buf[:len(path) + 1]))

	if !sdl3.LoadWAV(c_path, &spec, &buf, &buf_len) {
		return false
	}
	defer sdl3.free(buf)

	// 转成 f32 交错
	dst_spec := sdl3.AudioSpec{
		format = .F32,
		channels = spec.channels,
		freq = spec.freq,
	}
	dst: [^]u8
	dst_len: i32
	if !sdl3.ConvertAudioSamples(&spec, buf, i32(buf_len), &dst_spec, &dst, &dst_len) {
		return false
	}
	defer sdl3.free(dst)

	count := int(dst_len) / size_of(f32)
	out := make([]f32, count)
	mem.copy(raw_data(out), dst, int(dst_len))

	sound^ = {
		samples  = out,
		channels = int(spec.channels),
		rate     = int(spec.freq),
	}
	return true
}

// 入队播放：音量先做样本级缩放（0 静音，1 原样），SDL 流负责重采样到设备格式。
// 一次性 whole-buffer 入队（短音效）；长音频需要流式分块时再扩展。
audio_play :: proc(device: ^Audio_Device, sound: ^Audio_Sound, volume: f32 = 1) -> bool {
	if device.stream == nil || sound.samples == nil { return false }

	vol: f32 = volume
	if vol > 1 { vol = 1 }
	if vol < 0 { vol = 0 }

	needs_scale := vol < 0.999
	scaled: []f32
	if needs_scale {
		scaled = make([]f32, len(sound.samples))
		for i in 0..<len(sound.samples) {
			scaled[i] = sound.samples[i] * vol
		}
		defer delete(scaled)
	}

	data := needs_scale ? scaled : sound.samples
	// 注：流在设备打开时已协商格式，源/设备采样率不同时 SDL 自动重采样
	return sdl3.PutAudioStreamData(device.stream, raw_data(data), i32(len(data) * size_of(f32)))
}

// ------------------------------------------------------------------------------
// 混音辅助 —— 样本级音量/裁剪（纯数学，供测试与自定义混音器）
// ------------------------------------------------------------------------------

// 样本级音量缩放 + 硬裁剪到 [-1,1]。dst 与 src 可同片。
apply_volume :: proc(dst, src: []f32, volume: f32) {
	n := min(len(dst), len(src))
	for i in 0..<n {
		v := src[i] * volume
		if v > 1 { v = 1 } else if v < -1 { v = -1 }
		dst[i] = v
	}
}
