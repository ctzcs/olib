# meshutil

`olib:core/meshutil` 是三角网格的 CPU 工具：统计、拓扑边、焊接、压缩和简化。
纯 Odin，不依赖 GPU；输入是位置 `[][3]f32` 与三角形索引 `[]u32`（每 3 个一组，同 dasset）。
位置相同的顶点视为同一几何点，UV/法线拆分产生的缝不算破洞。

## 检查网格

```odin
import meshutil "olib:core/meshutil"

positions := meshutil.primitive_positions(&primitive) // 静态或蒙皮 primitive 都可以
defer delete(positions)
s := meshutil.stats(positions, primitive.indices)
```

| 字段 | 看什么 |
| --- | --- |
| `used_vertices` < `vertices` | 有闲置顶点，`compact` 去掉 |
| `used_vertices` ≫ `unique_positions` | UV/法线拆得多（平直着色、UV 岛碎），顶点处理量翻倍 |
| `seam_edges` | 属性缝的边数，和上一条对应 |
| `border_edges` | 开放边：本应封闭的模型说明有破洞或没焊上的裂缝 |
| `non_manifold_edges` | 三个以上三角形共用的边，简化和法线计算都会出问题 |
| `degenerate_triangles` | 退化三角形，`remove_degenerate` 去掉 |
| `invalid_indices` | 越界索引；非零时其余拓扑统计不完整 |

`edges(positions, indices)` 返回按位置焊接后的唯一边及其种类（Interior / Seam / Border / Non_Manifold），
供 [gizmo 线框](../../kit/gizmo/README.md#网格线框) 显示，也可自行筛选。

## 整理顶点

```odin
welded, ok := meshutil.weld(primitive.vertices, primitive.indices) // 合并字节完全相同的顶点，原地改写索引
kept := meshutil.remove_degenerate(positions, indices)              // 原地过滤，返回有效前缀
compacted, ok2 := meshutil.compact(vertices, indices)                // 去掉未引用顶点，按首次引用排序
```

`weld` 与 `compact` 是泛型，适用于 `dasset.Dasset_Vertex`、`Dasset_Skin_Vertex` 或自定义顶点；
`weld` 按字节比较，顶点结构不应含未初始化的填充。二者都返回新分配的顶点数组，索引越界时不修改并返回 false。

## 简化（LOD）

```odin
lod_indices, error, ok := meshutil.simplify(positions, primitive.indices,
	target_index_count = len(primitive.indices)/4, max_error = 0.01)
defer delete(lod_indices)
lod_vertices, _ := meshutil.compact(primitive.vertices, lod_indices) // 可选：只保留 LOD 用到的顶点
```

二次误差（QEM）边折叠，思路对位 meshoptimizer 的 `meshopt_simplify`：

- 只改写索引，保留原顶点（位置、法线、UV、蒙皮权重不变），因此不会产生插值出来的新属性。
- 达到目标索引数，或下一步误差超过 `max_error` 时停止；两者取先到者。
  误差与返回的 `error` 都是相对包围盒最长边的距离，0.01 ≈ 1%，与模型单位无关。
- 开放边界只沿边界收缩、额外加权，轮廓不内缩；两份属性的缝两侧成对折叠，不开裂。
  三份以上属性拆分的点（平直着色的角）、非流形点保持不动，这类模型能简化的空间有限，先看 `stats`。
- 拒绝翻转三角形或产生非流形边的折叠。

结果可直接作为 [Model_Lod](../../kit/rendering/3d/REFERENCE.md) 的各级网格；
65k 三角形的模型简化约 0.1 秒（`-o:speed`），适合在导入或工具里离线生成，不要每帧调用。

## 验证

```powershell
odin run tools/check -- -only:core/meshutil
```

测试覆盖立方体缝统计、开放边界与非流形边、焊接/压缩/退化过滤，以及平面简化保留角点、
带缝 UV 球简化后保持封闭、误差上限与非法输入。
