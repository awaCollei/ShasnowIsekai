extends CanvasLayer

## 独立的设置面板，可从主菜单或暂停菜单打开
## 用法：var sm = preload("res://ui/settings_menu.tscn").instantiate()
##       get_tree().root.add_child(sm)
##       sm.open()

signal closed

const BINDING_ACTIONS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right",
	"interact", "select_prev", "select_next", "menu",
	"attack", "chant", "dodge", "confirm"
]

@onready var game_sfx_slider: HSlider = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/GameSfxRow/Slider
@onready var game_sfx_value_label: Label = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/GameSfxRow/ValueLabel
@onready var ui_sfx_slider: HSlider = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/UiSfxRow/Slider
@onready var ui_sfx_value_label: Label = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/UiSfxRow/ValueLabel
@onready var bgm_slider: HSlider = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/BgmRow/Slider
@onready var bgm_value_label: Label = $BlurRect/CenterContainer/MainVBox/TabContainer/音量设置/BgmRow/ValueLabel
@onready var always_run_check: CheckBox = $BlurRect/CenterContainer/MainVBox/TabContainer/键位设置/AlwaysRunRow/CheckBox
@onready var waiting_label: Label = $BlurRect/CenterContainer/MainVBox/WaitingLabel

var is_open: bool = false
var waiting_for_key: bool = false
var waiting_action: String = ""
var binding_buttons: Dictionary = {}


func _ready() -> void:
	# 收集键位绑定按钮
	for action in BINDING_ACTIONS:
		var row_name := "Row_" + action
		var row := $BlurRect/CenterContainer/MainVBox/TabContainer/键位设置/ScrollContainer/BindingsList.get_node_or_null(row_name)
		if row:
			var key_btn := row.get_node("KeyButton") as Button
			if key_btn:
				binding_buttons[action] = key_btn
				key_btn.pressed.connect(_on_key_button_pressed.bind(action))

	# 连接按钮
	$BlurRect/CenterContainer/MainVBox/TabContainer/键位设置/ButtonsRow/ResetButton.pressed.connect(_on_reset_pressed)
	$BlurRect/CenterContainer/MainVBox/BackButton.pressed.connect(close)
	always_run_check.toggled.connect(_on_always_run_toggled)

	# 连接音量滑块
	game_sfx_slider.value_changed.connect(_on_game_sfx_volume_changed)
	ui_sfx_slider.value_changed.connect(_on_ui_sfx_volume_changed)
	bgm_slider.value_changed.connect(_on_bgm_volume_changed)


func open() -> void:
	is_open = true
	_update_key_display()
	_update_volume_sliders()
	always_run_check.button_pressed = SettingsManager.always_run


func close() -> void:
	is_open = false
	waiting_for_key = false
	waiting_label.visible = false
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_open:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if waiting_for_key:
				waiting_for_key = false
				waiting_label.visible = false
				get_viewport().set_input_as_handled()
				return
			close()
			get_viewport().set_input_as_handled()
			return

		if waiting_for_key:
			SettingsManager.set_key_binding(waiting_action, event.keycode)
			binding_buttons[waiting_action].text = OS.get_keycode_string(event.keycode)
			waiting_for_key = false
			waiting_label.visible = false
			get_viewport().set_input_as_handled()


func _update_key_display() -> void:
	for action in BINDING_ACTIONS:
		if binding_buttons.has(action):
			binding_buttons[action].text = SettingsManager.get_key_name(action)


func _update_volume_sliders() -> void:
	game_sfx_slider.set_value_no_signal(SettingsManager.game_sfx_volume)
	ui_sfx_slider.set_value_no_signal(SettingsManager.ui_sfx_volume)
	bgm_slider.set_value_no_signal(SettingsManager.bgm_volume)
	_update_volume_label(game_sfx_value_label, SettingsManager.game_sfx_volume)
	_update_volume_label(ui_sfx_value_label, SettingsManager.ui_sfx_volume)
	_update_volume_label(bgm_value_label, SettingsManager.bgm_volume)


func _update_volume_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(value * 100)


func _on_key_button_pressed(action: String) -> void:
	waiting_for_key = true
	waiting_action = action
	waiting_label.visible = true


func _on_always_run_toggled(pressed: bool) -> void:
	SettingsManager.set_always_run(pressed)


func _on_reset_pressed() -> void:
	SettingsManager.reset_to_defaults()
	_update_key_display()
	_update_volume_sliders()
	always_run_check.button_pressed = false


func _on_game_sfx_volume_changed(value: float) -> void:
	SettingsManager.set_game_sfx_volume(value)
	_update_volume_label(game_sfx_value_label, value)


func _on_ui_sfx_volume_changed(value: float) -> void:
	SettingsManager.set_ui_sfx_volume(value)
	_update_volume_label(ui_sfx_value_label, value)


func _on_bgm_volume_changed(value: float) -> void:
	SettingsManager.set_bgm_volume(value)
	_update_volume_label(bgm_value_label, value)
