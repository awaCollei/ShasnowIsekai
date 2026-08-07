# 地图敌人持久化

## 状态规则

地图以 `scene_file_path` 作为唯一键，敌人快照保存在存档的 `[enemy_maps] states` 中。

- 第一次进入、当前游戏会话和存档都没有该地图键：执行地图的 `_spawn_scene_entities()`。
- 已经存在地图键：完全按快照恢复，不再执行默认刷新。
- 快照中的 `enemies = []` 是有效的“地图已清理”状态，之后进入不会重新生成敌人。
- 离开地图前和正式保存前都会重新捕获敌人的场景路径、世界坐标、HP、最大 HP 和 `sub_scene`。
- 旧存档没有 `enemy_maps` 时按首次进入处理，保持兼容。

运行时快照让玩家即使没有立即写入磁盘，在多个地图之间往返时也不会重复刷新；调用 `save_game()` 后才会写入槽位文件。

## 手动刷新地图

```gdscript
# 可传注册 ID
SaveManager.refresh_enemy_map("city1")

# 也可直接传场景路径
SaveManager.refresh_enemy_map("res://scenes/city1.tscn")

# 指定需要修改的存档槽位
SaveManager.refresh_enemy_map("city1", 2)
```

该方法只删除地图快照。下次进入对应地图时，`WorldScene` 会重新调用默认敌人生成逻辑。目前没有把这个接口接到 UI。

## 可持久化敌人的约束

敌人应由独立 `.tscn` 实例化，使根节点的 `scene_file_path` 非空。没有来源场景路径的纯代码临时敌人会被跳过并输出警告，因为它们无法可靠重建。
