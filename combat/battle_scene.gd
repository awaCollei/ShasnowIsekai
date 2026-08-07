extends CanvasLayer
class_name BattleScene

signal battle_resolved(victory: bool, defeated_enemies: Array[Enemy])

enum Phase { STARTING, PLAYER_CHOICE, TARGET_CHOICE, RESOLVING, FINISHED }

const ACTOR_VIEW := preload("res://combat/battle_actor_view.gd")
const ACTIONS := {
	"attack": {"name": "普通攻击", "mp": 0.0, "damage": 12, "restore": 18.0, "kind": "melee", "all": false},
	"magic_blade": {"name": "魔法之刃", "mp": 30.0, "damage": 44, "restore": 0.0, "kind": "melee", "all": false},
	"frost_lance": {"name": "霜晶枪", "mp": 18.0, "damage": 28, "restore": 0.0, "kind": "projectile", "all": false},
	"starfall": {"name": "星焰爆裂", "mp": 42.0, "damage": 32, "restore": 0.0, "kind": "burst", "all": true},
}

@onready var battlefield: TextureRect = $BattleRoot/Battlefield
@onready var actor_layer: Node2D = $BattleRoot/ActorLayer
@onready var action_panel: VBoxContainer = $BattleRoot/UILayer/ActionPanel
@onready var target_panel: VBoxContainer = $BattleRoot/UILayer/TargetPanel
@onready var message_label: Label = $BattleRoot/UILayer/MessagePanel/Message
@onready var wave_label: Label = $BattleRoot/UILayer/WaveLabel
@onready var hp_label: Label = $BattleRoot/UILayer/StatusPanel/VBox/HP
@onready var mp_label: Label = $BattleRoot/UILayer/StatusPanel/VBox/MP
@onready var hp_bar: ProgressBar = $BattleRoot/UILayer/StatusPanel/VBox/HPBar
@onready var mp_bar: ProgressBar = $BattleRoot/UILayer/StatusPanel/VBox/MPBar
@onready var transition: Control = $BattleRoot/Transition
@onready var transition_band: ColorRect = $BattleRoot/Transition/Band
@onready var transition_title: Label = $BattleRoot/Transition/Title

var player: Player
var player_view: BattleActorView
var all_enemies: Array[Enemy] = []
var waves: Array[Array] = []
var current_wave_index := -1
var enemy_views: Dictionary = {}
var defeated_enemies: Array[Enemy] = []
var phase := Phase.STARTING
var _pending_action := ""
var _player_first := true
var _first_strike_available := true


func _ready() -> void:
	_create_action_buttons()


func _configure_battlefield(scene_id: String) -> void:
	var battlefield_path := "res://assets/%s/battlefield.png" % scene_id
	var fallback_path := "res://assets/%s/background2.png" % scene_id
	var selected_path := ""
	if not scene_id.is_empty() and ResourceLoader.exists(battlefield_path):
		selected_path = battlefield_path
	elif not scene_id.is_empty() and ResourceLoader.exists(fallback_path):
		# 兼容尚未制作 battlefield.png 的地图；专属战斗图加入后会自动优先使用。
		selected_path = fallback_path
	if selected_path.is_empty():
		battlefield.texture = null
	else:
		battlefield.texture = load(selected_path) as Texture2D
	battlefield.visible = battlefield.texture != null


func setup(target_player: Player, enemies: Array[Enemy], player_first: bool, wave_size: int, scene_id: String) -> void:
	player = target_player
	_configure_battlefield(scene_id)
	all_enemies.assign(enemies)
	_player_first = player_first
	_build_waves(maxi(1, wave_size))
	_create_player_view()
	_refresh_status()
	player.hp_changed.connect(_on_player_hp_changed)
	player.mp_changed.connect(_on_player_mp_changed)
	await get_tree().process_frame
	await _play_entry_transition()
	await _start_next_wave()


