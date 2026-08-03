extends Area2D
class_name Enemy

signal damage_taken(amount: int)
signal died

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

func die() -> void:
	died.emit()
	queue_free()
