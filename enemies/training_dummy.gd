extends Enemy
class_name TrainingDummy


func _ready() -> void:
	battle_name = "训练木桩"
	battle_enabled = false
	super._ready()


func take_damage(amount: int) -> void:
	# 训练木桩无限生命，只发出伤害信号但不减血
	damage_taken.emit(amount)
