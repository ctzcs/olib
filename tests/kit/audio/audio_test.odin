// audio 包单元测试：WAV 装载/转换走真实 SDL；设备打开按环境可用性跳过。
#+test
package audio

import "core:os"
import "core:strings"
import "core:testing"

// 生成一个最小合法 WAV（RIFF/PCM 16bit 单声道 8 样本锯齿）再让 SDL 装载。
@(private)
write_test_wav :: proc(t: ^testing.T, path: string) {
	samples := [8]u16{0, 8192, 16384, 24576, 32768, 40960, 49152, 57344}
	riff := "RIFF"
	wave := "WAVE"
	fmt_chunk := "fmt "
	data_chunk := "data"
	data: [dynamic]u8
	defer delete(data)

	append(&data, ..transmute([]u8)riff)
	u32le(&data, 36 + len(samples) * 2)
	append(&data, ..transmute([]u8)wave)
	append(&data, ..transmute([]u8)fmt_chunk)
	u32le(&data, 16)
	u16le(&data, 1) // PCM
	u16le(&data, 1) // 单声道
	u32le(&data, 22050) // 采样率
	u32le(&data, 22050 * 2) // 字节率
	u16le(&data, 2) // 块对齐
	u16le(&data, 16) // 位深
	append(&data, ..transmute([]u8)data_chunk)
	u32le(&data, len(samples) * 2)
	for s in samples {
		u16le(&data, s)
	}

	e := os.write_entire_file(path, data[:])
	testing.expectf(t, e == nil, "写测试 WAV: %v", e)
}

@(private)
u32le :: proc(data: ^[dynamic]u8, v: u32) {
	append(data, u8(v))
	append(data, u8(v >> 8))
	append(data, u8(v >> 16))
	append(data, u8(v >> 24))
}

@(private)
u16le :: proc(data: ^[dynamic]u8, v: u16) {
	append(data, u8(v))
	append(data, u8(v >> 8))
}

@(test)
sound_load_wav_converts_to_f32 :: proc(t: ^testing.T) {
	wav := strings.join({os.get_env_alloc("TEMP", context.temp_allocator), "olib_audio_test.wav"}, "/", context.temp_allocator)
	write_test_wav(t, wav)

	if !audio_init() {
		testing.expect(t, true) // 无音频子系统也允许通过（仅跳过装载）
		return
	}
	defer audio_shutdown()

	sound: Audio_Sound
	defer audio_sound_dispose(&sound)
	ok := audio_sound_load_wav(&sound, wav)
	if !testing.expectf(t, ok, "WAV 装载") { return }

	testing.expect(t, len(sound.samples) == 8 && sound.channels == 1 && sound.rate == 22050)
	// 16-bit PCM WAV 按规范是有符号：u16 位型按 s16 解释
	// {0,8192,16384,24576,32768,...} -> {0,.25,.5,.75,-1,...}
	testing.expect(t, sound.samples[0] == 0)
	testing.expect(t, sound.samples[2] == 0.5)
	testing.expect(t, sound.samples[4] == -1) // 32768 溢出为 -32768

	// 设备打开（可能失败——无音频设备的环境允许）
	device: Audio_Device
	if audio_device_open(&device) {
		defer audio_device_close(&device)
		played := audio_play(&device, &sound, 0.5)
		testing.expect(t, played)
	} else {
		// 无默认回放设备的环境允许跳过播放
	}
}

@(test)
apply_volume_scales_and_clamps :: proc(t: ^testing.T) {
	src := []f32{0.25, -0.25, 0.75, -0.75}
	defer delete(src)
	dst := make([]f32, 4)
	defer delete(dst)

	apply_volume(dst, src, 2.0) // 放大：0.25*2=0.5 不裁剪，0.75*2=1.5 裁到 1
	testing.expect(t, dst[0] == 0.5 && dst[1] == -0.5 && dst[2] == 1 && dst[3] == -1)

	apply_volume(dst, src, 0.5)
	testing.expect(t, dst[0] == 0.125 && dst[3] == -0.375)

	apply_volume(dst, src, 0.0)
	testing.expect(t, dst[0] == 0 && dst[2] == 0)
}
