extends Node
class_name PlayerAnimation

## 统一管理角色的所有动画（待机、行走、疾跑、攻击）
## 同一时间只允许一个动画播放，后来的请求打断当前动画

signal attack_finished

@onready var player: CharacterBody2D = get_parent()
@onready var sprite: Sprite2D = player.get_node("Sprite2D")
@onready var chant_effect: MagicChantEffect = player.get_node("MagicChantEffect")

# 动画帧
var walk_frames: Array[Texture2D] = []
var run_frames: Array[Texture2D] = []
var attack_frames: Array[Texture2D] = []
var chant_frames: Array[Texture2D] = []
var stand_texture: Texture2D

# 音效
var footstep_streams: Array[AudioStream] = []
var chant_player: AudioStreamPlayer

# 动画参数
var current_frame: int = 0
var anim_timer: float = 0.0
var footstep_timer: float = 0.0

const WALK_INTERVAL: float = 0.04
const RUN_INTERVAL: float = 0.04
const ATTACK_INTERVAL: float = 0.025
const CHANT_INTERVAL: float = 0.05

const WALK_FOOTSTEP_INTERVAL: float = 0.50
const RUN_FOOTSTEP_INTERVAL: float = 0.30

enum AnimState { IDLE, WALK, RUN, ATTACK, CHANT }
var state: AnimState = AnimState.IDLE

enum ChantPhase { FORWARD, LOOP, REVERSE }
var chant_phase: ChantPhase = ChantPhase.FORWARD


func _ready() -> void:
	_load_frames()
	_load_footstep_sounds()
	sprite.texture = stand_texture


func _load_frames() -> void:
	stand_texture = load("res://assets/shasnow/stand/stand_1.png")

	for i in range(1, 25):
		var tex = load("res://assets/shasnow/walk/walk_%d.png" % i)
		if tex:
			walk_frames.append(tex)

	for i in range(1, 17):
		var tex = load("res://assets/shasnow/run/run_%d.png" % i)
		if tex:
			run_frames.append(tex)

	for i in range(1, 33):
		var tex = load("res://assets/shasnow/basic_attack/basic_attack_%d.png" % i)
		if tex:
			attack_frames.append(tex)

	for i in range(1, 16):
		var tex = load("res://assets/shasnow/chanting/chanting_%d.png" % i)
		if tex:
			chant_frames.append(tex)

	if walk_frames.is_empty():
		walk_frames = [stand_texture]
	if run_frames.is_empty():
		run_frames = walk_frames.duplicate()


func _load_footstep_sounds() -> void:
	for i in range(1, 4):
		var snd = load("res://assets/sound_effects/footstep_%d.mp3" % i)
		if snd:
			footstep_streams.append(snd)


func _start_chant_audio() -> void:
	_stop_chant_audio()
	chant_player = AudioManager.play_looping_sfx("res://assets/sound_effects/chant.mp3")


func _stop_chant_audio() -> void:
	if chant_player:
		AudioManager.stop_looping_sfx(chant_player)
		chant_player = null


func _process(delta: float) -> void:
	match state:
		AnimState.IDLE:
			pass
		AnimState.WALK:
			_advance_loop(delta, walk_frames, WALK_INTERVAL)
		AnimState.RUN:
			_advance_loop(delta, run_frames, RUN_INTERVAL)
		AnimState.ATTACK:
			_advance_oneshot(delta, attack_frames, ATTACK_INTERVAL)
		AnimState.CHANT:
			_advance_chant(delta)


func _advance_loop(delta: float, frames: Array, interval: float) -> void:
	if frames.is_empty():
		return
	anim_timer += delta
	if anim_timer >= interval:
		anim_timer -= interval
		current_frame = (current_frame + 1) % frames.size()
		sprite.texture = frames[current_frame]

	# 脚步声
	var footstep_interval := RUN_FOOTSTEP_INTERVAL if state == AnimState.RUN else WALK_FOOTSTEP_INTERVAL
	footstep_timer += delta
	if footstep_timer >= footstep_interval:
		footstep_timer -= footstep_interval
		_play_random_footstep()


func _advance_oneshot(delta: float, frames: Array, interval: float) -> void:
	if frames.is_empty():
		state = AnimState.IDLE
		sprite.texture = stand_texture
		attack_finished.emit()
		return

	anim_timer += delta
	if anim_timer >= interval:
		anim_timer -= interval
		current_frame += 1
		if current_frame >= frames.size():
			state = AnimState.IDLE
			sprite.texture = stand_texture
			attack_finished.emit()
		else:
			sprite.texture = frames[current_frame]


