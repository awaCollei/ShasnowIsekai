extends Node

const REGISTRY_PATH := "res://inventory/items.json"
const LOOT_TABLES_PATH := "res://inventory/loot_tables.json"
const ITEM_TEXTURE_DIR := "res://assets/items/"
const DROP_SCENE := preload("res://inventory/dropped_item.tscn")

var registry: Dictionary = {}
var loot_tables: Dictionary = {}
var inventory := InventoryStorage.new(30, false)
var chests: Dictionary = {}
## 与 chests 同键保存类型；类型属于实例存档，不能仅依赖当前房间配置。
var chest_types: Dictionary = {}
var ground_drops: Dictionary = {}
var _drop_serial := 0

func _ready() -> void:
	_load_registry()
	_load_loot_tables()

func _load_registry() -> void:
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if not file:
		push_error("物品注册表不存在: %s" % REGISTRY_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		registry = parsed.get("items", {})
	for item_id in registry:
		var texture_path := get_texture_path(item_id)
		if not ResourceLoader.exists(texture_path):
			push_warning("物品 %s 缺少同名图片: %s" % [item_id, texture_path])

func _load_loot_tables() -> void:
	var file := FileAccess.open(LOOT_TABLES_PATH, FileAccess.READ)
	if not file:
		push_error("战利品注册表不存在: %s" % LOOT_TABLES_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		loot_tables = parsed.get("chest_types", {})
	for type_id in loot_tables:
		var rules = loot_tables[type_id].get("rules", [])
		var probability_sum := 0.0
		for rule in rules:
			if not rule is Dictionary:
				continue
			probability_sum += maxf(0.0, float(rule.get("chance", 0.0)))
			var item_id := String(rule.get("item", ""))
			if not has_item(item_id):
				push_warning("箱子类型 %s 引用了未注册物品: %s" % [type_id, item_id])
		if probability_sum > 1.0001:
			push_warning("箱子类型 %s 的每格概率总和大于 1，将按规则顺序截断" % type_id)

func has_item(item_id: String) -> bool:
	return registry.has(item_id)

func get_item(item_id: String) -> Dictionary:
	return registry.get(item_id, {})

func get_max_stack(item_id: String) -> int:
	return maxi(1, int(get_item(item_id).get("max_stack", 99)))

func get_texture_path(item_id: String) -> String:
	return ITEM_TEXTURE_DIR + item_id + ".png"

func get_chest(chest_id: String, chest_type: String = "", capacity: int = 24, infinite: bool = false) -> InventoryStorage:
	if chests.has(chest_id):
		# 旧存档没有 type 字段时，用当前场景配置补齐，但绝不重新生成内容。
		if String(chest_types.get(chest_id, "")).is_empty() and not chest_type.is_empty():
			chest_types[chest_id] = chest_type
		return chests[chest_id]
	var config: Dictionary = loot_tables.get(chest_type, {})
	var actual_capacity := maxi(1, int(config.get("capacity", capacity)))
	var storage := InventoryStorage.new(actual_capacity, infinite)
	chests[chest_id] = storage
	chest_types[chest_id] = chest_type
	_generate_chest_loot(storage, chest_type, chest_id)
	SaveManager.request_auto_save("生成箱子战利品")
	return storage

## 逐格进行一次随机判定。规则概率按数组顺序占用 [0, 1) 区间，
## 未命中任何规则时该格保持为空。
func _generate_chest_loot(storage: InventoryStorage, chest_type: String, chest_id: String) -> void:
	var config: Dictionary = loot_tables.get(chest_type, {})
	if String(config.get("generation", "none")) != "per_slot_probability":
		return
	var rules = config.get("rules", [])
	if not rules is Array:
		return
	var rng := RandomNumberGenerator.new()
	var world_seed := int(SaveManager.runtime_map_state.get("loot_seed", 1357911))
	rng.seed = world_seed ^ chest_id.hash()
	for slot_index in range(storage.slots.size()):
		var roll := rng.randf()
		var cumulative := 0.0
		for raw_rule in rules:
			if not raw_rule is Dictionary:
				continue
			cumulative += maxf(0.0, float(raw_rule.get("chance", 0.0)))
			if roll >= minf(cumulative, 1.0):
				continue
			var item_id := String(raw_rule.get("item", ""))
			if has_item(item_id):
				var minimum := maxi(1, int(raw_rule.get("min_count", 1)))
				var maximum := maxi(minimum, int(raw_rule.get("max_count", minimum)))
				var amount := mini(rng.randi_range(minimum, maximum), get_max_stack(item_id))
				storage.slots[slot_index] = {"id": item_id, "count": amount}
			break
	storage.changed.emit()

func drop_from_inventory(slot_index: int, world_position: Vector2) -> bool:
	return drop_from_storage(inventory, slot_index, world_position)

func drop_from_storage(storage: InventoryStorage, slot_index: int, world_position: Vector2) -> bool:
	if not storage:
		return false
	var item := storage.take_slot(slot_index)
	if item.is_empty():
		return false
	var sub_scene := ""
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "Player", true, false):
			var player := node as Player
			if player:
				sub_scene = player.current_sub_scene
				break
	if not spawn_drop(item, world_position, "", sub_scene):
		storage.put_slot(slot_index, item)
		return false
	SaveManager.request_auto_save("丢弃物品")
	return true

func spawn_drop(item: Dictionary, world_position: Vector2, scene_id: String = "", sub_scene: String = "") -> bool:
	if not has_item(String(item.get("id", ""))):
		return false
	if scene_id.is_empty():
		scene_id = SceneManager.get_current_scene()
	if scene_id.is_empty():
		return false
	_drop_serial += 1
	var drop_id := "%s_%d_%d" % [scene_id, Time.get_ticks_msec(), _drop_serial]
	var record := {"drop_id": drop_id, "item": item.duplicate(true), "position": world_position, "sub_scene": sub_scene}
	if not ground_drops.has(scene_id):
		ground_drops[scene_id] = []
	ground_drops[scene_id].append(record)
	if _instantiate_drop(record, scene_id):
		return true
	# 实例化失败时必须撤销持久化记录，否则物品放回背包后会在下次进图复制。
	ground_drops[scene_id].erase(record)
	if ground_drops[scene_id].is_empty():
		ground_drops.erase(scene_id)
	return false

func restore_scene_drops(scene_id: String) -> void:
	if scene_id.is_empty() or not ground_drops.has(scene_id):
		return
	for record in ground_drops[scene_id]:
		if record is Dictionary:
			_instantiate_drop(record, scene_id)

func pickup_drop(scene_id: String, drop_id: String) -> bool:
	if not ground_drops.has(scene_id):
		return false
	var records: Array = ground_drops[scene_id]
	for i in range(records.size()):
		var record = records[i]
		if String(record.get("drop_id", "")) != drop_id:
			continue
		var item: Dictionary = record.get("item", {})
		if not inventory.can_add(String(item.get("id", "")), int(item.get("count", 1))):
			MessageDisplayManager.show_info_message("背包已满")
			return false
		inventory.add_item(String(item["id"]), int(item.get("count", 1)))
		records.remove_at(i)
		SaveManager.request_auto_save("拾取物品")
		return true
	return false

func _instantiate_drop(record: Dictionary, scene_id: String) -> bool:
	var scene := get_tree().current_scene
	if not scene or not (scene is WorldScene):
		return false
	var drop := DROP_SCENE.instantiate() as DroppedItem
	if not drop:
		return false
	scene.add_child(drop)
	drop.setup(String(record["drop_id"]), record["item"], record.get("position", Vector2.ZERO), scene_id, String(record.get("sub_scene", "")))
	return true

func serialize() -> Dictionary:
	var chest_data := {}
	for chest_id in chests:
		var storage := chests[chest_id] as InventoryStorage
		chest_data[chest_id] = {
			"type": String(chest_types.get(chest_id, "")),
			"capacity": storage.capacity,
			"auto_expand": storage.auto_expand,
			"slots": storage.serialize(),
		}
	return {"inventory": inventory.serialize(), "chests": chest_data, "ground_drops": ground_drops.duplicate(true)}

func load_data(data: Dictionary) -> void:
	inventory.load_data(data.get("inventory", []))
	chests.clear()
	chest_types.clear()
	var chest_data = data.get("chests", {})
	if chest_data is Dictionary:
		for chest_id in chest_data:
			var raw = chest_data[chest_id]
			# 兼容早期仅保存 slots 数组的格式。
			var slot_data = raw.get("slots", []) if raw is Dictionary else raw
			var saved_capacity := int(raw.get("capacity", 24)) if raw is Dictionary else 24
			var infinite := bool(raw.get("auto_expand", String(chest_id) == "rv_warehouse")) if raw is Dictionary else String(chest_id) == "rv_warehouse"
			var storage := InventoryStorage.new(saved_capacity, infinite)
			storage.load_data(slot_data)
			chests[chest_id] = storage
			chest_types[chest_id] = String(raw.get("type", "")) if raw is Dictionary else ""
	var drops = data.get("ground_drops", {})
	ground_drops = drops.duplicate(true) if drops is Dictionary else {}

func reset() -> void:
	# 保留 storage 实例，使 UI 的 changed 信号连接始终有效。
	inventory.load_data([])
	chests.clear()
	chest_types.clear()
	ground_drops.clear()
