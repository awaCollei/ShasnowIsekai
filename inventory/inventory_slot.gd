class_name InventorySlot
extends Panel

signal slot_selected(storage: InventoryStorage, index: int)
signal quick_transfer_requested(storage: InventoryStorage, index: int)
signal outside_drop_requested(storage: InventoryStorage, index: int)

var storage: InventoryStorage
var slot_index := -1
var inventory_ui: Node
var drop_boundary: Control
var _is_drag_source := false
var _suppress_release_click := false

@onready var icon: TextureRect = $Icon
@onready var count_label: Label = $Count

func _ready() -> void:
	gui_input.connect(_on_gui_input)

func setup(owner_storage: InventoryStorage, index: int, ui: Node, boundary: Control, selected: bool = false) -> void:
	storage = owner_storage
	slot_index = index
	inventory_ui = ui
	drop_boundary = boundary
	set_selected(selected)
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
		tooltip_text = "%s\n%s" % [config.get("name", item_id), config.get("description", "")]
		var count := int(item.get("count", 1))
		count_label.text = str(count) if count > 1 else ""

func set_selected(selected: bool) -> void:
	self_modulate = Color(1.18, 1.08, 1.28, 1.0) if selected else Color.WHITE

func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_suppress_release_click = false
		if event.shift_pressed or event.double_click:
			_suppress_release_click = true
			quick_transfer_requested.emit(storage, slot_index)
			accept_event()
	elif not _suppress_release_click and not _is_drag_source:
		slot_selected.emit(storage, slot_index)
		accept_event()
	_suppress_release_click = false if not event.pressed else _suppress_release_click

func _get_drag_data(_at_position: Vector2):
	if not storage or slot_index >= storage.slots.size() or not storage.slots[slot_index] is Dictionary:
		return null
	_is_drag_source = true
	icon.modulate.a = 0.35
	count_label.modulate.a = 0.35

	var item: Dictionary = storage.slots[slot_index]
	var preview_root := Control.new()
	preview_root.custom_minimum_size = Vector2(64, 64)
	preview_root.size = Vector2(64, 64)
	preview_root.position = Vector2(-32, -32)
	var preview_icon := TextureRect.new()
	preview_icon.texture = icon.texture
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_root.add_child(preview_icon)
	preview_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var preview_count := Label.new()
	preview_count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	preview_count.position = Vector2(-34, -26)
	preview_count.size = Vector2(30, 22)
	preview_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	preview_count.add_theme_constant_override("outline_size", 3)
	preview_count.add_theme_color_override("font_outline_color", Color.BLACK)
	var count := int(item.get("count", 1))
	preview_count.text = str(count) if count > 1 else ""
	preview_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_root.add_child(preview_count)
	set_drag_preview(preview_root)
	return {"storage": storage, "index": slot_index}

func _can_drop_data(_at_position: Vector2, data) -> bool:
	return data is Dictionary and data.has("storage") and data.has("index")

func _drop_data(_at_position: Vector2, data) -> void:
	inventory_ui.move_item(data.storage, int(data.index), storage, slot_index)

func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or not _is_drag_source:
		return
	_is_drag_source = false
	if icon:
		icon.modulate = Color.WHITE
	if count_label:
		count_label.modulate = Color.WHITE
	if not get_viewport().gui_is_drag_successful() and drop_boundary and not drop_boundary.get_global_rect().has_point(get_global_mouse_position()):
		outside_drop_requested.emit(storage, slot_index)
