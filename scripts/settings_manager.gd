extends Node

# 默认键位绑定
const DEFAULT_KEY_BINDINGS: Dictionary = {
	"move_up": KEY_UP,
	"move_down": KEY_DOWN,
	"move_left": KEY_LEFT,
	"move_right": KEY_RIGHT,
	"interact": KEY_F,
	"inventory": KEY_E,
	"select_prev": KEY_W,
	"select_next": KEY_S,
	"menu": KEY_ESCAPE,
	"attack": KEY_Z,
	"chant": KEY_X,
	"dodge": KEY_SHIFT,
	"confirm": KEY_SPACE,
}

# 键位显示名称
const KEY_BINDING_NAMES: Dictionary = {
	"move_up": "移动（上）",
	"move_down": "移动（下）",
	"move_left": "移动（左）",
	"move_right": "移动（右）",
	"interact": "交互",
	"inventory": "背包",
	"select_prev": "选择（上一个）",
	"select_next": "选择（下一个）",
	"menu": "菜单",
	"attack": "攻击",
	"chant": "吟唱",
	"dodge": "闪避",
	"confirm": "确认/推进对话",
}

# 当前键位绑定
var key_bindings: Dictionary = {}

# 始终疾跑
var always_run: bool = false

# 音量设置（0.0 ~ 1.0）
var game_sfx_volume: float = 1.0
var ui_sfx_volume: float = 1.0
var voice_volume: float = 1.0
var bgm_volume: float = 1.0

# 设置文件路径
const SETTINGS_PATH: String = "user://settings.cfg"

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)

	# 加载键位
	for action in DEFAULT_KEY_BINDINGS:
		if err == OK and config.has_section_key("key_bindings", action):
			key_bindings[action] = config.get_value("key_bindings", action)
		else:
			key_bindings[action] = DEFAULT_KEY_BINDINGS[action]

	# 加载始终疾跑
	if err == OK and config.has_section_key("gameplay", "always_run"):
		always_run = config.get_value("gameplay", "always_run", false)
	else:
		always_run = false

	# 加载音量设置
	if err == OK and config.has_section_key("audio", "game_sfx"):
		game_sfx_volume = config.get_value("audio", "game_sfx", 1.0)
	else:
		game_sfx_volume = 1.0

	if err == OK and config.has_section_key("audio", "ui_sfx"):
		ui_sfx_volume = config.get_value("audio", "ui_sfx", 1.0)
	else:
		ui_sfx_volume = 1.0

	if err == OK and config.has_section_key("audio", "voice"):
		voice_volume = config.get_value("audio", "voice", 1.0)
	else:
		voice_volume = 1.0

	if err == OK and config.has_section_key("audio", "bgm"):
		bgm_volume = config.get_value("audio", "bgm", 1.0)
	else:
		bgm_volume = 1.0

	apply_key_bindings()
	apply_audio_settings()

func save_settings() -> void:
	var config := ConfigFile.new()

	for action in key_bindings:
		config.set_value("key_bindings", action, key_bindings[action])

	config.set_value("gameplay", "always_run", always_run)

	config.set_value("audio", "game_sfx", game_sfx_volume)
	config.set_value("audio", "ui_sfx", ui_sfx_volume)
	config.set_value("audio", "voice", voice_volume)
	config.set_value("audio", "bgm", bgm_volume)

	config.save(SETTINGS_PATH)

func apply_key_bindings() -> void:
	for action in key_bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

		# 清除旧的事件
		InputMap.action_erase_events(action)

		# 添加新的按键事件
		var event := InputEventKey.new()
		event.keycode = key_bindings[action]
		event.physical_keycode = key_bindings[action]
		InputMap.action_add_event(action, event)

func reset_to_defaults() -> void:
	for action in DEFAULT_KEY_BINDINGS:
		key_bindings[action] = DEFAULT_KEY_BINDINGS[action]
	always_run = false
	game_sfx_volume = 1.0
	ui_sfx_volume = 1.0
	voice_volume = 1.0
	bgm_volume = 1.0
	apply_key_bindings()
	apply_audio_settings()
	save_settings()

func set_key_binding(action: String, keycode: Key) -> void:
	if key_bindings.has(action):
		key_bindings[action] = keycode
		apply_key_bindings()
		save_settings()

func get_key_name(action: String) -> String:
	if key_bindings.has(action):
		return OS.get_keycode_string(key_bindings[action])
	return ""

func set_always_run(value: bool) -> void:
	always_run = value
	save_settings()


func set_game_sfx_volume(value: float) -> void:
	game_sfx_volume = value
	AudioManager.set_game_sfx_volume(value)
	save_settings()


func set_ui_sfx_volume(value: float) -> void:
	ui_sfx_volume = value
	AudioManager.set_ui_sfx_volume(value)
	save_settings()


func set_voice_volume(value: float) -> void:
	voice_volume = value
	AudioManager.set_voice_volume(value)
	save_settings()


func set_bgm_volume(value: float) -> void:
	bgm_volume = value
	AudioManager.set_bgm_volume(value)
	save_settings()


func apply_audio_settings() -> void:
	AudioManager.set_game_sfx_volume(game_sfx_volume)
	AudioManager.set_ui_sfx_volume(ui_sfx_volume)
	AudioManager.set_voice_volume(voice_volume)
	AudioManager.set_bgm_volume(bgm_volume)
