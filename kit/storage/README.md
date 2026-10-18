# 跨平台存储路径

`kit/storage` 统一选择资源根、用户根与应用命名空间，默认用于新游戏模板。实际文件读写直接使用 Foster 的 `StorageContainer`、`ReadAllBytes`、`WriteAllBytes` 等 API，不另包一套读写接口。

| 平台 | `user_root(app_name)` |
| --- | --- |
| Windows | `%APPDATA%/<app_name>` |
| macOS | `~/Library/Application Support/<app_name>` |
| Linux | `$XDG_CONFIG_HOME/<app_name>`，缺省 `~/.config/<app_name>` |
| Web | `/foster/<app_name>/` 虚拟目录，由 Foster 的 localStorage 后端持久化 |

桌面 `resources_root_dev` 返回工作目录，`resources_root_release` 返回可执行文件目录；Web 两者返回虚拟 FS 根 `/`，不是 URL，也不会自动下载站点资源。字体等 `#load` 资源仍直接内嵌；Web 外部资源须先加载到 Foster 虚拟 FS。

根字符串归调用方指定的 allocator 所有，存储容器借用它，容器使用完后才能 delete。`user_root` 创建目录失败或应用名为空、包含路径分隔符时返回空字符串。不能把失败的用户根当作当前工作目录继续读写。Web 存储受同源和浏览器容量/权限限制；每次写入均检查 Foster 返回的 bool。

```odin
import storage "olib:kit/storage"
import foster "olib:foster"

root := storage.user_root("MyGame")
if root == "" do return
defer delete(root)
files := foster.StorageContainer{Root = root, Writable = true}
ok := foster.WriteAllText(&files, "settings.json", `{}`)
// 由调用方处理 ok；存档格式、版本与保存时机属于游戏。
```

`with_user_storage` 保留原有回调 API，桌面与 Web 均可用；返回 true 只表示成功打开并执行回调，实际读写结果由回调检查。`user_file_path` 在 Web 返回虚拟路径，不能用于系统文件 API。

新游戏模板的 host 默认持有根字符串和两个 Foster 容器，通过 `Services.assets`（只读）和 `Services.user_storage`（可写）提供给 core/editor；热重载不会释放它们。稳定的 `STORAGE_ID` 使用项目名，开发窗口标题变化不会切换存储目录。开发版与桌面发布版共用用户目录；Web 在当前源下独立存储，不与桌面同步。

默认接入提供可用的存储，不自动保存整局进度。业务在明确的保存时机编码后写入，加载时校验和迁移；禁止在热重载候选 load 或模块 unload 中自动写盘。热重载快照与持久存档分开，不把存储指针或根字符串作为权威游戏状态编码。
