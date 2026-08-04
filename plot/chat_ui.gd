extends CanvasLayer

## 对话UI — RPG/Galgame风格对话框
## 由 PlotlineManager 控制，不应直接使用。

# ==========================
# 信号
# ==========================
signal text_fully_shown   # 打字机完成，等待玩家确认
signal advance_confirmed  # 玩家确认推进

# ==========================
# UI节点引用（通过场景树路径获取）
# ==========================
@onready var _root_control: Control = $RootControl
@onready var _illustration_area: Control = $RootControl/IllustrationArea
@onready var _illust_left: TextureRect = $RootControl/IllustrationArea/IllustLeft
@onready var _illust_center: TextureRect = $RootControl/IllustrationArea/IllustCenter
@onready var _illust_right: TextureRect = $RootControl/IllustrationArea/IllustRight
@onready var _dialog_panel: Panel = $RootControl/DialogPanel
@onready var _speaker_bg: Panel = $RootControl/DialogPanel/SpeakerBg
@onready var _speaker_label: Label = $RootControl/DialogPanel/SpeakerLabel
@onready var _text_label: Label = $RootControl/DialogPanel/TextLabel
@onready var _next_indicator: Label = $RootControl/DialogPanel/NextIndicator

# ==========================
# 状态
# ==========================
var _full_text: String = ""
var _displayed_count: int = 0
var _char_timer: float = 0.0
var _char_interval: float = 0.04
var _is_typing: bool = false
var _is_shown: bool = false
var _can_advance: bool = false

# 立绘路径映射
const ILLUSTRATION_PATHS: Dictionary = {
	"雪影": "res://assets/illustration/雪影.png",
	"薇芯": "res://assets/illustration/薇芯.png",
}

const COLOR_ACTIVE := Color.WHITE
const COLOR_GRAYED := Color(0.4, 0.4, 0.4, 1.0)


func _ready() -> void:
	# 确保节点引用都有效
	if not _root_control or not _dialog_panel:
		push_error("ChatUI: 无法找到必要的UI节点！")
		return
	
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# 设置 TextLabel 的初始大小（延迟一帧等布局完毕）
	call_deferred("_update_text_label_size")


func _update_text_label_size() -> void:
	if _dialog_panel:
		_text_label.size = Vector2(_dialog_panel.size.x - 64, _dialog_panel.size.y - 64)


# ==========================
# 公共接口
# ==========================

func show_ui() -> void:
	visible = true
	_is_shown = true
	_root_control.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root_control, "modulate:a", 1.0, 0.3)


func hide_ui() -> void:
	_is_shown = false
	_can_advance = false
	clear_all()
	var tw := create_tween()
	tw.tween_property(_root_control, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): visible = false)


func set_speaker(name_str: String) -> void:
	_speaker_label.text = name_str
	var has_speaker := not name_str.is_empty()
	_speaker_bg.visible = has_speaker
	_speaker_label.visible = has_speaker
	# # 根据名字长度调整背景宽度
	# if has_speaker:
	# 	var bg_width := name_str.length() * 20 + 40
	# 	_speaker_bg.size = Vector2(bg_width, 36)
	# 	_speaker_label.size = _speaker_bg.size


func set_text(text: String) -> void:
	_full_text = text
	_displayed_count = 0
	_text_label.text = ""
	_can_advance = false
	_next_indicator.visible = false
	_start_typewriter()


func set_illustrations(illust_names: Array, speaker: String) -> void:
	_illust_left.visible = false
	_illust_center.visible = false
	_illust_right.visible = false

	match illust_names.size():
		0:
			return
		1:
			_show_illust(_illust_center, illust_names[0], illust_names[0] == speaker)
		2:
			_show_illust(_illust_left, illust_names[0], illust_names[0] == speaker)
			_show_illust(_illust_right, illust_names[1], illust_names[1] == speaker)


func clear_all() -> void:
	_full_text = ""
	_displayed_count = 0
	_text_label.text = ""
	_speaker_label.text = ""
	_speaker_bg.visible = false
	_speaker_label.visible = false
	_is_typing = false
	_can_advance = false
	_next_indicator.visible = false
	_illust_left.visible = false
	_illust_center.visible = false
	_illust_right.visible = false


# ==========================
# 打字机效果
# ==========================

func _start_typewriter() -> void:
	_is_typing = true
	_char_timer = 0.0
	_displayed_count = 0
	_text_label.text = ""


func _process(delta: float) -> void:
	if not _is_shown or not _is_typing:
		return

	_char_timer += delta
	while _char_timer >= _char_interval and _displayed_count < _full_text.length():
		_char_timer -= _char_interval
		_displayed_count += 1
		_text_label.text = _full_text.substr(0, _displayed_count)

	if _displayed_count >= _full_text.length():
		_is_typing = false
		_can_advance = true
		_next_indicator.visible = true
		text_fully_shown.emit()


func skip_typewriter() -> void:
	if not _is_typing:
		return
	_displayed_count = _full_text.length()
	_text_label.text = _full_text
	_is_typing = false
	_can_advance = true
	_next_indicator.visible = true
	text_fully_shown.emit()

# ==========================
# 输入处理
# ==========================

func _input(event: InputEvent) -> void:
	if not _is_shown:
		return

	var is_confirm := false

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_confirm = true

	if event is InputEventKey and event.pressed and not event.echo:
		# 空格键兜底 + 通过 InputMap 匹配自定义 confirm 按键
		if event.keycode == KEY_SPACE:
			is_confirm = true
		elif InputMap.has_action("confirm") and _event_matches_action(event, "confirm"):
			is_confirm = true

	if not is_confirm:
		return

	get_viewport().set_input_as_handled()

	if _is_typing:
		skip_typewriter()
	elif _can_advance:
		_can_advance = false
		_next_indicator.visible = false
		advance_confirmed.emit()


func _event_matches_action(event: InputEventKey, action: String) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.keycode == event.keycode:
			return true
	return false


# ==========================
# 内部辅助
# ==========================

func _show_illust(tr: TextureRect, name_str: String, is_speaker: bool) -> void:
	if ILLUSTRATION_PATHS.has(name_str):
		tr.texture = load(ILLUSTRATION_PATHS[name_str])
	elif ResourceLoader.exists("res://assets/illustration/" + name_str + ".png"):
		tr.texture = load("res://assets/illustration/" + name_str + ".png")
	else:
		return
	tr.modulate = COLOR_ACTIVE if is_speaker else COLOR_GRAYED
	tr.visible = true
