extends Node
class_name CharacterAnimation

## 角色动画组件 — 根据角色数据加载帧序列，驱动 Sprite2D 切换。
## 支持 idle / walk / run 等基本动画，可被子类扩展（如 PlayerAnimation）。

signal animation_finished(anim_name: String)

var anim_frames: Dictionary = {}       # { "idle": [Texture2D, ...], ... }
var anim_intervals: Dictionary = {}    # { "idle": 0.0, ... }
var anim_looping: Dictionary = {}      # { "idle": false, ... }
var current_anim: String = ""
var current_frame: int = 0
var anim_timer: float = 0.0
var _active: bool = true

@onready var sprite: Sprite2D = _find_sprite()


func _find_sprite() -> Sprite2D:
	var parent := get_parent()
	if parent:
		return parent.get_node("Sprite2D") as Sprite2D
	return null


## 用角色数据初始化动画帧
func initialize(character_id: String) -> void:
	var char_data := CharacterDatabase.get_character(character_id)
	if char_data.is_empty():
		push_error("CharacterAnimation: 找不到角色数据: " + character_id)
		return

	var animations: Dictionary = char_data.get("animations", {})
	for anim_name in animations:
		var cfg: Dictionary = animations[anim_name]
		var path: String = cfg.get("path", "")
		var frames_count: int = cfg.get("frames", 0)
		var prefix: String = cfg.get("prefix", "")
		var interval: float = cfg.get("interval", 0.04)
		var looping: bool = cfg.get("looping", false)

		anim_intervals[anim_name] = interval
		anim_looping[anim_name] = looping

		var frames: Array[Texture2D] = []
		for i in range(1, frames_count + 1):
			var tex: Texture2D = load(path + prefix + str(i) + ".png")
			if tex:
				frames.append(tex)

		if not frames.is_empty():
			anim_frames[anim_name] = frames


## 查询是否有某个动画
func has_animation(anim_name: String) -> bool:
	return anim_frames.has(anim_name)


## 播放指定动画（中断当前）
func play_animation(anim_name: String) -> void:
	if not anim_frames.has(anim_name):
		return
	current_anim = anim_name
	current_frame = 0
	anim_timer = 0.0
	var frames: Array = anim_frames[anim_name]
	if not frames.is_empty() and sprite:
		sprite.texture = frames[0]


## 设置精灵水平翻转
func set_flip_h(h: bool) -> void:
	if sprite:
		sprite.flip_h = h


## 暂停 / 恢复动画更新
func set_active(active: bool) -> void:
	_active = active


func _process(delta: float) -> void:
	if not _active:
		return
	if current_anim.is_empty() or not anim_frames.has(current_anim):
		return

	var frames: Array = anim_frames[current_anim]
	if frames.is_empty():
		return

	anim_timer += delta
	var interval: float = anim_intervals.get(current_anim, 0.04)
	if anim_timer >= interval:
		anim_timer -= interval
		current_frame += 1
		if current_frame >= frames.size():
			if anim_looping.get(current_anim, true):
				current_frame = 0
			else:
				current_frame = frames.size() - 1
				animation_finished.emit(current_anim)
		if sprite:
			sprite.texture = frames[current_frame]