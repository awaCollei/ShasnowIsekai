extends Node

const REGISTRY_PATH := "res://inventory/items.json"
const LOOT_TABLES_PATH := "res://inventory/loot_tables.json"
const ITEM_TEXTURE_DIR := "res://assets/items/"
const DROP_SCENE := preload("res://inventory/dropped_item.tscn")

var registry: Dictionary = {}
var loot_tables: Dictionary = {}
var inventory := InventoryStorage.new(10)
var chests: Dictionary = {}
## 与 chests 同键保存类型；类型属于实例存档，不能仅依赖当前房间配置。
var chest_types: Dictionary = {}
var ground_drops: Dictionary = {}
var _drop_serial := 0

func get_drop_storage_id(sub_scene: String = "") -> String:
	if sub_scene == "rv_indoor" or sub_scene == "rv_roof":
		return "rv"
	return SaveManager.current_zone_id

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
		var star_levels: Dictionary = loot_tables[type_id].get("star_levels", {})
		for star in ["1", "2", "3"]:
			var rules = star_levels.get(star, {}).get("rules", [])
			var probability_sum := 0.0
			for rule in rules:
				if not rule is Dictionary:
					continue
				probability_sum += maxf(0.0, float(rule.get("chance", 0.0)))
				var item_id := String(rule.get("item", ""))
				if not has_item(item_id):
					push_warning("箱子类型 %s（%s 星）引用了未注册物品: %s" % [type_id, star, item_id])
			if probability_sum > 1.0001:
				push_warning("箱子类型 %s（%s 星）的每格概率总和大于 1，将按规则顺序截断" % [type_id, star])

func has_item(item_id: String) -> bool:
	return registry.has(item_id)

func get_item(item_id: String) -> Dictionary:
	return registry.get(item_id, {})

func get_max_stack(item_id: String) -> int:
	return maxi(1, int(get_item(item_id).get("max_stack", 99)))

func get_texture_path(item_id: String) -> String:
	return ITEM_TEXTURE_DIR + item_id + ".png"

func get_chest(chest_id: String, chest_type: String = "", star_level: int = 1, capacity: int = 24) -> InventoryStorage:
	if chests.has(chest_id):
		return chests[chest_id]
	var config: Dictionary = loot_tables.get(chest_type, {})
	var actual_capacity := maxi(1, int(config.get("capacity", capacity)))
	var storage := InventoryStorage.new(actual_capacity)
	chests[chest_id] = storage
	chest_types[chest_id] = chest_type
	_generate_chest_loot(storage, chest_type, chest_id, star_level)
	SaveManager.request_auto_save("生成箱子战利品")
	return storage

## 逐格进行一次随机判定。规则概率按数组顺序占用 [0, 1) 区间，
## 未命中任何规则时该格保持为空。
func _generate_chest_loot(storage: InventoryStorage, chest_type: String, chest_id: String, star_level: int) -> void:
	var config: Dictionary = loot_tables.get(chest_type, {})
	if String(config.get("generation", "none")) != "per_slot_probability":
		return
	var star_levels: Dictionary = config.get("star_levels", {})
	var level_config: Dictionary = star_levels.get(str(star_level), {})
	var rules = level_config.get("rules", [])
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

func drop_from_storage(storage: InventoryStorage, slot_index: int, world_position: Vector2, amount: int = -1) -> bool:
	if not storage or slot_index < 0 or slot_index >= storage.slots.size() or not storage.slots[slot_index] is Dictionary:
		return false
	var available := int(storage.slots[slot_index].get("count", 1))
	var drop_amount := available if amount < 0 else amount
	var item := storage.take_amount(slot_index, drop_amount)
	if item.is_empty():
		return false
	var sub_scene := ""
	var owner_scene := ""
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "Player", true, false):
			var player := node as Player
			if player:
				sub_scene = player.current_sub_scene
				break
		# 房车是跨区域共享的存储空间；普通掉落物属于当前区域。
	owner_scene = get_drop_storage_id(sub_scene)
	if not spawn_drop(item, world_position, owner_scene, sub_scene):
		# 原格仍有同类物品时 put_slot 会正确合并；整组丢弃失败时则原位放回。
		storage.put_slot(slot_index, item)
		return false
	SaveManager.request_auto_save("丢弃物品")
	return true

