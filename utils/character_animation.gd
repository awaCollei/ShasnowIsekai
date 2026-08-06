extends Node
class_name CharacterAnimation

## 通用逐帧角色动画组件。玩家、NPC 与敌人均可复用。
signal animation_finished(anim_name: String)

var anim_frames: Dictionary = {}
var anim_intervals: Dictionary = {}
var anim_looping: Dictionary = {}
var current_anim: String = ""
var current_frame: int = 0
var anim_timer: float = 0.0
var _active := true
var _finished_emitted := false

@onready var sprite: Sprite2D = _find_sprite()


func _find_sprite() -> Sprite2D:
	var parent := get_parent()
	return parent.get_node_or_null("Sprite2D") as Sprite2D if parent else null


## 从角色数据库初始化（玩家/NPC 使用）。
func initialize(character_id: String) -> void:
	var char_data := CharacterDatabase.get_character(character_id)
	if char_data.is_empty():
		push_error("CharacterAnimation: 找不到角色数据: " + character_id)
		return
	var animations: Dictionary = char_data.get("animations", {})
	for anim_name in animations:
		var cfg: Dictionary = animations[anim_name]
		add_frame_animation(
			anim_name,
			cfg.get("path", ""),
			cfg.get("prefix", ""),
			cfg.get("frames", 0),
			cfg.get("interval", 0.04),
			cfg.get("looping", false)
		)


## 直接登记素材目录（敌人等无需写入角色数据库的对象使用）。
func add_frame_animation(anim_name: String, path: String, prefix: String, frame_count: int, interval: float = 0.04, looping: bool = true) -> void:
	var frames: Array[Texture2D] = []
	for i in range(1, frame_count + 1):
		var tex := load(path + prefix + str(i) + ".png") as Texture2D
		if tex:
			frames.append(tex)
	if frames.is_empty():
		push_warning("CharacterAnimation: 动画没有有效帧: " + anim_name)
		return
	anim_frames[anim_name] = frames
	anim_intervals[anim_name] = maxf(interval, 0.001)
	anim_looping[anim_name] = looping


func has_animation(anim_name: String) -> bool:
	return anim_frames.has(anim_name)


func play_animation(anim_name: String, restart: bool = true) -> void:
	if not anim_frames.has(anim_name):
		return
	if not restart and current_anim == anim_name:
		return
	current_anim = anim_name
	current_frame = 0
	anim_timer = 0.0
	_finished_emitted = false
	var frames: Array = anim_frames[anim_name]
	if not frames.is_empty() and sprite:
		sprite.texture = frames[0]


func set_flip_h(h: bool) -> void:
	if sprite:
		sprite.flip_h = h


func set_active(active: bool) -> void:
	_active = active


func _process(delta: float) -> void:
	if not _active or current_anim.is_empty() or not anim_frames.has(current_anim):
		return
	var frames: Array = anim_frames[current_anim]
	if frames.is_empty() or (_finished_emitted and not anim_looping.get(current_anim, true)):
		return
	anim_timer += delta
	var interval: float = anim_intervals.get(current_anim, 0.04)
	while anim_timer >= interval:
		anim_timer -= interval
		current_frame += 1
		if current_frame >= frames.size():
			if anim_looping.get(current_anim, true):
				current_frame = 0
			else:
				current_frame = frames.size() - 1
				_finished_emitted = true
				# 先提交末帧再发信号；回调可能立刻切换到另一动画。
				if sprite:
					sprite.texture = frames[current_frame]
				var completed_anim := current_anim
				animation_finished.emit(completed_anim)
				return
		if sprite:
			sprite.texture = frames[current_frame]
