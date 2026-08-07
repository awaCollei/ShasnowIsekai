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
var hp: int

func _ready() -> void:
	hp = max_hp
	monitoring = false
	monitorable = true

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
