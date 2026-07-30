extends HBoxContainer
class_name InteractionOption

# 信号
signal selected(index: int)

# 组件引用
@onready var key_label: Label = $KeyLabel
@onready var text_label: Label = $TextLabel

# 状态
var option_index: int = 0
var is_selected: bool = false

func _ready() -> void:
	# 设置鼠标过滤
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_text(text: String) -> void:
	if text_label:
		text_label.text = text

func set_index(index: int) -> void:
	option_index = index

func set_selected(selected: bool) -> void:
	is_selected = selected
	if key_label:
		# F: 只在选中时显示
		key_label.visible = selected
	if text_label:
		if selected:
			# 选中时高亮
			text_label.modulate = Color(1, 1, 1, 1)
		else:
			# 未选中时暗淡
			text_label.modulate = Color(0.6, 0.6, 0.6, 1)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			selected.emit(option_index)