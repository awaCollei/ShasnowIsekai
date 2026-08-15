extends ConfirmationDialog

## 统一的项目确认框：避免使用 Godot 默认灰色外观，并统一中文按钮。
func _ready() -> void:
	theme = preload("res://theme/teal_ui.tres")
	get_ok_button().text = "确认"
	get_cancel_button().text = "取消"
	get_ok_button().add_theme_font_size_override("font_size", 16)
	get_cancel_button().add_theme_font_size_override("font_size", 16)