func _advance_chant(delta: float) -> void:
	if chant_frames.is_empty():
		state = AnimState.IDLE
		sprite.texture = stand_texture
		_stop_chant_audio()
		chant_effect.stop()
		return

	match chant_phase:
		ChantPhase.FORWARD:
			anim_timer += delta
			if anim_timer >= CHANT_INTERVAL:
				anim_timer -= CHANT_INTERVAL
				current_frame += 1
				if current_frame >= chant_frames.size():
					chant_phase = ChantPhase.LOOP
					# 默认循环最后两帧，也兼容素材缺帧的情况。
					current_frame = maxi(0, chant_frames.size() - 2)
				sprite.texture = chant_frames[current_frame]

		ChantPhase.LOOP:
			anim_timer += delta
			if anim_timer >= CHANT_INTERVAL:
				anim_timer -= CHANT_INTERVAL
				current_frame += 1
				if current_frame >= chant_frames.size():
					current_frame = maxi(0, chant_frames.size() - 2)
				sprite.texture = chant_frames[current_frame]

		ChantPhase.REVERSE:
			anim_timer += delta
			if anim_timer >= CHANT_INTERVAL:
				anim_timer -= CHANT_INTERVAL
				current_frame -= 1
				if current_frame < 0:
					state = AnimState.IDLE
					current_frame = 0
					anim_timer = 0.0
					sprite.texture = stand_texture
					_stop_chant_audio()
					chant_effect.stop()
				else:
					sprite.texture = chant_frames[current_frame]


func request_idle() -> void:
	state = AnimState.IDLE
	current_frame = 0
	anim_timer = 0.0
	footstep_timer = 0.0
	sprite.texture = stand_texture
	_stop_chant_audio()
	chant_effect.stop()


func request_walk() -> void:
	if state != AnimState.WALK:
		if state == AnimState.CHANT:
			_stop_chant_audio()
			chant_effect.stop()
		state = AnimState.WALK
		current_frame = 0
		anim_timer = 0.0
		footstep_timer = 0.0
		if not walk_frames.is_empty():
			sprite.texture = walk_frames[0]


func request_run() -> void:
	if state != AnimState.RUN:
		if state == AnimState.CHANT:
			_stop_chant_audio()
			chant_effect.stop()
		state = AnimState.RUN
		current_frame = 0
		anim_timer = 0.0
		footstep_timer = 0.0
		if not run_frames.is_empty():
			sprite.texture = run_frames[0]


func request_attack() -> void:
	state = AnimState.ATTACK
	current_frame = 0
	anim_timer = 0.0
	footstep_timer = 0.0
	_stop_chant_audio()
	chant_effect.stop()
	if not attack_frames.is_empty():
		sprite.texture = attack_frames[0]


func request_magic_blade() -> void:
	# 魔法之刃复用普攻动作，但保留独立的蓄力释放特效。
	state = AnimState.ATTACK
	current_frame = 0
	anim_timer = 0.0
	footstep_timer = 0.0
	_stop_chant_audio()
	chant_effect.release_blade(sprite.flip_h)
	if not attack_frames.is_empty():
		sprite.texture = attack_frames[0]


func can_release_magic_blade() -> bool:
	return state == AnimState.CHANT and chant_effect.is_fully_charged()


func request_chant() -> void:
	if state != AnimState.CHANT:
		state = AnimState.CHANT
		current_frame = 0
		anim_timer = 0.0
		footstep_timer = 0.0
		chant_phase = ChantPhase.FORWARD
		if not chant_frames.is_empty():
			sprite.texture = chant_frames[0]
		_start_chant_audio()
		chant_effect.start(sprite.flip_h)
	elif chant_phase == ChantPhase.REVERSE:
		chant_phase = ChantPhase.FORWARD
		chant_effect.start(sprite.flip_h)


func request_chant_release() -> void:
	if state == AnimState.CHANT and chant_phase != ChantPhase.REVERSE:
		chant_phase = ChantPhase.REVERSE
		chant_effect.stop()


func is_attacking() -> bool:
	return state == AnimState.ATTACK


func is_chanting() -> bool:
	return state == AnimState.CHANT


func get_current_frame() -> int:
	return current_frame


func set_flip_h(h: bool) -> void:
	sprite.flip_h = h
	chant_effect.set_facing(h)


func _play_random_footstep() -> void:
	if footstep_streams.is_empty():
		return
	var idx := randi() % footstep_streams.size()
	AudioManager.play_game_sfx(footstep_streams[idx])
