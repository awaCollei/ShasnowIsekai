extends CanvasLayer

# UI 引用
@onready var blur_rect: ColorRect = $BlurRect
@onready var main_panel: VBoxContainer = $BlurRect/CenterContainer/MainPanel
@onready var save_panel: VBoxContainer = $BlurRect/CenterContainer/SavePanel
@onready var slots_container: VBoxContainer = $BlurRect/CenterContainer/SavePanel/SlotsContainer

# 状态
var is_open: bool = false

# 对话框
var overwrite_confirm: ConfirmationDialog

# 待保存的槽位（覆盖确认用）
var _pending_save_slot: int = -1

# 设置菜单实例
var _settings_menu = null


func _ready() -> void:
	visible = false
	ButtonFeedback.setup_recursive(self)

	# 连接主菜单按钮
	$BlurRect/CenterContainer/MainPanel/ResumeButton.pressed.connect(_on_resume_pressed)
	$BlurRect/CenterContainer/MainPanel/SaveButton.pressed.connect(_on_save_pressed)
	$BlurRect/CenterContainer/MainPanel/SettingsButton.pressed.connect(_on_settings_pressed)
	$BlurRect/CenterContainer/MainPanel/ReturnToMenuButton.pressed.connect(_on_return_to_menu_pressed)

	# 连接保存面板按钮
	$BlurRect/CenterContainer/SavePanel/BackButton.pressed.connect(_on_save_back_pressed)

	# 创建统一风格的覆盖确认框
	overwrite_confirm = preload("res://ui/styled_confirm_dialog.gd").new()
	overwrite_confirm.title = "覆盖存档"
	overwrite_confirm.dialog_text = "该槽位已有存档，是否覆盖？"
	overwrite_confirm.confirmed.connect(_on_overwrite_confirmed)
	add_child(overwrite_confirm)


func _on_overwrite_confirmed() -> void:
	if _pending_save_slot < 1:
		return
	_do_save(_pending_save_slot)
	_pending_save_slot = -1


func _unhandled_key_input(event: InputEvent) -> void:
	# 设置菜单或背包打开时不处理 ESC，避免两个暂停层互相覆盖状态。
	var inventory_ui := get_node_or_null("/root/InventoryUI")
	if _settings_menu or (inventory_ui and inventory_ui.visible):
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			var save_manager = get_node_or_null("/root/SaveManager")
			if save_manager and save_manager.is_in_game:
				toggle()
				get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	visible = true
	get_tree().paused = true
	AudioManager.pause_bgm()
	_show_main_menu()


func close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false
	AudioManager.resume_bgm()


func _show_main_menu() -> void:
	main_panel.visible = true
	save_panel.visible = false


func _show_save_panel() -> void:
	main_panel.visible = false
	save_panel.visible = true
	_refresh_save_slots()


func _refresh_save_slots() -> void:
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


func _on_settings_pressed() -> void:
	_settings_menu = preload("res://ui/settings_menu.tscn").instantiate()
	get_tree().root.add_child(_settings_menu)
	_settings_menu.closed.connect(_on_settings_closed)
	_settings_menu.open()


func _on_settings_closed() -> void:
	_settings_menu = null


func _on_return_to_menu_pressed() -> void:
	var save_manager = get_node_or_null("/root/SaveManager")
	if save_manager:
		save_manager.return_to_main_menu()


func _on_save_back_pressed() -> void:
	_show_main_menu()


func _on_slot_save_pressed(slot: int) -> void:
	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager:
		return

	var info = save_manager.load_save_info(slot)
	if info.has_data:
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
		_show_main_menu()
