extends Node

# 场景管理器单例
static var instance: SceneManager

# 当前场景
var current_scene: String = "base"

func _ready() -> void:
	# 设置单例
	instance = self
	
	# 连接场景切换信号
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	# 当玩家节点被添加到场景时，更新其场景信息
	if node is Player:
		node.set_scene_info(current_scene)

func get_current_scene() -> String:
	return current_scene

func set_scene_info(scene: String) -> void:
	current_scene = scene
