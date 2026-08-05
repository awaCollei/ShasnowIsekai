extends CanvasLayer
class_name MapScreen

@onready var location_list: VBoxContainer = %LocationList
@onready var current_location_label: Label = %CurrentLocationLabel
@onready var close_button: Button = %CloseButton

var _was_paused: bool = false
var _closing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	close_button.pressed.connect(close)
	_build_location_list()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build_location_list() -> void:
	for child in location_list.get_children():
		child.queue_free()

	var current_id = SceneManager.get_current_scene()
	var current_info := SceneRegistry.get_scene_info(current_id)
	current_location_label.text = "当前位置：%s" % current_info.get("display_name", current_id)

	for scene_id: String in SceneRegistry.get_all_scenes():
		var info := SceneRegistry.get_scene_info(scene_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 54.0)
		button.text = "%s\n%s" % [
			info.get("display_name", scene_id),
			info.get("description", ""),
		]
		button.tooltip_text = info.get("scene_path", "")
		button.disabled = scene_id == current_id
		if button.disabled:
			button.text += "（当前）"
		else:
			button.pressed.connect(_travel_to.bind(scene_id))
		location_list.add_child(button)


func _travel_to(scene_id: String) -> void:
	if _closing:
		return
	_closing = true
	get_tree().paused = _was_paused
	# 场景中的玩家与出生位置由目标 tscn 自己提供。
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
