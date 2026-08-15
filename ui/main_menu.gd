extends Control

@onready var main_panel: VBoxContainer = $MainPanel
@onready var save_slots_panel: VBoxContainer = $SaveSlotsPanel
@onready var slots_container: VBoxContainer = $SaveSlotsPanel/SlotsContainer
@onready var blur_rect: ColorRect = $BlurRect
@onready var save_slots_card: Panel = $SaveSlotsCard
@onready var new_game_button: Button = $MainPanel/NewGameButton
@onready var load_game_button: Button = $MainPanel/LoadGameButton
@onready var quit_button: Button = $MainPanel/QuitButton

var delete_confirm: ConfirmationDialog
var _pending_delete_slot: int = -1


func _ready() -> void:
	ButtonFeedback.setup_recursive(self)
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	$SaveSlotsPanel/BackButton.pressed.connect(_on_back_pressed)
	$SettingsButton.pressed.connect(_on_settings_pressed)

	# 创建统一风格的删除确认框
	delete_confirm = preload("res://ui/styled_confirm_dialog.gd").new()
	delete_confirm.title = "删除存档"
	delete_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(delete_confirm)

	AudioManager.play_bgm("res://assets/bgm.mp3")


func _on_new_game_pressed() -> void:
	var save_manager = get_node_or_null("/root/SaveManager")
	if save_manager:
		save_manager.start_new_game()


func _on_load_game_pressed() -> void:
	_show_save_slots()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_back_pressed() -> void:
	_show_main()


func _show_main() -> void:
	main_panel.visible = true
	save_slots_panel.visible = false
	save_slots_card.visible = false
	$SettingsButton.visible = true
	blur_rect.visible = false


func _show_save_slots() -> void:
	main_panel.visible = false
	save_slots_panel.visible = true
	save_slots_card.visible = true
	$SettingsButton.visible = false
	blur_rect.visible = true

	# 清空旧条目
	for child in slots_container.get_children():
		child.queue_free()

	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager:
		return

	var infos = save_manager.get_all_load_save_infos()
	for info in infos:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 16)
		var slot_name := "自动存档" if info.slot == SaveManager.AUTO_SAVE_SLOT else "存档 %d" % info.slot
		if info.has_data:
			label.text = "%s - %s - %s" % [slot_name, info.scene_path.get_file(), info.timestamp]
		else:
			label.text = "%s - （空）" % slot_name

		var load_btn := Button.new()
		load_btn.text = "读取"
		load_btn.custom_minimum_size = Vector2(80, 32)
		load_btn.add_theme_font_size_override("font_size", 14)
		load_btn.disabled = not info.has_data
		load_btn.pressed.connect(_on_slot_load_pressed.bind(info.slot))

		var delete_btn := Button.new()
		delete_btn.text = "删除"
		delete_btn.custom_minimum_size = Vector2(80, 32)
		delete_btn.add_theme_font_size_override("font_size", 14)
		delete_btn.disabled = not info.has_data
		delete_btn.pressed.connect(_on_slot_delete_pressed.bind(info.slot))

		row.add_child(label)
		row.add_child(load_btn)
		row.add_child(delete_btn)
		slots_container.add_child(row)


func _on_slot_load_pressed(slot: int) -> void:
	var save_manager = get_node_or_null("/root/SaveManager")
	if save_manager:
		save_manager.load_game(slot)


func _on_slot_delete_pressed(slot: int) -> void:
	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager:
		return

	var info = save_manager.load_save_info(slot)
	var slot_name := "自动存档" if slot == SaveManager.AUTO_SAVE_SLOT else "存档 %d" % slot
	delete_confirm.dialog_text = "确定要删除%s（%s）吗？此操作不可撤销。" % [slot_name, info.timestamp]
	_pending_delete_slot = slot
	delete_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	if _pending_delete_slot < 0:
		return
	var save_manager = get_node_or_null("/root/SaveManager")
	if save_manager:
		save_manager.delete_save(_pending_delete_slot)
	_pending_delete_slot = -1
	_show_save_slots()  # 刷新列表


func _on_settings_pressed() -> void:
	var sm = preload("res://ui/settings_menu.tscn").instantiate()
	get_tree().root.add_child(sm)
	sm.open()
