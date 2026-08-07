extends CanvasLayer
class_name MapScreen

@onready var current_location_label: Label = %CurrentLocationLabel
@onready var close_button: Button = %CloseButton
@onready var map_placeholder: PanelContainer = $Margin/Panel/ContentMargin/VBox/MapPlaceholder
@onready var location_list: VBoxContainer = %LocationList
var _was_paused := false
var _closing := false
var _grid: GridContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	close_button.pressed.connect(close)
	_build_grid()
	_build_location_list()
	var panel := $Margin/Panel
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_QUAD)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _build_grid() -> void:
	for child in map_placeholder.get_children():
		child.queue_free()
	_grid = GridContainer.new()
	_grid.columns = MapState.WIDTH
	_grid.add_theme_constant_override("h_separation", 5)
	_grid.add_theme_constant_override("v_separation", 5)
	map_placeholder.add_child(_grid)
	var state := SaveManager.runtime_map_state
	if state.is_empty():
		SaveManager.runtime_map_state = MapState.create_new()
		state = SaveManager.runtime_map_state
	var current = SceneManager.get_current_scene()
	current_location_label.text = "当前位置：%s  ·  网格区域" % SceneRegistry.get_scene_info(current).get("display_name", current)
	for y in range(MapState.HEIGHT):
		for x in range(MapState.WIDTH):
			var id := MapState.zone_id(x, y)
			var zone: Dictionary = state.get("zones", {}).get(id, {})
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(78, 48)
			cell.text = _cell_text(x, y, zone)
			cell.tooltip_text = "区域 %s\n%s" % [id, zone.get("region", "未知")]
			# 世界地图允许直接前往任意格子；未发现格子只隐藏详情，进入时才生成内容。
			cell.disabled = false
			if id == "0,2":
				cell.text += "\n出生点"
			if not bool(zone.get("discovered", false)):
				cell.text = "？\n%d,%d" % [x, y]
			cell.pressed.connect(_travel_to_zone.bind(id))
			_grid.add_child(cell)

func _cell_text(x: int, y: int, zone: Dictionary) -> String:
	if not bool(zone.get("discovered", false)):
		return "？"
	var symbol := "●" if bool(zone.get("entered", false)) else "○"
	return "%s\n%d,%d" % [symbol, x, y]

func _build_location_list() -> void:
	for child in location_list.get_children():
		child.queue_free()
	var current_id = SceneManager.get_current_scene()
	for scene_id: String in SceneRegistry.get_all_scenes():
		var info := SceneRegistry.get_scene_info(scene_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 42.0)
		button.text = "%s  ·  %s" % [info.get("display_name", scene_id), info.get("description", "")]
		button.disabled = scene_id == current_id
		if not button.disabled:
			button.pressed.connect(_travel_to.bind(scene_id))
		location_list.add_child(button)

func _travel_to_zone(zone_id: String) -> void:
	# 区域尚未接入独立场景时仍进入 city1；区域 ID 已先写入共享状态。
	var zone: Dictionary = SaveManager.runtime_map_state.get("zones", {}).get(zone_id, {})
	zone["discovered"] = true
	zone["entered"] = true
	SaveManager.runtime_map_state["zones"][zone_id] = zone
	SaveManager.current_zone_id = zone_id
	_travel_to(String(zone.get("scene", "city1")))

func _travel_to(scene_id: String) -> void:
	if _closing:
		return
	_closing = true
	var tween := create_tween()
	tween.tween_property($Margin/Panel, "modulate:a", 0.0, 0.12)
	await tween.finished
	get_tree().paused = _was_paused
	if not SceneManager.change_to_scene(scene_id):
		_closing = false
		get_tree().paused = true
		return
	queue_free()

func close() -> void:
	if _closing:
		return
	_closing = true
	get_tree().paused = _was_paused
	queue_free()
