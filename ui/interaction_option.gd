extends PanelContainer
class_name InteractionOption

signal selected(index: int)

@onready var arrow_label: Label = $MarginContainer/HBoxContainer/ArrowLabel
@onready var key_label: Label = $MarginContainer/HBoxContainer/KeyLabel
@onready var text_label: Label = $MarginContainer/HBoxContainer/TextLabel

# 由场景提供两套 StyleBox，避免在脚本里堆叠视觉参数。
@export var normal_style: StyleBox
@export var selected_style: StyleBox

var option_index: int = 0
var is_selected: bool = false

func _ready() -> void:
	# 只让根节点接收点击，避免子 Label 抢走 GUI 输入。
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 同步当前交互键绑定
	if key_label:
		key_label.text = SettingsManager.get_key_name("interact")
	set_selected(false)

func set_text(text: String) -> void:
	if text_label:
		text_label.text = text

func set_index(index: int) -> void:
	option_index = index

func set_selected(selected: bool) -> void:
	is_selected = selected
	if arrow_label:
		arrow_label.visible = selected
	if key_label:
		# 交互键只在当前选项显示，减少未选中状态的视觉噪声。
		key_label.visible = selected
	if text_label:
		text_label.modulate = Color.WHITE if selected else Color(0.72, 0.75, 0.8, 1.0)
	if selected_style and normal_style:
		add_theme_stylebox_override("panel", selected_style if selected else normal_style)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(option_index)
