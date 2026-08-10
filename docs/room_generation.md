# city1 建筑 / 房间生成坐标说明

## 统一坐标约定

`RoomGenerator` 节点的局部 `(0, 0)` 是**建筑左下角，同时也是 1 楼地板表面**。

Godot 2D 的 Y 轴向下，所以：

- 1 楼地板：`y = 0`
- 2 楼地板：`y = -(room_height + floor_separator_height)`
- 3 楼地板：`y = -2 * (room_height + floor_separator_height)`
- 房间内容应使用负 Y；默认房间内部范围是 `-400 <= y <= 0`
- 每层的 `sub_scene`：1 楼为 `outdoor`，其余依次为 `floor2`、`floor3`……

默认 `room_height = 400`、`floor_separator_height = 50`，因此楼层基准线间距是 450。

## 只需要在 city1 根节点调整的 3 个位置值

在 `scenes/city1.tscn` 中选中根节点 `Main`，查看 **Building Placement** 分组。

### 1. `building_origin`：建筑原点

默认：`Vector2(800, 680)`。

它表示建筑左下角的世界坐标：

- X 增大：整栋楼向右移动；
- X 减小：整栋楼向左移动；
- Y 增大：整栋楼向下移动；
- Y 减小：整栋楼向上移动。

建议先让 `building_origin.y` 与户外地面表面的世界 Y 完全一致，再调 X。

### 2. `stair_portal_height`：楼梯传送门离本层地板的高度

默认：`80`。

这是“向上”的正高度，生成器内部会放在：

```text
portal_y = floor_y - stair_portal_height
```

若交互区域埋进地板，增大它；若悬空太高，减小它。建议每次以 5–10 像素为步长。

### 3. `enemy_height_above_floor`：敌人原点离本层地板的高度

默认：`50`。

同样是“向上”的正高度：

```text
enemy_y = floor_y - enemy_height_above_floor
```

应按照敌人场景“根节点到脚底/碰撞箱底部”的距离调整。当前史莱姆碰撞箱底部约在根节点下方 49 像素，因此默认 50。若敌人陷入地面就增大，悬空就减小。

## 房间资源制作约定

每个 `city1/*.tscn` 的根节点都以房间**左下角地板**为 `(0, 0)`：

- X 从 `0` 向右；
- Y 从 `-400` 到 `0`；
- 交互点应靠近地板但保持负 Y；
- 房间场景只放内容，不自行放外墙、分隔板、黑色遮罩和楼层传送门。

房间宽度在 `RoomGenerator.register_rooms()` 中以像素填写，例如：

```gdscript
{"id": "empty", "scene": "...", "width": 640.0, "weight": 3.0}
```

生成器会让最后一间吸收剩余宽度，保证所有楼层都严格等于 `building_width`。

## 可见性与墙体职责

- 未进入房间：纯黑遮罩覆盖房间内容和该房间右侧的内墙；
- 进入房间：只移除该房间遮罩，并把 `entered` 写回 zone 存档；
- `wall.tscn`：有碰撞的空气墙；建筑外墙使用它并可显示 `wall.png`；
- `textured_wall.tscn`：只有贴图、无碰撞，仅用于房间之间；
- `floor.png` 与两侧外墙的 Z 层高于黑色遮罩，因此建筑未探索时仍可见；
- 左外墙的一楼保留 160 像素高入口，玩家可从户外直接走进第一间楼梯间。

## 旧存档

本次布局格式版本为 2。旧版使用“槽位宽度”的 `rooms` 数据会在进入区域时自动重建；之后进入状态、房间布局与敌人仍按各自 zone 独立保存。
