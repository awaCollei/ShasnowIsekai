# city1 建筑 / 房间生成说明

## 坐标约定

`RoomGenerator` 的局部 `(0, 0)` 是建筑左下角，也是 1 楼地板表面。
Godot 2D 的 Y 轴向下，因此第 `N` 层地板位置为：

```text
y = -(N - 1) * (room_height + floor_separator_height)
```

- 1 楼的 `sub_scene` 为 `outdoor`；其余依次为 `floor2`、`floor3`……
- `building_origin` 控制整栋建筑在世界中的位置。
- `enemy_height_above_floor` 控制敌人原点高出地板的距离。

## 配置来源

生成器不提供配置回退，也不修正配置值：

- `building/rooms.json` 必须包含当前 `scene / region_type`、`floor_count`、`portal_positions` 和完整的房间字段。
- `room_generator.gd` 文件开头的导出值直接控制建筑宽度、房间高度、间隔、最大房间数和墙体尺寸。
- 外墙、内墙和地板贴图由 `city1.gd` 直接传给生成器，必须有效。
- 配置或资源错误会直接暴露，不会用默认房间、默认宽度、纯色地板或替代位置继续生成。

## 房间宽度

所有房间（包括**空房间**和**楼梯间**）只有一个宽度来源：

```text
res://assets/{scene}/{region_type}/{room_id}.png 的原始像素宽度
```

布局存档只保存房间 ID 和进入状态，不再保存 `width_px`。因此贴图宽度变化后，布局位置和房间碰撞宽度会直接使用当前贴图尺寸。

普通房间始终使用贴图原始宽度。空房间不参与随机选择，只用于尾部补齐：连续空房间中除最右侧最后一间外，其余均使用空房间贴图的原始最大宽度；最后一间按剩余宽度从贴图两侧等量裁剪，保持画面居中。生成器不会拉伸贴图或扩大空房间。

## 房间 JSON 字段

每个房间都必须显式提供：

- `id`
- `weight`
- `investigation_points`（没有时写 `[]`）
- `chests`（没有时写 `[]`）

调查点必须包含 `position`、`investigation_id`、`investigation_name`、`message`；箱子必须包含 `position`、`type`、`name`。

## 布局存档

当前布局版本为 5。旧布局会重建一次，以清除曾经随机生成在中间或连续以非最大宽度生成的空房间。普通房间宽度不进入存档；仅被裁剪的空房间记录本次布局分配的宽度。