func _play_entry_transition() -> void:
	transition.visible = true
	transition.modulate = Color.WHITE
	transition_band.scale = Vector2(0.0, 1.0)
	transition_title.text = "战斗开始" if _player_first else "遇袭"
	transition_title.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(transition_band, "scale:x", 1.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(transition_title, "modulate:a", 1.0, 0.16)
	tween.tween_interval(0.55)
	tween.tween_property(transition_title, "modulate:a", 0.0, 0.18)
	tween.tween_property(transition, "modulate:a", 0.0, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished
	transition.visible = false


func _build_waves(wave_size: int) -> void:
	var wave: Array[Enemy] = []
	for enemy in all_enemies:
		wave.append(enemy)
		if wave.size() >= wave_size:
			waves.append(wave)
			wave = []
	if not wave.is_empty():
		waves.append(wave)


func _create_player_view() -> void:
	player_view = ACTOR_VIEW.new() as BattleActorView
	actor_layer.add_child(player_view)
	player_view.setup_player()
	player_view.position = Vector2(400, 485)
	player_view.home_position = player_view.position
	player_view.sprite.flip_h = true
	player_view.hp_bar.visible = false


func _start_next_wave() -> void:
	current_wave_index += 1
	if current_wave_index >= waves.size():
		await _finish_battle(true)
		return
	enemy_views.clear()
	wave_label.text = "第 %d / %d 波" % [current_wave_index + 1, waves.size()]
	var wave: Array = waves[current_wave_index]
	for index in wave.size():
		var enemy := wave[index] as Enemy
		var view := ACTOR_VIEW.new() as BattleActorView
		actor_layer.add_child(view)
		view.setup_enemy(enemy)
		# 敌人由右上向左下错落排列。
		view.position = Vector2(1010 - index * 150, 190 + index * 105)
		view.home_position = view.position
		enemy_views[enemy] = view
	if current_wave_index == 0:
		message_label.text = ("我方先手：首个行动伤害提升 25%" if _player_first else "敌方先手：首个敌方行动伤害提升 25%")
	else:
		message_label.text = "新的敌人加入战斗"
	await get_tree().create_timer(0.8).timeout
	if _player_first:
		_begin_player_choice()
	else:
		await _run_enemy_turns()


func _create_action_buttons() -> void:
	for child in action_panel.get_children():
		child.queue_free()
	for action_id in ACTIONS:
		var data: Dictionary = ACTIONS[action_id]
		var button := Button.new()
		var suffix := "回复 %d MP" % int(data.restore) if float(data.restore) > 0.0 else "消耗 %d MP" % int(data.mp)
		button.text = "%s  ·  %s" % [data.name, suffix]
		button.custom_minimum_size = Vector2(230, 42)
		_apply_button_style(button, action_panel)
		button.pressed.connect(_on_action_pressed.bind(action_id))
		action_panel.add_child(button)


func _begin_player_choice() -> void:
	if phase == Phase.FINISHED:
		return
	phase = Phase.PLAYER_CHOICE
	action_panel.visible = true
	target_panel.visible = false
	message_label.text = "选择本回合行动"
	_refresh_action_availability()


func _refresh_action_availability() -> void:
	var action_ids := ACTIONS.keys()
	for index in action_panel.get_child_count():
		var button := action_panel.get_child(index) as Button
		var data: Dictionary = ACTIONS[action_ids[index]]
		button.disabled = player.get_visible_mp() + 0.001 < float(data.mp)


func _on_action_pressed(action_id: String) -> void:
	if phase != Phase.PLAYER_CHOICE:
		return
	var data: Dictionary = ACTIONS[action_id]
	_pending_action = action_id
	if bool(data.all):
		action_panel.visible = false
		await _resolve_player_action(null)
	else:
		_show_target_choice()


func _show_target_choice() -> void:
	phase = Phase.TARGET_CHOICE
	action_panel.visible = false
	target_panel.visible = true
	for child in target_panel.get_children():
		child.queue_free()
	message_label.text = "选择目标"
	for enemy in _living_wave_enemies():
		var button := Button.new()
		button.text = "%s  HP %d/%d" % [enemy.battle_name, enemy.hp, enemy.max_hp]
		button.custom_minimum_size = Vector2(220, 38)
		_apply_button_style(button, target_panel)
		button.pressed.connect(_on_target_pressed.bind(enemy))
		target_panel.add_child(button)
	var cancel := Button.new()
	cancel.text = "返回"
	_apply_button_style(cancel, target_panel)
	cancel.pressed.connect(_begin_player_choice)
	target_panel.add_child(cancel)


func _apply_button_style(button: Button, source: Control) -> void:
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		var style := source.get_theme_stylebox(style_name)
		if style:
			button.add_theme_stylebox_override(style_name, style.duplicate())
	button.add_theme_font_size_override("font_size", 17)


func _on_target_pressed(enemy: Enemy) -> void:
	if phase != Phase.TARGET_CHOICE or not is_instance_valid(enemy) or enemy.hp <= 0:
		return
	target_panel.visible = false
	await _resolve_player_action(enemy)


func _resolve_player_action(target: Enemy) -> void:
	phase = Phase.RESOLVING
	var data: Dictionary = ACTIONS[_pending_action]
	if not player.spend_mp(float(data.mp)):
		message_label.text = "MP 不足"
		await get_tree().create_timer(0.45).timeout
		_begin_player_choice()
		return
	if float(data.restore) > 0.0:
		player.gain_mp(float(data.restore))

	var multiplier := 1.25 if _player_first and _first_strike_available else 1.0
	_first_strike_available = false
	var damage := roundi(int(data.damage) * multiplier)
	message_label.text = "%s！" % String(data.name)
	match String(data.kind):
		"melee":
			await _play_player_melee(target)
		"projectile":
			await _play_projectile(target, Color(0.45, 0.85, 1.0), false)
		"burst":
			await _play_projectile(null, Color(1.0, 0.42, 0.68), true)

	var targets: Array[Enemy] = []
	if bool(data.all):
		targets = _living_wave_enemies()
	elif is_instance_valid(target):
		targets.append(target)
	for enemy in targets:
		if not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		enemy.apply_battle_damage(damage)
		var view := enemy_views.get(enemy) as BattleActorView
		if view:
			view.refresh_enemy_hp()
			await view.hit_flash()
		if enemy.hp <= 0:
			defeated_enemies.append(enemy)
			if view:
				await view.fade_defeated()

	if _living_wave_enemies().is_empty():
		message_label.text = "本波敌人已击破"
		await get_tree().create_timer(0.65).timeout
		await _start_next_wave()
		return
	await _run_enemy_turns()


func _play_player_melee(target: Enemy) -> void:
	var target_view := enemy_views.get(target) as BattleActorView
	if not target_view:
		return
	player_view.play_attack()
	await player_view.lunge_to(target_view.position + Vector2(-105, 55), 0.24)
	await get_tree().create_timer(0.26).timeout
	await player_view.return_home(0.30)


func _play_projectile(target: Enemy, color: Color, all_targets: bool) -> void:
	player_view.play_attack()
	var orb := Polygon2D.new()
	var points := PackedVector2Array()
	for index in 20:
		points.append(Vector2.from_angle(TAU * float(index) / 20.0) * 18.0)
	orb.polygon = points
	orb.color = color
	orb.position = player_view.position + Vector2(55, -45)
	actor_layer.add_child(orb)
	var destination := Vector2(870, 245)
	if not all_targets:
		var target_view := enemy_views.get(target) as BattleActorView
		if target_view:
			destination = target_view.position
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(orb, "position", destination, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(orb, "scale", Vector2(2.8, 2.8) if all_targets else Vector2(1.3, 1.3), 0.42)
	await tween.finished
	orb.queue_free()


func _run_enemy_turns() -> void:
	phase = Phase.RESOLVING
	action_panel.visible = false
	target_panel.visible = false
	for enemy in _living_wave_enemies():
		if player.hp <= 0.0:
			await _finish_battle(false)
			return
		var view := enemy_views.get(enemy) as BattleActorView
		if not view:
			continue
		var multiplier := 1.25 if not _player_first and _first_strike_available else 1.0
		_first_strike_available = false
		var damage := float(enemy.get_battle_damage()) * multiplier
		message_label.text = "%s 发起攻击" % enemy.battle_name
		view.play_attack()
		await view.lunge_to(player_view.position + Vector2(115, -45), 0.30)
		player.take_damage(damage)
		await player_view.hit_flash()
		await view.return_home(0.30)
		await get_tree().create_timer(0.18).timeout
	if player.hp <= 0.0:
		await _finish_battle(false)
	else:
		_begin_player_choice()


func _living_wave_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	if current_wave_index < 0 or current_wave_index >= waves.size():
		return result
	for value in waves[current_wave_index]:
		var enemy := value as Enemy
		if is_instance_valid(enemy) and enemy.hp > 0:
			result.append(enemy)
	return result


func _finish_battle(victory: bool) -> void:
	if phase == Phase.FINISHED:
		return
	phase = Phase.FINISHED
	action_panel.visible = false
	target_panel.visible = false
	message_label.text = "战斗胜利" if victory else "战斗失败"
	await get_tree().create_timer(1.0).timeout
	battle_resolved.emit(victory, defeated_enemies)
	queue_free()
	if not victory:
		SaveManager.return_to_main_menu()


func _refresh_status() -> void:
	if not player:
		return
	hp_label.text = "HP  %d / %d" % [roundi(player.hp), roundi(player.max_hp)]
	mp_label.text = "MP  %d / %d" % [roundi(player.get_visible_mp()), roundi(player.max_mp)]
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.hp
	mp_bar.max_value = player.max_mp
	mp_bar.value = player.get_visible_mp()


func _on_player_hp_changed(_hp: float, _max_hp: float) -> void:
	_refresh_status()


func _on_player_mp_changed(_mp: float, _max_mp: float, _reserved: float) -> void:
	_refresh_status()
	if phase == Phase.PLAYER_CHOICE:
		_refresh_action_availability()
