extends CanvasLayer

# 键位动作与场景节点路径的映射
const BINDING_ACTIONS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right",
	"interact", "select_prev", "select_next", "menu",
	"attack", "chant", "dodge"
]

# UI 引用（从场景获取）
@onready var blur_rect: ColorRect = $BlurRect
@onready var main_panel: VBoxContainer = $BlurRect/CenterContainer/MainPanel
@onready var key_bindings_panel: VBoxContainer = $BlurRect/CenterContainer/KeyBindingsPanel
@onready var waiting_label: Label = $BlurRect/CenterContainer/KeyBindingsPanel/WaitingLabel
@onready var always_run_check: CheckBox = $BlurRect/CenterContainer/KeyBindingsPanel/AlwaysRunRow/CheckBox

# 状态
var is_open: bool = false
var waiting_for_key: bool = false
var waiting_action: String = ""

# 键位绑定按钮引用（动态收集）
var binding_buttons: Dictionary = {}

func _ready() -> void:
	visible = false

	# 收集所有键位绑定按钮
	for action in BINDING_ACTIONS:
		var row_name := "Row_" + action
		var row := $BlurRect/CenterContainer/KeyBindingsPanel/ScrollContainer/BindingsList.get_node_or_null(row_name)
		if row:
			var key_btn := row.get_node("KeyButton") as Button
			if key_btn:
				binding_buttons[action] = key_btn
				key_btn.pressed.connect(_on_key_button_pressed.bind(action))

	# 连接主菜单按钮
	$BlurRect/CenterContainer/MainPanel/ResumeButton.pressed.connect(_on_resume_pressed)
	$BlurRect/CenterContainer/MainPanel/KeybindButton.pressed.connect(_on_keybind_pressed)

	# 连接键位设置页面按钮
	$BlurRect/CenterContainer/KeyBindingsPanel/ButtonsRow/ResetButton.pressed.connect(_on_reset_pressed)
	$BlurRect/CenterContainer/KeyBindingsPanel/ButtonsRow/BackButton.pressed.connect(_on_back_pressed)
	always_run_check.toggled.connect(_on_always_run_toggled)

	# 更新按键显示文本
	_update_key_display()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			toggle()
			get_viewport().set_input_as_handled()
			return

	# 等待按键绑定时，捕获键盘输入
	if is_open and waiting_for_key and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			waiting_for_key = false
			waiting_label.visible = false
			get_viewport().set_input_as_handled()
			return

		SettingsManager.set_key_binding(waiting_action, event.keycode)
		binding_buttons[waiting_action].text = OS.get_keycode_string(event.keycode)
		waiting_for_key = false
		waiting_label.visible = false
		get_viewport().set_input_as_handled()

func _update_key_display() -> void:
	for action in BINDING_ACTIONS:
		if binding_buttons.has(action):
			binding_buttons[action].text = SettingsManager.get_key_name(action)

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	is_open = true
	visible = true
	get_tree().paused = true
	_show_main_menu()

func close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false
	waiting_for_key = false
	waiting_label.visible = false

func _show_main_menu() -> void:
	main_panel.visible = true
	key_bindings_panel.visible = false

func _show_key_bindings() -> void:
	main_panel.visible = false
	key_bindings_panel.visible = true
	_update_key_display()
	always_run_check.button_pressed = SettingsManager.always_run

func _on_resume_pressed() -> void:
	close()

func _on_keybind_pressed() -> void:
	_show_key_bindings()

func _on_back_pressed() -> void:
	_show_main_menu()

func _on_key_button_pressed(action: String) -> void:
	waiting_for_key = true
	waiting_action = action
	waiting_label.visible = true

func _on_always_run_toggled(pressed: bool) -> void:
	SettingsManager.set_always_run(pressed)

func _on_reset_pressed() -> void:
	SettingsManager.reset_to_defaults()
	_update_key_display()
	always_run_check.button_pressed = false
