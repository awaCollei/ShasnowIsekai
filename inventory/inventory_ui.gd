extends CanvasLayer

const SLOT_SCENE := preload("res://inventory/inventory_slot.tscn")

@onready var window: PanelContainer = $Center/Window
@onready var title: Label = $Center/Window/Margin/VBox/TitleRow/Title
@onready var player_grid: GridContainer = $Center/Window/Margin/VBox/Columns/PlayerSide/Scroll/PlayerGrid
@onready var chest_side: VBoxContainer = $Center/Window/Margin/VBox/Columns/ChestSide
@onready var chest_title: Label = $Center/Window/Margin/VBox/Columns/ChestSide/ChestTitle
@onready var chest_grid: GridContainer = $Center/Window/Margin/VBox/Columns/ChestSide/Scroll/ChestGrid
@onready var detail_side: PanelContainer = $Center/Window/Margin/VBox/Columns/DetailSide
@onready var detail_icon: TextureRect = $Center/Window/Margin/VBox/Columns/DetailSide/Margin/VBox/Icon
@onready var detail_name: Label = $Center/Window/Margin/VBox/Columns/DetailSide/Margin/VBox/Name
@onready var detail_count: Label = $Center/Window/Margin/VBox/Columns/DetailSide/Margin/VBox/Count
@onready var detail_description: Label = $Center/Window/Margin/VBox/Columns/DetailSide/Margin/VBox/Description
@onready var split_button: Button = $Center/Window/Margin/VBox/Columns/DetailSide/Margin/VBox/Buttons/Split
@onready var discard_button: Button = $Center/Window/Margin/VBox/Columns/DetailSide/Margin/VBox/Buttons/Discard
@onready var use_button: Button = $Center/Window/Margin/VBox/Columns/DetailSide/Margin/VBox/Buttons/Use

var current_chest: InventoryStorage
var current_chest_id := ""
var selected_storage: InventoryStorage
var selected_index := -1
var _refresh_pending := false
var _is_open := false

func _ready() -> void:
	hide_inventory()
	InventoryManager.inventory.changed.connect(_queue_refresh)
	$Center/Window/Margin/VBox/TitleRow/Close.pressed.connect(hide_inventory)
	split_button.pressed.connect(_split_selected)
	discard_button.pressed.connect(_discard_selected)
	use_button.pressed.connect(_use_selected)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and SaveManager.is_in_game and (visible or not get_tree().paused):
		if visible:
			hide_inventory()
		else:
			open_inventory()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("menu"):
		hide_inventory()
		get_viewport().set_input_as_handled()

func open_inventory() -> void:
	_begin_open()
	current_chest = null
	current_chest_id = ""
	_clear_selection()
	visible = true
	chest_side.visible = false
	title.text = "背包"
	_refresh()

func open_chest(chest_id: String, chest_type: String, display_name: String, capacity: int, infinite: bool) -> void:
	_begin_open()
	current_chest_id = chest_id
	current_chest = InventoryManager.get_chest(chest_id, chest_type, capacity, infinite)
	if not current_chest.changed.is_connected(_queue_refresh):
		current_chest.changed.connect(_queue_refresh)
	_clear_selection()
	visible = true
	chest_side.visible = true
	title.text = "物品管理"
	chest_title.text = display_name
	_refresh()

func _begin_open() -> void:
	if not _is_open:
		_is_open = true
		_set_player_lock(true)

func hide_inventory() -> void:
	visible = false
	current_chest = null
	current_chest_id = ""
	_clear_selection()
	if _is_open:
		_is_open = false
		_set_player_lock(false)

func _set_player_lock(locked: bool) -> void:
	var player := _find_player()
	if player:
		player.ui_locked = locked

func move_item(from: InventoryStorage, from_index: int, to: InventoryStorage, to_index: int) -> void:
	if not from or not to or from_index == to_index and from == to:
		return
	var moving := from.take_slot(from_index)
	if moving.is_empty():
		return
	var remainder := to.put_slot(to_index, moving)
	if not remainder.is_empty():
		from.put_slot(from_index, remainder)
	_clear_selection()
	SaveManager.request_auto_save("整理物品")
	_refresh()

func _on_slot_selected(storage: InventoryStorage, index: int) -> void:
	if index < 0 or index >= storage.slots.size() or not storage.slots[index] is Dictionary:
		_clear_selection()
	elif selected_storage == storage and selected_index == index:
		_clear_selection()
	else:
		selected_storage = storage
		selected_index = index
	_refresh()

