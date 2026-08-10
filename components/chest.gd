class_name Chest
extends Area2D

const RV_WAREHOUSE_ID := "rv_warehouse"

## chest_id 标识这个箱子实例，必须在整个存档中唯一。
@export var chest_id: String = ""
## chest_type 决定 loot_tables.json 中使用的生成规则。
@export var chest_type: String = ""
@export var display_name: String = "箱子"
@export var capacity: int = 24
@export var infinite_storage: bool = false
@export var sub_scene: String = ""

var player_ref: Player
var world_player: Player
var _option_active := false

@onready var visual: CanvasItem = $Visual

func _ready() -> void:
	if chest_id.is_empty():
		push_error("箱子必须设置唯一 chest_id: %s" % get_path())
		monitoring = false
		return
	if chest_type.is_empty():
		push_warning("箱子未设置 chest_type，将生成空箱子: %s" % chest_id)
	elif not InventoryManager.loot_tables.has(chest_type):
		push_warning("未注册的箱子类型 %s: %s" % [chest_type, chest_id])
	if has_node("Visual/Label"):
		$Visual/Label.text = display_name
	# 第一次创建实例时立即按类型生成战利品；已有存档实例不会重复刷新。
	InventoryManager.get_chest(chest_id, chest_type, capacity, infinite_storage)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_ref = body
		_refresh_option()

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		player_ref = null
		_remove_option()

func _process(_delta: float) -> void:
	if not is_instance_valid(world_player):
		world_player = _find_player()
	if visual and world_player:
		visual.visible = sub_scene.is_empty() or world_player.current_sub_scene == sub_scene
	# Portal 可能在玩家仍处于碰撞范围内时切换 sub_scene。
	if is_instance_valid(player_ref):
		_refresh_option()

func _refresh_option() -> void:
	var should_show := _can_interact()
	if should_show == _option_active:
		return
	_option_active = should_show
	var system := _find_interaction_system()
	if not system:
		return
	if should_show:
		system.add_option("chest_" + chest_id, "打开" + display_name, self)
	else:
		system.remove_option("chest_" + chest_id)

func interact() -> void:
	if not _can_interact():
		return
	var ui := get_node_or_null("/root/InventoryUI")
	if ui:
		ui.open_chest(chest_id, chest_type, display_name, capacity, infinite_storage)

func _can_interact() -> bool:
	return player_ref != null and (sub_scene.is_empty() or player_ref.current_sub_scene == sub_scene)

func _remove_option() -> void:
	_option_active = false
	var system := _find_interaction_system()
	if system:
		system.remove_option("chest_" + chest_id)

func _find_player() -> Player:
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "Player", true, false):
			return node as Player
	return null

func _find_interaction_system() -> InteractionSystem:
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "InteractionSystem", true, false):
			return node as InteractionSystem
	return null
