package foster_framework

// olib 对 Foster 的纯新增能力（无上游对应），每项登记于 docs/LOCAL_CHANGES.md。

// 文件内导航
//   Framework / App
//   Storage / Atomic Write
//   Graphics / Texture Sampling

// ==============================================================================
// Framework / App — 用户数据
// ==============================================================================

// [olib L-004] 按类型取回 AppSetUserData 挂上的状态，省去每个回调里的 cast。
// 不做类型校验：T 必须与 AppSetUserData 传入的指针类型一致；未设置时返回 nil。
AppGetUserDataAs :: proc(app: ^App, $T: typeid) -> ^T {
	return cast(^T)AppGetUserData(app)
}

// ==============================================================================
// Storage / Atomic Write — 完整替换单个文件
// ==============================================================================

// [olib L-015] 桌面先写同目录临时文件并同步，再替换；Web 原子替换虚拟文件单键。
// 只读/ZIP 容器拒绝写入。失败保留原文件，不保证断电持久性或多文件事务。
// Web 文件选择器的外部文件仍需 FlushStorageFileAsync 确认，true 只表示虚拟文件已更新。
WriteAllBytesAtomic :: proc(container: ^StorageContainer, path: string, data: []byte) -> bool {
	if container == nil || !container.Writable || container.ZipEntries != nil || path == "" {
		return false
	}
	full := StorageJoinPath(container, path)
	parent, _ := storage_path_split(full)
	if parent != "" && !storage_os_make_directory_all(parent) {
		return false
	}
	if storage_os_is_directory(full) {
		return false
	}
	return storage_os_write_file_atomic(full, data)
}

// [olib L-015] UTF-8 文本沿用相同的单文件替换语义。
WriteAllTextAtomic :: proc(container: ^StorageContainer, path, data: string) -> bool {
	return WriteAllBytesAtomic(container, path, transmute([]byte)data)
}

// ==============================================================================
// Graphics / Texture Sampling — 贴图能否绑定到材质采样器
// ==============================================================================

// [olib L-018] 贴图能否绑定到采样器。普通贴图总带 SAMPLER 用途；多采样颜色附件采样其解析纹理；
// 深度附件须单采样且格式支持采样，与 Target 创建时是否加 SAMPLER 用途是同一条规则。
TextureIsSampleable :: proc(tex: ^Texture) -> bool {
	if tex == nil || tex.Resource == nil || tex.Disposed {
		return false
	}
	if !tex.IsTargetAttachment {
		return true
	}
	if TextureFormatIsColorFormat(tex.Format) {
		return tex.SampleCount == .One || tex.ResolveResource != nil
	}
	return depth_attachment_sampleable(tex.GraphicsDevice, tex.Format, tex.SampleCount)
}

// [olib L-018] SDL 没有深度解析纹理，多采样深度不能采样；单采样时按设备是否支持该格式的采样判定。
@(private)
depth_attachment_sampleable :: proc(device: ^GraphicsDevice, format: TextureFormat, sample_count: SampleCount) -> bool {
	return sample_count == .One && GraphicsDeviceIsTextureFormatSupported(device, format)
}
