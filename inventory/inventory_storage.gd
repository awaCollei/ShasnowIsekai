class_name InventoryStorage
extends RefCounted

signal changed

var capacity: int
var auto_expand: bool
var slots: Array = []

func _init(initial_capacity: int = 30, expands: bool = false) -> void:
	capacity = maxi(initial_capacity, 1)
	auto_expand = expands
	slots.resize(capacity)
	slots.fill(null)

func add_item(item_id: String, count: int = 1) -> bool:
	if count <= 0 or not InventoryManager.has_item(item_id) or not can_add(item_id, count):
		return false
	var remaining := count
	var max_stack := InventoryManager.get_max_stack(item_id)
	for i in range(slots.size()):
		var item = slots[i]
		if item is Dictionary and String(item.get("id", "")) == item_id and int(item.get("count", 0)) < max_stack:
			var amount := mini(remaining, max_stack - int(item["count"]))
			item["count"] = int(item["count"]) + amount
			remaining -= amount
			if remaining == 0:
				changed.emit()
				return true
	while remaining > 0:
		var empty := _find_empty()
		if empty < 0:
			if not auto_expand:
				return false
			_add_row()
			empty = _find_empty()
		var amount := mini(remaining, max_stack)
		slots[empty] = {"id": item_id, "count": amount}
		remaining -= amount
	changed.emit()
	return true

func can_add(item_id: String, count: int = 1) -> bool:
	if auto_expand:
		return InventoryManager.has_item(item_id)
	var room := 0
	var max_stack := InventoryManager.get_max_stack(item_id)
	for item in slots:
		if item == null:
			room += max_stack
		elif item is Dictionary and String(item.get("id", "")) == item_id:
			room += max_stack - int(item.get("count", 0))
	return room >= count

func take_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size() or not slots[index] is Dictionary:
		return {}
	var result: Dictionary = slots[index]
	slots[index] = null
	changed.emit()
	return result

func put_slot(index: int, item: Dictionary) -> Dictionary:
	if index < 0 or item.is_empty():
		return item
	while index >= slots.size() and auto_expand:
		_add_row()
	if index >= slots.size():
		return item
	var current = slots[index]
	if current == null:
		slots[index] = item
		changed.emit()
		return {}
	if String(current.get("id", "")) == String(item.get("id", "")):
		var max_stack := InventoryManager.get_max_stack(String(item["id"]))
		var amount := mini(int(item["count"]), max_stack - int(current["count"]))
		current["count"] = int(current["count"]) + amount
		item["count"] = int(item["count"]) - amount
		changed.emit()
		return {} if int(item["count"]) <= 0 else item
	slots[index] = item
	changed.emit()
	return current

func set_slot(index: int, item) -> void:
	if index >= 0 and index < slots.size():
		slots[index] = item
		changed.emit()

func split_stack(index: int) -> bool:
	if index < 0 or index >= slots.size() or not slots[index] is Dictionary:
		return false
	var source: Dictionary = slots[index]
	var count := int(source.get("count", 1))
	if count <= 1:
		return false
	var empty := _find_empty()
	if empty < 0 and auto_expand:
		_add_row()
		empty = _find_empty()
	if empty < 0:
		return false
	var split_count := int(count / 2)
	source["count"] = count - split_count
	slots[empty] = {"id": String(source.get("id", "")), "count": split_count}
	changed.emit()
	return true

func ensure_trailing_row() -> void:
	if not auto_expand:
		return
	var empty_count := 0
	for item in slots:
		if item == null:
			empty_count += 1
	if empty_count < 6:
		_add_row()

func serialize() -> Array:
	return slots.duplicate(true)

func load_data(data, minimum_size: int = -1) -> void:
	var target_size := capacity if minimum_size < 0 else maxi(capacity, minimum_size)
	if data is Array:
		target_size = maxi(target_size, data.size()) if auto_expand else capacity
	slots.resize(target_size)
	slots.fill(null)
	if data is Array:
		for i in range(mini(data.size(), slots.size())):
			var raw = data[i]
			if raw is Dictionary and InventoryManager.has_item(String(raw.get("id", ""))):
				slots[i] = {"id": String(raw["id"]), "count": maxi(1, int(raw.get("count", 1)))}
	changed.emit()

func _find_empty() -> int:
	for i in range(slots.size()):
		if slots[i] == null:
			return i
	return -1

func _add_row() -> void:
	var old_size := slots.size()
	slots.resize(old_size + 6)
	for i in range(old_size, slots.size()):
		slots[i] = null
