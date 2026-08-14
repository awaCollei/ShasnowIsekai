class_name Chest
extends Area2D

## chest_id 标识这个箱子实例，必须在整个存档中唯一。
@export var chest_id: String = ""
## chest_type 决定 loot_tables.json 中使用的生成规则。
@export var chest_type: String = ""
## 动态建筑箱子继承所属区域星级；场景内固定箱子默认为 1 星。
@export_range(1, 3, 1) var star_level: int = 1
@export var display_name: String = "箱子"
@export var capacity: int = 24
@export var sub_scene: String = ""

var player_ref: Player
var world_player: Player
var _option_active := false
var _tween: Tween
var _ring_tween: Tween
var _is_glow_active := false

@onready var visual: Node2D = $Visual
@onready var glow: Sprite2D = $Visual/Glow
@onready var glow_ring: Sprite2D = $Visual/GlowRing
@onready var particles_primary: GPUParticles2D = $Visual/ParticlesPrimary
@onready var particles_secondary: GPUParticles2D = $Visual/ParticlesSecondary
@onready var particles_rising: GPUParticles2D = $Visual/ParticlesRising

func _ready() -> void:
	if chest_id.is_empty():
		push_error("箱子必须设置唯一 chest_id: %s" % get_path())
		monitoring = false
		return
	if chest_type.is_empty():
		push_warning("箱子未设置 chest_type，将生成空箱子: %s" % chest_id)
	elif not InventoryManager.loot_tables.has(chest_type):
		push_warning("未注册的箱子类型 %s: %s" % [chest_type, chest_id])
	
	InventoryManager.get_chest(chest_id, chest_type, star_level, capacity)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# 启动时直接显示光效（常亮）
	_show_glow(true)

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
	
	# 可见性控制：默认可见，但 rv_indoor 场景需要同场景才可见
	var should_visible := true
	if world_player and sub_scene == "rv_indoor":
		should_visible = world_player.current_sub_scene == sub_scene
	
	if visual:
		visual.visible = should_visible
		# 如果可见且光效未激活，重新激活
		if should_visible and not _is_glow_active:
			_show_glow(true)
		elif not should_visible and _is_glow_active:
			_show_glow(false)
	
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
		system.add_option("chest_" + chest_id, display_name, self)
	else:
		system.remove_option("chest_" + chest_id)

func interact() -> void:
	if not _can_interact():
		return
	var ui := get_node_or_null("/root/InventoryUI")
	if ui:
		ui.open_chest(chest_id, chest_type, display_name, capacity, star_level)

func _can_interact() -> bool:
	if not player_ref:
		return false
	# rv_indoor 场景需要同场景才能交互
	if sub_scene == "rv_indoor":
		return player_ref.current_sub_scene == sub_scene
	return true

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

func _show_glow(enabled: bool) -> void:
	if enabled == _is_glow_active:
		return
	_is_glow_active = enabled
	
	if _tween:
		_tween.kill()
		_tween = null
	if _ring_tween:
		_ring_tween.kill()
		_ring_tween = null
	
	if not glow or not glow_ring:
		return
	
	if enabled:
		# 主光晕淡入并脉动
		_tween = create_tween()
		_tween.set_trans(Tween.TRANS_SINE)
		_tween.set_ease(Tween.EASE_IN_OUT)
		glow.modulate.a = 0.0
		_tween.tween_property(glow, "modulate:a", 1.0, 0.4)
		_tween.tween_callback(_start_pulsing)
		
		# 光环淡入并旋转
		_ring_tween = create_tween()
		_ring_tween.set_trans(Tween.TRANS_SINE)
		_ring_tween.set_ease(Tween.EASE_IN_OUT)
		glow_ring.modulate.a = 0.0
		_ring_tween.tween_property(glow_ring, "modulate:a", 0.8, 0.5)
		_ring_tween.tween_callback(_start_ring_animation)
		
		# 开启所有粒子
		if particles_primary:
			particles_primary.emitting = true
		if particles_secondary:
			particles_secondary.emitting = true
		if particles_rising:
			particles_rising.emitting = true
	else:
		_tween = create_tween()
		_tween.set_trans(Tween.TRANS_SINE)
		_tween.set_ease(Tween.EASE_IN_OUT)
		_tween.tween_property(glow, "modulate:a", 0.0, 0.3)
		
		_ring_tween = create_tween()
		_ring_tween.set_trans(Tween.TRANS_SINE)
		_ring_tween.set_ease(Tween.EASE_IN_OUT)
		_ring_tween.tween_property(glow_ring, "modulate:a", 0.0, 0.3)
		
		if particles_primary:
			particles_primary.emitting = false
		if particles_secondary:
			particles_secondary.emitting = false
		if particles_rising:
			particles_rising.emitting = false

func _start_pulsing() -> void:
	if not glow:
		return
	if _tween:
		_tween.kill()
		_tween = null
	
	_tween = create_tween()
	_tween.set_loops()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(glow, "scale", Vector2(1.8, 1.8), 0.6)
	_tween.tween_property(glow, "scale", Vector2(1.2, 1.2), 0.6)

func _start_ring_animation() -> void:
	if not glow_ring:
		return
	if _ring_tween:
		_ring_tween.kill()
		_ring_tween = null
	
	_ring_tween = create_tween()
	_ring_tween.set_loops()
	_ring_tween.set_trans(Tween.TRANS_SINE)
	_ring_tween.set_ease(Tween.EASE_IN_OUT)
	_ring_tween.tween_property(glow_ring, "scale", Vector2(2.5, 2.5), 1.0)
	_ring_tween.tween_property(glow_ring, "scale", Vector2(1.5, 1.5), 1.0)
	
	# 旋转光环
	var rotate_tween = create_tween()
	rotate_tween.set_loops()
	rotate_tween.tween_property(glow_ring, "rotation", PI * 2, 3.0)