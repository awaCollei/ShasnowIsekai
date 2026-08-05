extends RefCounted
class_name CharacterDatabase

## 角色数据表 — 静态工具类，从 characters.json 加载并提供角色数据查询。

static var _data: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var file := FileAccess.open("res://assets/characters.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		if err == OK:
			_data = json.data
		file.close()
	_loaded = true


## 获取指定 ID 角色的完整数据
static func get_character(id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get(id, {})


## 获取所有角色 ID 列表
static func get_all_ids() -> Array:
	_ensure_loaded()
	return _data.keys()


## 获取角色的某个动画配置（不存在则返回空字典）
static func get_animation(id: String, anim_name: String) -> Dictionary:
	var char_data := get_character(id)
	var animations: Dictionary = char_data.get("animations", {})
	return animations.get(anim_name, {})