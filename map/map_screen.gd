extends CanvasLayer
class_name MapScreen

@onready var panel: PanelContainer = %Panel
@onready var grid_host: Control = %GridHost
@onready var scene_title: Label = %SceneTitle
@onready var scene_desc: Label = %SceneDescription
@onready var detail_title: Label = %DetailTitle
@onready var detail_desc: Label = %DetailDescription
@onready var detail_meta: Label = %DetailMeta
@onready var travel_button: Button = %TravelButton
@onready var left_button: Button = %LeftButton
@onready var right_button: Button = %RightButton
var _was_paused := false
var _closing := false
var _selected_zone := ""
var _scene_ids: Array[String] = []
var _scene_index := 0
var _grid: GridContainer
var _position_marker: Label
const MARKER_X_CORRECTION := -6.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused; get_tree().paused = true
	_scene_ids = SceneRegistry.get_scene_ids()
	var current = SceneManager.get_current_scene()
	_scene_index = maxi(0, _scene_ids.find(current))
	%BackdropOverlay.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	%CloseButton.pressed.connect(close); left_button.pressed.connect(func(): _change_scene(-1)); right_button.pressed.connect(func(): _change_scene(1))
	travel_button.pressed.connect(_travel_selected)
	_style_button(%CloseButton); _style_button(left_button); _style_button(right_button); _style_button(travel_button)
	_refresh_scene()
	panel.modulate.a = 0.0; panel.scale = Vector2(0.97, 0.97)
	var intro := create_tween().set_parallel(true)
	intro.tween_property(panel, "modulate:a", 1.0, 0.2); intro.tween_property(panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_QUAD)

func _input(event: InputEvent) -> void:
	# 地图暂停期间仍保持最高优先级，避免 ESC 继续传给 PauseMenu。
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _refresh_scene() -> void:
	var scene_id := _scene_ids[_scene_index]
	var info := SceneRegistry.get_scene_info(scene_id)
	scene_title.text = info.get("display_name", scene_id)
	scene_desc.text = info.get("description", "")
	left_button.disabled = _scene_index == 0; right_button.disabled = _scene_index == _scene_ids.size() - 1
	var backdrop := $DimBackground as TextureRect
	backdrop.texture = load("res://assets/%s/background2.png" % scene_id) as Texture2D
	_set_map_background(scene_id); _build_grid(scene_id); _clear_detail()
	call_deferred("_place_position_marker", scene_id)

func _change_scene(delta: int) -> void:
	if _scene_ids.is_empty(): return
	_scene_index = clampi(_scene_index + delta, 0, _scene_ids.size() - 1)
	var out := create_tween(); out.tween_property(%MapBody, "modulate:a", 0.0, 0.1); await out.finished
	_refresh_scene()
	%MapBody.modulate.a = 0.0; create_tween().tween_property(%MapBody, "modulate:a", 1.0, 0.18)

func _style_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new(); style.corner_radius_top_left = 8; style.corner_radius_top_right = 8; style.corner_radius_bottom_left = 8; style.corner_radius_bottom_right = 8; style.set_border_width_all(1); style.border_color = Color("#397b9e") if state != "hover" else Color("#9be0ff"); style.bg_color = Color("#173b52", 0.9) if state != "disabled" else Color("#152330", 0.65); button.add_theme_stylebox_override(state, style)

func _set_map_background(scene_id: String) -> void:
	var frame := %GridFrame
	for child in frame.get_children():
		if child.name == "SceneMapBackdrop": child.queue_free()
	var texture := load("res://assets/%s/background2.png" % scene_id) as Texture2D
	if not texture: return
	var backdrop := TextureRect.new(); backdrop.name = "SceneMapBackdrop"; backdrop.texture = texture; backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; backdrop.modulate = Color(0.32, 0.52, 0.64, 0.24); backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE; backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); frame.add_child(backdrop); frame.move_child(backdrop, 0)

func _build_grid(scene_id: String) -> void:
	for child in grid_host.get_children(): child.queue_free()
	_grid = GridContainer.new()
	var is_base := scene_id == "base"
	var columns := 3 if is_base else 6
	var rows := 3 if is_base else 6
	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", 0); _grid.add_theme_constant_override("v_separation", 0)
	grid_host.add_child(_grid)
	var state := MapState.ensure(SaveManager.runtime_map_state)
	SaveManager.runtime_map_state = state
	var n := 0
	if is_base:
		# 在 3x3 网格中居中放置基地格子（位置 4）
		for i in range(9):
			if i == 4:
				_add_map_cell(state.get("base", {}), MapState.BASE_ID, 1, 1, n)
			else:
				var ph := Control.new(); ph.custom_minimum_size = Vector2(100, 82); _grid.add_child(ph)
	else:
		for y in range(MapState.HEIGHT):
			for x in range(MapState.WIDTH):
				var id := MapState.zone_id(x, y)
				var zone: Dictionary = state.zones.get(id, {})
				_add_map_cell(zone, id, n % columns, int(n / columns), n); n += 1
func _add_map_cell(zone: Dictionary, id: String, x: int, y: int, order: int) -> void:
	var cell := Button.new(); cell.custom_minimum_size = Vector2(100, 82); cell.focus_mode = Control.FOCUS_ALL; cell.set_meta("zone_id", id)
	cell.text = _cell_text(zone, id); cell.add_theme_stylebox_override("normal", _cell_style(zone, false)); cell.add_theme_stylebox_override("hover", _cell_style(zone, true)); cell.add_theme_stylebox_override("disabled", _cell_style(zone, false)); cell.pressed.connect(_select_zone.bind(id)); _grid.add_child(cell)
	cell.modulate.a = 0.0; var delay = 0.025 * abs(x - _grid.columns / 2) + 0.025 * abs(y - 2) + order * 0.006; var t := create_tween(); t.tween_interval(delay); t.tween_property(cell, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC)

