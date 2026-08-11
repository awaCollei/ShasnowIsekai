class_name DroppedItem
extends Area2D

var drop_id := ""
var item_data: Dictionary = {}
var scene_id := ""
var sub_scene := ""
var player_ref: Player
var world_player: Player
var _option_active := false

@onready var sprite: Sprite2D = $Sprite2D

func setup(id: String, item: Dictionary, world_position: Vector2, owning_scene_id: String, owning_sub_scene: String = "") -> void:
	drop_id = id
	item_data = item.duplicate(true)
	scene_id = owning_scene_id
	sub_scene = owning_sub_scene
	global_position = world_position + Vector2(0, 80)
	var path := InventoryManager.get_texture_path(String(item_data.get("id", "")))
	if ResourceLoader.exists(path):
		sprite.texture = load(path)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if not is_instance_valid(world_player):
		world_player = _find_player()
	if world_player:
		if sub_scene == "indoor":
			sprite.visible = world_player.current_sub_scene == sub_scene
		else:
			sprite.visible = true
	if is_instance_valid(player_ref):
		_refresh_option()

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_ref = body
		_refresh_option()

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		player_ref = null
		_remove_option()

func _refresh_option() -> void:
	var should_show := player_ref != null and (sub_scene.is_empty() or player_ref.current_sub_scene == sub_scene)
	if should_show == _option_active:
		return
	var system := _find_interaction_system()
	if not system:
		return
	_option_active = should_show
	if should_show:
		var item_name := String(InventoryManager.get_item(String(item_data.get("id", ""))).get("name", item_data.get("id", "物品")))
		system.add_option("drop_" + drop_id, "拾取 " + item_name, self)
	else:
		system.remove_option("drop_" + drop_id)

func interact() -> void:
	if player_ref == null or (not sub_scene.is_empty() and player_ref.current_sub_scene != sub_scene):
		return
	if InventoryManager.pickup_drop(scene_id, drop_id):
		_remove_option()
		queue_free()

func _remove_option() -> void:
	_option_active = false
	var system := _find_interaction_system()
	if system:
		system.remove_option("drop_" + drop_id)

func _find_player() -> Player:
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "Player", true, false):
			return node as Player
	return null

func _find_interaction_system() -> InteractionSystem:
	var scene := get_tree().current_scene
	if not scene:
		return null
	for node in scene.find_children("*", "InteractionSystem", true, false):
		return node as InteractionSystem
	return null
