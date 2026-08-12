class_name InventorySlot
extends Panel

signal slot_selected(storage: InventoryStorage, index: int)
signal quick_transfer_requested(storage: InventoryStorage, index: int)
signal outside_drop_requested(storage: InventoryStorage, index: int)

const QUALITY_COLORS := {
	1: Color(0.65, 0.65, 0.65,0.5),   # 亮灰
	2: Color(0.30, 0.85, 0.30,0.5),   # 亮绿
	3: Color(0.30, 0.60, 0.95,0.5),   # 亮蓝
	4: Color(0.70, 0.35, 0.90,0.5),   # 亮紫
	5: Color(0.95, 0.60, 0.10,0.5),   # 亮橙
	6: Color(0.95, 0.25, 0.25,0.5),   # 亮红
}

var storage: InventoryStorage
var slot_index := -1
var inventory_ui: Node
var drop_boundary: Control
var _is_drag_source := false
var _suppress_release_click := false

@onready var selected_frame: Panel = $Selected
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
		if ResourceLoader.exists(path, "Texture2D"):
			icon.texture = ResourceLoader.load(path, "Texture2D") as Texture2D
		var config := InventoryManager.get_item(item_id)
		tooltip_text = "%s\n%s" % [config.get("name", item_id), config.get("description", "")]
		var count := int(item.get("count", 1))
		count_label.text = str(count) if count > 1 else ""
		_apply_quality_bg(config.get("quality", 0))
	else:
		_apply_quality_bg(0)

func _apply_quality_bg(quality: int) -> void:
	var base := get_theme_stylebox("panel", "Panel")
	var style_box: StyleBoxFlat
	if base is StyleBoxFlat:
		style_box = base.duplicate() as StyleBoxFlat
	else:
		style_box = StyleBoxFlat.new()
		style_box.set_content_margin_all(0)
	if quality > 0 and QUALITY_COLORS.has(quality):
		style_box.bg_color = QUALITY_COLORS[quality]
	add_theme_stylebox_override("panel", style_box)

func set_selected(selected: bool) -> void:
	selected_frame.visible = selected
	self_modulate = Color(1.08, 1.13, 1.12, 1.0) if selected else Color.WHITE

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
	if not storage or slot_index < 0 or slot_index >= storage.slots.size() or not storage.slots[slot_index] is Dictionary:
		return null
	_is_drag_source = true
	icon.modulate.a = 0.35
	count_label.modulate.a = 0.35

	var item: Dictionary = storage.slots[slot_index]
	var preview_root := Control.new()
	preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var preview_content := Control.new()
	preview_content.position = Vector2(-32, -32)
	preview_content.size = Vector2(64, 64)

	var preview_icon := TextureRect.new()
	preview_icon.texture = icon.texture
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_icon.size = Vector2(64, 64)
	preview_content.add_child(preview_icon)

	var preview_count := Label.new()
	preview_count.size = Vector2(30, 22)
	preview_count.position = Vector2(30, 40)
	preview_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	preview_count.add_theme_constant_override("outline_size", 3)
	preview_count.add_theme_color_override("font_outline_color", Color.BLACK)
	var count := int(item.get("count", 1))
	preview_count.text = str(count) if count > 1 else ""
	preview_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_content.add_child(preview_count)

	preview_root.add_child(preview_content)
	set_drag_preview(preview_root)
	return {"storage": storage, "index": slot_index}

func _can_drop_data(_at_position: Vector2, data) -> bool:
	return data is Dictionary and data.get("storage") is InventoryStorage and int(data.get("index", -1)) >= 0

func _drop_data(_at_position: Vector2, data) -> void:
	if not _can_drop_data(_at_position, data) or not is_instance_valid(inventory_ui):
		return
	inventory_ui.move_item(data.get("storage") as InventoryStorage, int(data.get("index", -1)), storage, slot_index)

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