func _cell_text(zone: Dictionary, id: String) -> String:
	if zone.is_empty(): return "未知区域"
	var marker := "◆" if zone.get("entered", false) else "◇"
	return "%s\n%s" % [marker, MapState.type_name(zone.get("region_type", "office"))]

func _cell_style(zone: Dictionary, hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = Color("#18334a") if zone.get("discovered", false) else Color("#101e2b"); s.border_color = Color("#8fd7ff") if hover else Color("#356985"); s.set_border_width_all(2 if hover else 1); s.corner_radius_top_left=0; s.corner_radius_top_right=0; s.corner_radius_bottom_left=0; s.corner_radius_bottom_right=0; s.content_margin_left=5; s.content_margin_right=5
	return s

func _select_zone(id: String) -> void:
	if _selected_zone == id: _clear_detail(); return
	_selected_zone = id; var zone: Dictionary = MapState.get_zone(SaveManager.runtime_map_state, id); var type := MapState.type_name(zone.get("region_type", "office")); detail_title.text = type; detail_desc.text = _description_for(type); detail_meta.text = "坐标 %s   ·   去过 %d 次" % [id, int(zone.get("visit_count", 0))]; travel_button.disabled = false

func _clear_detail() -> void:
	_selected_zone = ""; detail_title.text = "选择一个区域"; detail_desc.text = "点击地图上的格子查看详情。再次点击已选格子可取消选择。"; detail_meta.text = ""; travel_button.disabled = true

func _description_for(type: String) -> String:
	return {"医院":"药品与医疗物资，也许还有幸存者。", "写字楼":"高层建筑，可能藏有办公用品和补给。", "住宅区":"普通居民区，房间里可能留下生活物资。", "市场":"曾经热闹的街区，物资种类丰富但风险未知。", "商店":"营地里的补给商店。", "营地":"房车营地，安全而熟悉。", "车库":"可以修理和改造装备的地方。"}.get(type, "一片尚待探索的区域。")

func _travel_selected() -> void:
	if _selected_zone.is_empty(): return
	var zone: Dictionary = MapState.get_zone(SaveManager.runtime_map_state, _selected_zone); zone["discovered"] = true; zone["entered"] = true; zone["visit_count"] = int(zone.get("visit_count", 0)) + 1; MapState.set_zone(SaveManager.runtime_map_state, _selected_zone, zone); SaveManager.current_zone_id = _selected_zone
	var target_scene := String(zone.get("scene", "city1"))
	await _animate_marker_to(_selected_zone, target_scene)
	_travel_to(target_scene)

func _place_position_marker(scene_id: String) -> void:
	if not is_instance_valid(_grid): return
	if is_instance_valid(_position_marker): _position_marker.queue_free()
	# 不在当前场景时不显示当前位置，避免把位置误认为属于另一张地图。
	if scene_id != SceneManager.get_current_scene(): return
	_position_marker = Label.new(); _position_marker.text = "▼"; _position_marker.add_theme_color_override("font_color", Color("#ff4f55")); _position_marker.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9)); _position_marker.add_theme_constant_override("shadow_offset_x", 2); _position_marker.add_theme_constant_override("shadow_offset_y", 2); _position_marker.add_theme_font_size_override("font_size", 30); _position_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE; grid_host.add_child(_position_marker)
	var current_id := String(SaveManager.current_zone_id)
	var cells := _grid.get_children(); var marker_index := -1
	if scene_id == "base": marker_index = 4 if current_id == MapState.BASE_ID else -1
	else:
		for i in range(cells.size()):
			if String(cells[i].get_meta("zone_id", "")) == current_id: marker_index = i; break
	if marker_index >= 0 and marker_index < cells.size():
		var cell := cells[marker_index] as Control; _position_marker.position = cell.position + Vector2(cell.size.x * 0.5 + MARKER_X_CORRECTION - 12, -18)

func _animate_marker_to(zone_id: String, target_scene: String) -> void:
	if target_scene != _scene_ids[_scene_index]: return
	if not is_instance_valid(_position_marker):
		# 当前查看的是目的地地图：标记从与当前场景相邻的边缘进入。
		_position_marker = Label.new(); _position_marker.text = "▼"; _position_marker.add_theme_color_override("font_color", Color("#ff4f55")); _position_marker.add_theme_font_size_override("font_size", 30); _position_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE; grid_host.add_child(_position_marker)
		var current_scene_index := _scene_ids.find(SceneManager.get_current_scene())
		var entering_from_left := _scene_index > current_scene_index
		_position_marker.position = Vector2(-35 if entering_from_left else grid_host.size.x + 10, grid_host.size.y * 0.5)
	var cells := _grid.get_children(); var target_index := -1
	for i in range(cells.size()):
		if String(cells[i].get_meta("zone_id", "")) == zone_id: target_index = i; break
	if target_index >= 0:
		var cell := cells[target_index] as Control; var destination := cell.position + Vector2(cell.size.x * 0.5 + MARKER_X_CORRECTION - 12, -18); var destination_tween := create_tween(); destination_tween.tween_property(_position_marker, "position", destination, 0.55).set_trans(Tween.TRANS_CUBIC); await destination_tween.finished

func _travel_to(scene_id: String) -> void:
	if _closing: return
	_closing = true; var tween := create_tween(); tween.tween_property(panel, "modulate:a", 0.0, 0.16); await tween.finished; get_tree().paused = _was_paused
	if not SceneManager.change_to_scene(scene_id): _closing = false; get_tree().paused = true; return
	queue_free()

func close() -> void:
	if _closing: return
	_closing = true; get_tree().paused = _was_paused; queue_free()
