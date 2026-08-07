extends Node2D
class_name BattleActorView

## 战斗场景中的纯表现代理，不参与世界碰撞与 AI。
var source_enemy: Enemy
var is_player := false
var home_position := Vector2.ZERO
var sprite: Sprite2D
var name_label: Label
var hp_bar: ProgressBar
var _idle_frames: Array[Texture2D] = []
var _attack_frames: Array[Texture2D] = []
var _frame_index := 0
var _frame_time := 0.0
var _playing_attack := false


func setup_player() -> void:
	is_player = true
	_create_nodes("夏雪")
	_load_sequence(_idle_frames, "res://assets/shasnow/stand/stand_%d.png", 1)
	_load_sequence(_attack_frames, "res://assets/shasnow/basic_attack/basic_attack_%d.png", 32)
	_apply_first_frame()


func setup_enemy(enemy: Enemy) -> void:
	source_enemy = enemy
	_create_nodes(enemy.battle_name)
	var kind := enemy.battle_visual_id
	if kind == "slime":
		_load_sequence(_idle_frames, "res://assets/slime/walk/walk_%d.png", 12)
		_load_sequence(_attack_frames, "res://assets/slime/attack/attack_%d.png", 14)
	else:
		var original_sprite := enemy.get_node_or_null("Sprite2D") as Sprite2D
		if original_sprite and original_sprite.texture:
			_idle_frames.append(original_sprite.texture)
			_attack_frames.append(original_sprite.texture)
	_apply_first_frame()
	refresh_enemy_hp()


func _create_nodes(display_name: String) -> void:
	sprite = Sprite2D.new()
	sprite.scale = Vector2(0.9, 0.9)
	add_child(sprite)

	name_label = Label.new()
	name_label.text = display_name
	name_label.position = Vector2(-72, -126)
	name_label.size = Vector2(144, 26)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	add_child(name_label)

	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(-64, -98)
	hp_bar.size = Vector2(128, 12)
	hp_bar.show_percentage = false
	add_child(hp_bar)


func _load_sequence(target: Array[Texture2D], pattern: String, count: int) -> void:
	for index in range(1, count + 1):
		var texture := load(pattern % index) as Texture2D
		if texture:
			target.append(texture)


func _apply_first_frame() -> void:
	if not _idle_frames.is_empty():
		sprite.texture = _idle_frames[0]


func _process(delta: float) -> void:
	var frames := _attack_frames if _playing_attack else _idle_frames
	if frames.size() <= 1:
		return
	_frame_time += delta
	var interval := 0.04 if _playing_attack else 0.09
	if _frame_time >= interval:
		_frame_time -= interval
		_frame_index += 1
		if _playing_attack and _frame_index >= frames.size():
			_playing_attack = false
			_frame_index = 0
			if not _idle_frames.is_empty():
				sprite.texture = _idle_frames[0]
		else:
			_frame_index %= frames.size()
			sprite.texture = frames[_frame_index]


func play_attack() -> void:
	_playing_attack = true
	_frame_index = 0
	_frame_time = 0.0
	if not _attack_frames.is_empty():
		sprite.texture = _attack_frames[0]


func lunge_to(target: Vector2, duration := 0.28) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", target, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished


func return_home(duration := 0.32) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", home_position, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func hit_flash() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.35, 0.45), 0.08)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.16)
	await tween.finished


func refresh_enemy_hp() -> void:
	if not is_instance_valid(source_enemy):
		return
	hp_bar.max_value = source_enemy.max_hp
	hp_bar.value = source_enemy.hp


func fade_defeated() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_property(self, "position:y", position.y + 24.0, 0.35)
	await tween.finished
	visible = false
