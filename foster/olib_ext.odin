package foster_framework

// olib 对 Foster 的纯新增能力（无上游对应），每项登记于 docs/LOCAL_CHANGES.md。

// 文件内导航
//   Framework / App

// ==============================================================================
// Framework / App — 用户数据
// ==============================================================================

// [olib L-004] 按类型取回 AppSetUserData 挂上的状态，省去每个回调里的 cast。
// 不做类型校验：T 必须与 AppSetUserData 传入的指针类型一致；未设置时返回 nil。
AppGetUserDataAs :: proc(app: ^App, $T: typeid) -> ^T {
	return cast(^T)AppGetUserData(app)
}
