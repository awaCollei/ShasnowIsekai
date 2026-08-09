extends CanvasLayer

## 对话UI — RPG/Galgame风格对话框
## 由 PlotlineManager 控制，不应直接使用。

# ==========================
# 信号
# ==========================
signal text_fully_shown      # 打字机完成，等待玩家确认
signal advance_confirmed     # 玩家确认推进

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
@onready var _text_label: RichTextLabel = $RootControl/DialogPanel/TextLabel
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
var _bbcode_tags: Array = []  # 预解析的BBCode标签 [{pos, tag, is_close}]

# 立绘路径映射
const ILLUSTRATION_PATHS: Dictionary = {
	"雪影": "res://assets/illustration/雪影.png",
	"薇芯": "res://assets/illustration/薇芯.png",
}

const COLOR_ACTIVE := Color.WHITE
const COLOR_GRAYED := Color(0.4, 0.4, 0.4, 1.0)

# ==========================
# 生命周期
# ==========================
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

	# 根据名字长度调整背景宽度（可选）
	# if has_speaker:
	#     var bg_width := name_str.length() * 20 + 40
	#     _speaker_bg.size = Vector2(bg_width, 36)
	#     _speaker_label.size = _speaker_bg.size


func set_text(text: String) -> void:
	_full_text = text
	_displayed_count = 0
	_text_label.text = ""
	_can_advance = false
	_next_indicator.visible = false

	_parse_bbcode_tags()
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


## 设置立绘方向
## direction: "left", "right", "face_to_face", "back_to_back"
func set_illustration_direction(direction: String) -> void:
	# 方向映射表：每个方向对应三个立绘的翻转状态 [左, 中, 右]
	# 注意：这里的状态是 "是否翻转"，true=翻折朝右，false=默认朝左
	var direction_map = {
		"left": [false, false, false],
		"right": [true, true, true],
		"face_to_face": [true, true, false],     # 左朝右，中朝右，右朝左
		"back_to_back": [false, false, true]     # 左朝左，中朝左，右朝右
	}

	var states = direction_map.get(direction, [false, false, false])
	_illust_left.flip_h = states[0]
	_illust_center.flip_h = states[1]
	_illust_right.flip_h = states[2]


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
	_bbcode_tags.clear()


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
		_skip_past_bbcode_tag()
		_text_label.text = _render_stream_text()

	if _displayed_count >= _full_text.length():
		_is_typing = false
		_can_advance = true
		_next_indicator.visible = true
		text_fully_shown.emit()


func _render_stream_text() -> String:
	"""返回当前已显示字符的文本，自动补全未闭合的BBCode标签"""
	var displayed := _full_text.substr(0, _displayed_count)
	var open_tags: Array[String] = []

	for tag_info in _bbcode_tags:
		if tag_info.pos >= _displayed_count:
			break

		if tag_info.is_close:
			for i in range(open_tags.size() - 1, -1, -1):
				if open_tags[i] == tag_info.tag:
					open_tags.remove_at(i)
					break
		else:
			open_tags.append(tag_info.tag)

	for tag in open_tags:
		displayed += "[/" + tag + "]"

	return displayed


func _parse_bbcode_tags() -> void:
	"""预解析全文中的BBCode标签位置"""
	_bbcode_tags.clear()

	var regex := RegEx.new()
	regex.compile("\\[(/?)(\\w+)([^\\]]*)\\]")

	for match_result in regex.search_all(_full_text):
		_bbcode_tags.append({
			"pos": match_result.get_start(),
			"length": match_result.get_string().length(),
			"tag": match_result.get_string(2),
			"is_close": match_result.get_string(1) == "/",
		})


func _skip_past_bbcode_tag() -> void:
	"""若当前光标处于BBCode标签内部，直接跳到标签末尾"""
	for tag_info in _bbcode_tags:
		var tag_start: int = tag_info.pos
		var tag_end: int = tag_start + tag_info.length

		if _displayed_count > tag_start and _displayed_count <= tag_end:
			_displayed_count = tag_end
			return


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
	AudioManager.play_ui_sfx("res://assets/sound_effects/next.mp3")

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