func _on_quick_transfer(storage: InventoryStorage, index: int) -> void:
	var target: InventoryStorage
	if storage == InventoryManager.inventory:
		target = current_chest
	elif current_chest and storage == current_chest:
		target = InventoryManager.inventory
	if not target or index < 0 or index >= storage.slots.size() or not storage.slots[index] is Dictionary:
		return
	var item: Dictionary = storage.slots[index]
	var item_id := String(item.get("id", ""))
	var count := int(item.get("count", 1))
	if not target.add_item(item_id, count):
		MessageDisplayManager.show_info_message("目标容器空间不足")
		return
	storage.take_slot(index)
	_clear_selection()
	SaveManager.request_auto_save("快速转移物品")
	_refresh()

func _on_outside_drop(storage: InventoryStorage, index: int) -> void:
	var player := _find_player()
	if not player:
		return
	var offset := Vector2(70.0 if player.animation.sprite.flip_h else -70.0, 0.0)
	if InventoryManager.drop_from_storage(storage, index, player.global_position + offset):
		_clear_selection()
	_refresh()

func _split_selected() -> void:
	if not _selection_is_valid():
		return
	if not selected_storage.split_stack(selected_index):
		MessageDisplayManager.show_info_message("无法分离：数量不足或没有空格")
	else:
		SaveManager.request_auto_save("分离物品堆叠")
	_refresh()

func _discard_selected() -> void:
	if not _selection_is_valid():
		return
	var player := _find_player()
	if not player:
		return
	var offset := Vector2(70.0 if player.animation.sprite.flip_h else -70.0, 0.0)
	if InventoryManager.drop_from_storage(selected_storage, selected_index, player.global_position + offset):
		_clear_selection()
	_refresh()

func _use_selected() -> void:
	if not _selection_is_valid():
		return
	var item: Dictionary = selected_storage.slots[selected_index]
	var config := InventoryManager.get_item(String(item.get("id", "")))
	# 第一版先保留统一入口；后续按 use_action 接入消耗品和装备效果。
	if not config.get("usable", false):
		MessageDisplayManager.show_info_message("该物品暂时无法使用")
		return
	MessageDisplayManager.show_info_message("尚未实现使用效果：%s" % config.get("name", item.get("id", "物品")))

func _selection_is_valid() -> bool:
	return selected_storage != null and selected_index >= 0 and selected_index < selected_storage.slots.size() and selected_storage.slots[selected_index] is Dictionary

func _clear_selection() -> void:
	selected_storage = null
	selected_index = -1
	if is_instance_valid(detail_side):
		detail_side.modulate.a = 0.0
		detail_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_instance_valid(split_button):
			split_button.disabled = true
			discard_button.disabled = true
			use_button.disabled = true

func _queue_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_run_queued_refresh")

func _run_queued_refresh() -> void:
	_refresh_pending = false
	_refresh()

func _refresh() -> void:
	if not is_node_ready() or not visible:
		return
	if selected_storage and not _selection_is_valid():
		_clear_selection()
	_fill_grid(player_grid, InventoryManager.inventory)
	if current_chest:
		current_chest.ensure_trailing_row()
		_fill_grid(chest_grid, current_chest)
	_refresh_details()

func _fill_grid(grid: GridContainer, storage: InventoryStorage) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for i in range(storage.slots.size()):
		var slot := SLOT_SCENE.instantiate() as InventorySlot
		grid.add_child(slot)
		slot.setup(storage, i, self, window, selected_storage == storage and selected_index == i)
		slot.slot_selected.connect(_on_slot_selected)
		slot.quick_transfer_requested.connect(_on_quick_transfer)
		slot.outside_drop_requested.connect(_on_outside_drop)

func _refresh_details() -> void:
	if not _selection_is_valid():
		detail_side.modulate.a = 0.0
		detail_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	detail_side.modulate.a = 1.0
	detail_side.mouse_filter = Control.MOUSE_FILTER_STOP
	var item: Dictionary = selected_storage.slots[selected_index]
	var item_id := String(item.get("id", ""))
	var config := InventoryManager.get_item(item_id)
	var path := InventoryManager.get_texture_path(item_id)
	detail_icon.texture = load(path) if ResourceLoader.exists(path) else null
	detail_name.text = String(config.get("name", item_id))
	detail_count.text = "数量：%d" % int(item.get("count", 1))
	detail_description.text = String(config.get("description", "暂无说明"))
	split_button.disabled = int(item.get("count", 1)) <= 1
	discard_button.disabled = false
	use_button.disabled = false

func _find_player() -> Player:
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "Player", true, false):
			return node as Player
	return null
