# 物品与背包模块

## 物品注册

在 `items.json` 的 `items` 字典中添加配置。字典键可以使用中文，它就是物品 ID，同时也是 `assets/items/<ID>.png` 的图片名（不含扩展名），无需再填写图标路径；配置字段统一使用英文。

```json
"钢材_1": {
  "name": "钢材 I",
  "description": "常见的加工钢材。",
  "max_stack": 99
}
```

运行时添加物品：

```gdscript
InventoryManager.inventory.add_item("钢材_1", 3)
```

生成地图掉落物：

```gdscript
InventoryManager.spawn_drop(
    {"id": "钢材_1", "count": 2},
    Vector2(400, 600),
    SceneManager.get_current_scene(),
    player.current_sub_scene
)
```

## 箱子

箱子同时具有两个关键字段：

- `chest_id`：箱子实例的唯一 ID，用于隔离存档内容。
- `chest_type`：箱子类型，对应 `loot_tables.json` 中的生成规则。
- `star_level`：箱子采用的区域星级（1–3）；动态建筑箱子自动继承所属区域星级。

手工放置的箱子需要设置唯一 `chest_id`。`rooms.json` 中只写相对位置和 `type`，`RoomGenerator` 会用无碰撞长度前缀编码，将 `scene + zone + region_type + building_instance_id + layout_version + room_id + chest_type + floor + room_index + chest_index` 动态构造成稳定唯一 ID；因此大量地图中重复出现相同房间时也不会共享箱子内容，布局或箱子类型变化也不会误接旧内容。同一 zone 有多个建筑生成器时，需要为它们设置不同且稳定的 `building_instance_id`。

普通箱子使用固定 `capacity`；`infinite_storage` 开启后，在剩余空格不足一行时会自动增加 6 格。房车仓库使用特殊 ID `rv_warehouse` 和类型 `warehouse`，已放在 `base.tscn` 的 `indoor` 子场景中，并配置为无限容量。

## 战利品注册表

`loot_tables.json` 的 `chest_types` 按箱子类型配置生成方式，`capacity` 与 `generation` 为公共字段，`star_levels` 的 `"1"`、`"2"`、`"3"` 分别保存各星级的 `rules`。目前支持 `generation: "per_slot_probability"`：箱子首次创建时，每个格子独立生成一个 `[0,1)` 随机数，按当前星级规则中的 `chance` 顺序累计概率；命中后按 `min_count`–`max_count` 生成物品，未命中则为空格。各规则概率之和建议不超过 1，剩余概率就是空格概率。

默认三级战利品表维护在 `building/editor/app.py`。删除旧 `loot_tables.json` 后启动编辑器并保存战利品表，即可生成新结构文件。

箱子内容一旦生成便随实例 ID 保存，重新进入房间或读档不会再次刷新。每个新世界还会在地图状态中保存 `loot_seed`；箱子使用 `loot_seed XOR chest_id.hash()` 的独立随机序列生成，因此各箱子的结果稳定且互不影响。

## 操作

- E：打开/关闭背包（可在设置中改键）
- F：拾取掉落物/打开附近箱子（沿用交互键）
- 单击：选中物品并显示 200×200 大图、说明及操作；再次单击取消
- 双击或 Shift+左键：在背包与当前箱子之间快速转移整组物品
- 拖到其他格子：移动、合并或交换；拖拽预览居中显示图标和数量
- 将背包物品拖出窗口：丢弃到玩家附近
- 详情面板：可通过数量滑块分离堆叠、丢弃或调用使用入口

背包、所有已创建箱子和各地图/子场景的掉落物均随现有存档保存。

## TODO

- 背包升级
- 物品 `use_action` 与实际使用效果
