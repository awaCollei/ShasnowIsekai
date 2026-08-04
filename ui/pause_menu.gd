extends CanvasLayer

# 键位动作与场景节点路径的映射
const BINDING_ACTIONS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right",
	"interact", "select_prev", "select_next", "menu",
	"attack", "chant", "dodge", "confirm"
]

# UI 引用（从场景获取）
@onready var blur_rect: ColorRect = $BlurRect
@onready var main_panel: VBoxContainer = $BlurRect/CenterContainer/MainPanel
@onready var key_bindings_panel: VBoxContainer = $BlurRect/CenterContainer/KeyBindingsPanel
@onready var save_panel: VBoxContainer = $BlurRect/CenterContainer/SavePanel
@onready var slots_container: VBoxContainer = $BlurRect/CenterContainer/SavePanel/SlotsContainer
@onready var waiting_label: Label = $BlurRect/CenterContainer/KeyBindingsPanel/WaitingLabel
@onready var always_run_check: CheckBox = $BlurRect/CenterContainer/KeyBindingsPanel/AlwaysRunRow/CheckBox

# 状态
var is_open: bool = false
var waiting_for_key: bool = false
var waiting_action: String = ""

# 键位绑定按钮引用（动态收集）
var binding_buttons: Dictionary = {}

# 对话框
var overwrite_confirm: ConfirmationDialog
var save_success_dialog: AcceptDialog

# 待保存的槽位（覆盖确认用）
var _pending_save_slot: int = -1


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
	$BlurRect/CenterContainer/MainPanel/SaveButton.pressed.connect(_on_save_pressed)
	$BlurRect/CenterContainer/MainPanel/KeybindButton.pressed.connect(_on_keybind_pressed)
	$BlurRect/CenterContainer/MainPanel/ReturnToMenuButton.pressed.connect(_on_return_to_menu_pressed)

	# 连接键位设置页面按钮
	$BlurRect/CenterContainer/KeyBindingsPanel/ButtonsRow/ResetButton.pressed.connect(_on_reset_pressed)
	$BlurRect/CenterContainer/KeyBindingsPanel/ButtonsRow/BackButton.pressed.connect(_on_back_pressed)
	always_run_check.toggled.connect(_on_always_run_toggled)

	# 连接保存面板按钮
	$BlurRect/CenterContainer/SavePanel/BackButton.pressed.connect(_on_save_back_pressed)

	# 创建覆盖确认对话框
	overwrite_confirm = ConfirmationDialog.new()
	overwrite_confirm.title = "覆盖存档"
	overwrite_confirm.dialog_text = "该槽位已有存档，是否覆盖？"
	overwrite_confirm.confirmed.connect(_on_overwrite_confirmed)
	add_child(overwrite_confirm)

	# 创建保存成功对话框
	save_success_dialog = AcceptDialog.new()
	save_success_dialog.title = "提示"
	save_success_dialog.dialog_text = "保存成功！"
	add_child(save_success_dialog)

	# 更新按键显示文本
	_update_key_display()


func _on_overwrite_confirmed() -> void:
	if _pending_save_slot < 1:
		return
	_do_save(_pending_save_slot)
	_pending_save_slot = -1


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			# 只在游戏中才响应 ESC 打开暂停菜单
			var save_manager = get_node_or_null("/root/SaveManager")
			if save_manager and save_manager.is_in_game:
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
	save_panel.visible = false

func _show_key_bindings() -> void:
	main_panel.visible = false
	key_bindings_panel.visible = true
	save_panel.visible = false
	_update_key_display()
	always_run_check.button_pressed = SettingsManager.always_run

func _show_save_panel() -> void:
	main_panel.visible = false
	key_bindings_panel.visible = false
	save_panel.visible = true
	_refresh_save_slots()

func _refresh_save_slots() -> void:
	# 清空旧条目
	for child in slots_container.get_children():
		child.queue_free()

	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager:
		return

	var infos = save_manager.get_all_save_infos()
	for info in infos:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 14)
		if info.has_data:
			label.text = "存档 %d - %s - %s" % [info.slot, info.scene_path.get_file(), info.timestamp]
		else:
			label.text = "存档 %d - （空）" % info.slot

		var save_btn := Button.new()
		save_btn.text = "保存"
		save_btn.custom_minimum_size = Vector2(70, 30)
		save_btn.add_theme_font_size_override("font_size", 14)
		save_btn.pressed.connect(_on_slot_save_pressed.bind(info.slot))

		row.add_child(label)
		row.add_child(save_btn)
		slots_container.add_child(row)

func _on_resume_pressed() -> void:
	close()

func _on_save_pressed() -> void:
	_show_save_panel()

func _on_keybind_pressed() -> void:
	_show_key_bindings()

func _on_return_to_menu_pressed() -> void:
	var save_manager = get_node_or_null("/root/SaveManager")
	if save_manager:
		save_manager.return_to_main_menu()

func _on_back_pressed() -> void:
	_show_main_menu()

func _on_save_back_pressed() -> void:
	_show_main_menu()

func _on_slot_save_pressed(slot: int) -> void:
	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager:
		return

	# 检查该槽位是否已有存档
	var info = save_manager.load_save_info(slot)
	if info.has_data:
		# 需要覆盖确认
		overwrite_confirm.dialog_text = "存档 %d（%s）已有数据，是否覆盖？" % [slot, info.timestamp]
		_pending_save_slot = slot
		overwrite_confirm.popup_centered()
	else:
		_do_save(slot)

func _do_save(slot: int) -> void:
	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager:
		return

	if save_manager.save_game(slot):
		save_success_dialog.popup_centered()
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
