extends CanvasLayer

const SLOT_SCENE := preload("res://inventory/inventory_slot.tscn")

@onready var window: PanelContainer = $Center/Window
@onready var title: Label = $Center/Window/Margin/VBox/TitleRow/Title
@onready var player_grid: GridContainer = $Center/Window/Margin/VBox/Columns/PlayerSide/Scroll/PlayerGrid
@onready var chest_side: VBoxContainer = $Center/Window/Margin/VBox/Columns/ChestSide
@onready var chest_title: Label = $Center/Window/Margin/VBox/Columns/ChestSide/ChestTitle
@onready var chest_grid: GridContainer = $Center/Window/Margin/VBox/Columns/ChestSide/Scroll/ChestGrid

var current_chest: InventoryStorage
var current_chest_id := ""
var _refresh_pending := false
var _is_open := false
var _was_paused := false

func _ready() -> void:
	hide_inventory()
	InventoryManager.inventory.changed.connect(_queue_refresh)
	$Center/Window/Margin/VBox/TitleRow/Close.pressed.connect(hide_inventory)

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
	visible = true
	chest_side.visible = true
	title.text = "物品管理"
	chest_title.text = display_name
	_refresh()

func _begin_open() -> void:
	if not _is_open:
		_was_paused = get_tree().paused
		_is_open = true
		get_tree().paused = true

func hide_inventory() -> void:
	visible = false
	current_chest = null
	current_chest_id = ""
	if _is_open:
		_is_open = false
		get_tree().paused = _was_paused

func move_item(from: InventoryStorage, from_index: int, to: InventoryStorage, to_index: int) -> void:
	if not from or not to or from_index == to_index and from == to:
		return
	var moving := from.take_slot(from_index)
	if moving.is_empty():
		return
	var remainder := to.put_slot(to_index, moving)
	if not remainder.is_empty():
		from.put_slot(from_index, remainder)
	SaveManager.request_auto_save("整理物品")
	_refresh()

func _on_outside_drop(storage: InventoryStorage, index: int) -> void:
	if storage != InventoryManager.inventory:
		return
	var player := _find_player()
	if not player:
		return
	var offset := Vector2(70.0 if player.animation.sprite.flip_h else -70.0, 0.0)
	InventoryManager.drop_from_inventory(index, player.global_position + offset)
	_refresh()

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
	_fill_grid(player_grid, InventoryManager.inventory)
	if current_chest:
		current_chest.ensure_trailing_row()
		_fill_grid(chest_grid, current_chest)

func _fill_grid(grid: GridContainer, storage: InventoryStorage) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for i in range(storage.slots.size()):
		var slot := SLOT_SCENE.instantiate() as InventorySlot
		grid.add_child(slot)
		slot.setup(storage, i, self, window)
		slot.outside_drop_requested.connect(_on_outside_drop)

func _find_player() -> Player:
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "Player", true, false):
			return node as Player
	return null
