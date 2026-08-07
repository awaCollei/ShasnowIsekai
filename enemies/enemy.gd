extends Area2D
class_name Enemy

signal damage_taken(amount: int)
signal died

@export_group("回合制战斗")
@export var battle_name: String = "敌人"
@export var battle_visual_id: String = "generic"
@export var battle_damage: float = 10.0
@export var battle_enabled: bool = true
@export var max_hp: int = 100
## 空字符串表示所有子场景；建筑内敌人由房间生成器写入对应楼层。
@export var sub_scene: String = ""
var hp: int
var _active_in_sub_scene := true

func _ready() -> void:
	z_index = 1
	hp = max_hp
	monitoring = false
	_update_sub_scene_state()


func _process(_delta: float) -> void:
	_update_sub_scene_state()


func _update_sub_scene_state() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var active := player == null or sub_scene.is_empty() or player.current_sub_scene == sub_scene
	if active == _active_in_sub_scene and visible == active:
		return
	_active_in_sub_scene = active
	visible = active
	monitorable = active

func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	damage_taken.emit(amount)
	if hp <= 0:
		die()


## 回合制专用：战斗结束前只结算数值，不提前释放世界中的敌人实例。
func apply_battle_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	hp = max(0, hp - amount)
	damage_taken.emit(amount)


func get_battle_damage() -> float:
	return battle_damage


func die() -> void:
	died.emit()
	queue_free()
