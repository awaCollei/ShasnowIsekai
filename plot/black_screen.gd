extends CanvasLayer

## 黑屏过渡UI — 由 PlotlineManager 控制，不应直接使用。
## 支持淡入/淡出黑屏，并在黑屏期间显示居中文本。

# ==========================
# 信号
# ==========================
signal advance_confirmed  # 玩家确认推进

# ==========================
# UI 节点引用
# ==========================
@onready var _color_rect: ColorRect = $ColorRect
@onready var _center_label: Label = $CenterLabel

# ==========================
# 状态
# ==========================
var _is_shown: bool = false
var _can_advance: bool = false


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


# ==========================
# 公共接口
# ==========================

## 淡入黑屏，await 后表示动画完成
func fade_in(duration: float = 0.5) -> void:
	visible = true
	_is_shown = true
	_can_advance = false
	var tw := create_tween()
	tw.tween_property(_color_rect, "modulate:a", 1.0, duration)
	await tw.finished


## 淡出黑屏，await 后表示动画完成
func fade_out(duration: float = 0.5) -> void:
	_is_shown = false
	_can_advance = false
	_center_label.visible = false
	_center_label.text = ""
	var tw := create_tween()
	tw.tween_property(_color_rect, "modulate:a", 0.0, duration)
	tw.tween_callback(func(): visible = false)
	await tw.finished


## 设置居中文本
func set_text(text: String) -> void:
	_center_label.text = text
	_center_label.visible = not text.is_empty()


## 清除文本
func clear_text() -> void:
	_center_label.text = ""
	_center_label.visible = false


## 启用/禁用等待确认
func set_can_advance(enabled: bool) -> void:
	_can_advance = enabled


# ==========================
# 输入处理
# ==========================

func _input(event: InputEvent) -> void:
	if not _is_shown or not _can_advance:
		return

	var is_confirm := false

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_confirm = true

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			is_confirm = true
		elif InputMap.has_action("confirm") and _event_matches_action(event, "confirm"):
			is_confirm = true

	if not is_confirm:
		return

	get_viewport().set_input_as_handled()
	_can_advance = false
	AudioManager.play_sfx("res://assets/sound_effects/next.mp3")
	advance_confirmed.emit()


func _event_matches_action(event: InputEventKey, action: String) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.keycode == event.keycode:
			return true
	return false