func spawn_drop(item: Dictionary, world_position: Vector2, scene_id: String = "", sub_scene: String = "") -> bool:
	if not has_item(String(item.get("id", ""))):
		return false
	if scene_id.is_empty():
		scene_id = get_drop_storage_id(sub_scene)
	if scene_id.is_empty():
		return false
	_drop_serial += 1
	var drop_id := "%s_%d_%d" % [scene_id, Time.get_ticks_msec(), _drop_serial]
	var saved_position := world_position
	if scene_id == "rv":
		var current_scene := get_tree().current_scene
		var rv := current_scene.find_child("RV", true, false) if current_scene else null
		if rv:
			saved_position = (rv as Node2D).to_local(world_position)
	var record := {"drop_id": drop_id, "item": item.duplicate(true), "position": saved_position, "sub_scene": sub_scene}
	if not ground_drops.has(scene_id):
		ground_drops[scene_id] = []
	ground_drops[scene_id].append(record)
	_deduplicate_drop_records(scene_id)
	if _instantiate_drop(record, scene_id):
		return true
	# 实例化失败时必须撤销持久化记录，否则物品放回背包后会在下次进图复制。
	ground_drops[scene_id].erase(record)
	if ground_drops[scene_id].is_empty():
		ground_drops.erase(scene_id)
	return false

func _deduplicate_drop_records(scene_id: String) -> void:
	if not ground_drops.has(scene_id):
		return
	var seen := {}
	var records: Array = ground_drops[scene_id]
	for index in range(records.size() - 1, -1, -1):
		var drop_id := String(records[index].get("drop_id", ""))
		if seen.has(drop_id):
			records.remove_at(index)
		else:
			seen[drop_id] = true

func restore_scene_drops(scene_id: String) -> void:
	_deduplicate_drop_records(scene_id)
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
			MessageDisplayManager.show_failure_message("背包已经满了！")
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
	# 房车子场景可能仍处于 _ready() 的子节点装配阶段，不能立即 add_child。
	# 同时 DroppedItem.setup() 依赖 @onready 的 Sprite2D，因此必须在入树后执行。
	call_deferred("_attach_drop", scene, drop, record.duplicate(true), scene_id)
	return true

func _attach_drop(scene: Node, drop: DroppedItem, record: Dictionary, scene_id: String) -> void:
	if not is_instance_valid(scene) or not is_instance_valid(drop):
		return
	if not scene.is_inside_tree() or not (scene is WorldScene):
		drop.free()
		return
	scene.add_child(drop)
	var drop_position: Vector2 = record.get("position", Vector2.ZERO)
	if scene_id == "rv":
		var rv := scene.find_child("RV", true, false)
		if rv:
			drop_position = (rv as Node2D).to_global(drop_position)
	drop.setup(String(record["drop_id"]), record["item"], drop_position, scene_id, String(record.get("sub_scene", "")))

func serialize() -> Dictionary:
	var chest_data := {}
	for chest_id in chests:
		var storage := chests[chest_id] as InventoryStorage
		chest_data[chest_id] = {
			"type": String(chest_types.get(chest_id, "")),
			"capacity": storage.capacity,
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
			var raw: Dictionary = chest_data[chest_id]
			var storage := InventoryStorage.new(int(raw.get("capacity", 24)))
			storage.load_data(raw.get("slots", []))
			chests[chest_id] = storage
			chest_types[chest_id] = String(raw.get("type", ""))
	var drops = data.get("ground_drops", {})
	ground_drops = drops.duplicate(true) if drops is Dictionary else {}

func reset() -> void:
	# 保留 storage 实例，使 UI 的 changed 信号连接始终有效。
	inventory.load_data([])
	chests.clear()
	chest_types.clear()
	ground_drops.clear()
