extends CanvasLayer

## 独立的设置面板，可从主菜单或暂停菜单打开
signal closed

const BINDING_ACTIONS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right",
	"interact", "inventory", "select_prev", "select_next", "menu",
	"attack", "chant", "dodge", "confirm"
]
const MOUSE_BINDINGS: Dictionary = {
	MOUSE_BUTTON_LEFT: -1,
	MOUSE_BUTTON_MIDDLE: -2,
	MOUSE_BUTTON_RIGHT: -3,
}
const CONFLICT_COLOR := Color(1.0, 0.32, 0.30, 1.0)

@onready var game_sfx_slider: HSlider = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/GameSfxRow/Slider
@onready var game_sfx_value_label: Label = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/GameSfxRow/ValueLabel
@onready var ui_sfx_slider: HSlider = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/UiSfxRow/Slider
@onready var ui_sfx_value_label: Label = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/UiSfxRow/ValueLabel
@onready var voice_slider: HSlider = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/VoiceRow/Slider
@onready var voice_value_label: Label = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/VoiceRow/ValueLabel
@onready var bgm_slider: HSlider = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/BgmRow/Slider
@onready var bgm_value_label: Label = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/BgmRow/ValueLabel
@onready var always_run_check: CheckButton = $BlurRect/CenterContainer/MainVBox/TabContainer/操作设置/AlwaysRunCheckBox

var is_open: bool = false
var waiting_for_key: bool = false
var waiting_action: String = ""
var binding_buttons: Dictionary = {}
var reset_confirm: ConfirmationDialog


func _ready() -> void:
	for action in BINDING_ACTIONS:
		var row_name := "Row_" + action
		var row := $BlurRect/CenterContainer/MainVBox/TabContainer/键位设置/ScrollContainer/BindingsList.get_node_or_null(row_name)
		if row:
			var key_btn := row.get_node("KeyButton") as Button
			if key_btn:
				binding_buttons[action] = key_btn
				key_btn.pressed.connect(_on_key_button_pressed.bind(action))
				key_btn.focus_mode = Control.FOCUS_ALL

	$BlurRect/CenterContainer/MainVBox/TabContainer/键位设置/ScrollContainer/BindingsList/ButtonsRow/ResetButton.pressed.connect(_on_reset_pressed)
	$BlurRect/CenterContainer/MainVBox/BackButton.pressed.connect(close)
	reset_confirm = preload("res://ui/styled_confirm_dialog.gd").new()
	reset_confirm.title = "恢复默认设置"
	reset_confirm.dialog_text = "确定要恢复所有音量、键位和游戏选项吗？"
	reset_confirm.theme = preload("res://theme/teal_ui.tres")
	reset_confirm.confirmed.connect(_on_reset_confirmed)
	add_child(reset_confirm)
	always_run_check.toggled.connect(_on_always_run_toggled)
	game_sfx_slider.value_changed.connect(_on_game_sfx_volume_changed)
	ui_sfx_slider.value_changed.connect(_on_ui_sfx_volume_changed)
	voice_slider.value_changed.connect(_on_voice_volume_changed)
	bgm_slider.value_changed.connect(_on_bgm_volume_changed)


func open() -> void:
	is_open = true
	_update_key_display()
	_update_volume_sliders()
	always_run_check.button_pressed = SettingsManager.always_run


func close() -> void:
	is_open = false
	waiting_for_key = false
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if not is_open:
		return

	# 普通状态下 ESC 关闭设置；捕获状态下 ESC 会作为普通按键保存。
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not waiting_for_key:
			close()
			get_viewport().set_input_as_handled()
			return
		if waiting_for_key:
			var new_key: int = event.keycode
			if new_key == KEY_NONE:
				new_key = event.physical_keycode
			_finish_key_capture(new_key)
			get_viewport().set_input_as_handled()
			return

	# 鼠标左键、中键、右键同样可以作为绑定输入。
	if waiting_for_key and event is InputEventMouseButton and event.pressed:
		if MOUSE_BINDINGS.has(event.button_index):
			_finish_key_capture(int(MOUSE_BINDINGS[event.button_index]))
			get_viewport().set_input_as_handled()


func _update_key_display() -> void:
	for action in BINDING_ACTIONS:
		if binding_buttons.has(action):
			binding_buttons[action].text = SettingsManager.get_key_name(action)
	_refresh_conflict_marks()


func _update_volume_sliders() -> void:
	game_sfx_slider.set_value_no_signal(SettingsManager.game_sfx_volume)
	ui_sfx_slider.set_value_no_signal(SettingsManager.ui_sfx_volume)
	voice_slider.set_value_no_signal(SettingsManager.voice_volume)
	bgm_slider.set_value_no_signal(SettingsManager.bgm_volume)
	_update_volume_label(game_sfx_value_label, SettingsManager.game_sfx_volume)
	_update_volume_label(ui_sfx_value_label, SettingsManager.ui_sfx_volume)
	_update_volume_label(voice_value_label, SettingsManager.voice_volume)
	_update_volume_label(bgm_value_label, SettingsManager.bgm_volume)


func _update_volume_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(value * 100)


func _on_key_button_pressed(action: String) -> void:
	if waiting_for_key:
		return
	waiting_for_key = true
	waiting_action = action
	for other_action in binding_buttons:
		binding_buttons[other_action].disabled = other_action != action
	binding_buttons[action].text = "按下按键"
	binding_buttons[action].grab_focus()


func _refresh_conflict_marks() -> void:
	var counts: Dictionary = {}
	for action in SettingsManager.key_bindings:
		var value := int(SettingsManager.key_bindings[action])
		counts[value] = int(counts.get(value, 0)) + 1
	for action in binding_buttons:
		var value := int(SettingsManager.key_bindings.get(action, 0))
		var button: Button = binding_buttons[action]
		if int(counts.get(value, 0)) > 1:
			button.add_theme_color_override("font_color", CONFLICT_COLOR)
			button.add_theme_color_override("font_hover_color", CONFLICT_COLOR)
		else:
			button.remove_theme_color_override("font_color")
			button.remove_theme_color_override("font_hover_color")


func _finish_key_capture(keycode: int) -> void:
	SettingsManager.set_key_binding(waiting_action, keycode)
	binding_buttons[waiting_action].text = SettingsManager.get_key_name(waiting_action)
	binding_buttons[waiting_action].release_focus()
	get_viewport().gui_release_focus()
	waiting_for_key = false
	for action in binding_buttons:
		binding_buttons[action].disabled = false
	_refresh_conflict_marks()


func _on_always_run_toggled(pressed: bool) -> void:
	SettingsManager.set_always_run(pressed)


func _on_reset_pressed() -> void:
	reset_confirm.popup_centered()


func _on_reset_confirmed() -> void:
	SettingsManager.reset_to_defaults()
	_update_key_display()
	_update_volume_sliders()
	always_run_check.button_pressed = false
	get_viewport().gui_release_focus()


func _on_game_sfx_volume_changed(value: float) -> void:
	SettingsManager.set_game_sfx_volume(value)
	_update_volume_label(game_sfx_value_label, value)


func _on_ui_sfx_volume_changed(value: float) -> void:
	SettingsManager.set_ui_sfx_volume(value)
	_update_volume_label(ui_sfx_value_label, value)


func _on_voice_volume_changed(value: float) -> void:
	SettingsManager.set_voice_volume(value)
	_update_volume_label(voice_value_label, value)


func _on_bgm_volume_changed(value: float) -> void:
	SettingsManager.set_bgm_volume(value)
	_update_volume_label(bgm_value_label, value)
