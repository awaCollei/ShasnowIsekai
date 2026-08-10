class_name InventorySlot
extends Panel

signal outside_drop_requested(storage: InventoryStorage, index: int)

var storage: InventoryStorage
var slot_index := -1
var inventory_ui: Node
var drop_boundary: Control
var _is_drag_source := false

@onready var icon: TextureRect = $Icon
@onready var count_label: Label = $Count

func setup(owner_storage: InventoryStorage, index: int, ui: Node, boundary: Control) -> void:
	storage = owner_storage
	slot_index = index
	inventory_ui = ui
	drop_boundary = boundary
	refresh()

func refresh() -> void:
	if not storage or slot_index < 0 or slot_index >= storage.slots.size():
		return
	var item = storage.slots[slot_index]
	icon.texture = null
	count_label.text = ""
	tooltip_text = ""
	if item is Dictionary:
		var item_id := String(item.get("id", ""))
		var path := InventoryManager.get_texture_path(item_id)
		if ResourceLoader.exists(path):
			icon.texture = load(path)
		var config := InventoryManager.get_item(item_id)
		tooltip_text = "%s\n%s" % [config.get("名称", item_id), config.get("说明", "")]
		var count := int(item.get("count", 1))
		count_label.text = str(count) if count > 1 else ""

func _get_drag_data(_at_position: Vector2):
	if not storage or slot_index >= storage.slots.size() or not storage.slots[slot_index] is Dictionary:
		return null
	_is_drag_source = true
	var preview := TextureRect.new()
	preview.texture = icon.texture
	preview.custom_minimum_size = Vector2(52, 52)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(preview)
	return {"storage": storage, "index": slot_index}

func _can_drop_data(_at_position: Vector2, data) -> bool:
	return data is Dictionary and data.has("storage") and data.has("index")

func _drop_data(_at_position: Vector2, data) -> void:
	inventory_ui.move_item(data.storage, int(data.index), storage, slot_index)

func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or not _is_drag_source:
		return
	_is_drag_source = false
	if not get_viewport().gui_is_drag_successful() and drop_boundary and not drop_boundary.get_global_rect().has_point(get_global_mouse_position()):
		outside_drop_requested.emit(storage, slot_index)
