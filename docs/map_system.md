# 网格地图与房间生成

- `scripts/map_state.gd` 保存唯一的 7×5 世界大地图；每个 `zone` 都有自己的 `scene` 属性（例如 `base` 或 `city1`），同一个 scene 可以被多个 zone 复用。区域保存自己的 `rooms` / `entered` / `enemies`。
- `scripts/room_generator.gd` 是通用拼装器；地图脚本可以覆盖 `register_rooms()` 和 `room_probability()`。
- `rooms/city1/` 的 `.tscn` 只描述房间内容，宽度、楼层、墙、楼梯入口由生成器统一布局。
- `SaveManager` 将大地图状态写入 `world_map/state`，旧存档没有该字段时自动创建新地图。
- 当前 `base` 使用 `0,2` 作为出生区域，其余区域默认使用 `city1`；地图 UI 已改为网格显示，可以直接前往任意格子，未知区域只隐藏详情，打开和关闭有淡入淡出。

`components/wall.tscn` 仍然是不可见的空气墙；新增的 `components/textured_wall.tscn` 才是使用 `assets/city1/wall.png` 的建筑墙。房间示例已经包含图片和调查点。后续接入更多素材时，只需替换 `rooms/city1/*.tscn` 或在场景子类覆盖房间注册表，不需要改变存档格式。
