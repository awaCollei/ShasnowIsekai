extends Node

## 全局音频管理器
## 四种音频通道：游戏音效、UI音效、循环音效、背景音乐
## 用法：AudioManager.play_game_sfx(stream) / AudioManager.play_ui_sfx(stream) / AudioManager.play_bgm(stream)
##       AudioManager.play_looping_sfx(stream) / AudioManager.stop_looping_sfx(player)

# 背景音乐播放器（同一时间只能有一首）
@onready var bgm_player: AudioStreamPlayer = AudioStreamPlayer.new()

# 音量控制（范围 0.0 ~ 1.0）
var game_sfx_volume: float = 1.0
var ui_sfx_volume: float = 1.0
var bgm_volume: float = 1.0:
	set(value):
		bgm_volume = clampf(value, 0.0, 1.0)
		if bgm_player:
			bgm_player.volume_db = linear_to_db(bgm_volume)

# 活跃的循环音效播放器，用于音量联动
var _looping_sfx_players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	add_child(bgm_player)
	bgm_player.name = "BGMPlayer"
	bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS


## 播放游戏音效（支持重叠播放）
func play_game_sfx(stream: Variant, volume_override: float = -1.0) -> void:
	var audio_stream = _get_stream(stream)
	if audio_stream == null:
		push_warning("AudioManager: 无法播放游戏音效，音频流为空")
		return

	var player := AudioStreamPlayer.new()
	player.stream = audio_stream
	player.finished.connect(player.queue_free)

	var vol = game_sfx_volume if volume_override < 0 else clampf(volume_override, 0.0, 1.0)
	player.volume_db = linear_to_db(vol)

	add_child(player)
	player.play()


## 播放循环游戏音效（返回播放器句柄，需要手动停止）
func play_looping_sfx(stream: Variant, volume_override: float = -1.0) -> AudioStreamPlayer:
	var audio_stream = _get_stream(stream)
	if audio_stream == null:
		push_warning("AudioManager: 无法播放循环音效，音频流为空")
		return null

	var player := AudioStreamPlayer.new()
	player.stream = audio_stream
	var vol = game_sfx_volume if volume_override < 0 else clampf(volume_override, 0.0, 1.0)
	player.volume_db = linear_to_db(vol)

	add_child(player)
	_looping_sfx_players.append(player)

	var _on_finished := func() -> void:
		if player.playing or is_instance_valid(player):
			player.volume_db = linear_to_db(game_sfx_volume)
			player.play()

	player.finished.connect(_on_finished)
	player.play()
	return player


## 停止循环游戏音效并释放播放器
func stop_looping_sfx(player: AudioStreamPlayer, fade_out_time: float = 3) -> void:
	if player == null:
		return
	_looping_sfx_players.erase(player)
	if fade_out_time > 0:
		var tween := create_tween()
		tween.tween_property(player, "volume_db", -80.0, fade_out_time)
		tween.tween_callback(player.stop)
		tween.tween_callback(player.queue_free)
	else:
		player.stop()
		player.queue_free()


## 播放 UI 音效（支持重叠播放）
func play_ui_sfx(stream: Variant, volume_override: float = -1.0) -> void:
	var audio_stream = _get_stream(stream)
	if audio_stream == null:
		push_warning("AudioManager: 无法播放UI音效，音频流为空")
		return

	var player := AudioStreamPlayer.new()
	player.stream = audio_stream
	player.finished.connect(player.queue_free)

	var vol = ui_sfx_volume if volume_override < 0 else clampf(volume_override, 0.0, 1.0)
	player.volume_db = linear_to_db(vol)

	add_child(player)
	player.play()


## 播放背景音乐（同一时间只能有一首）
func play_bgm(stream: Variant, fade_in_time: float = 0.0, volume_override: float = -1.0) -> void:
	var audio_stream = _get_stream(stream)
	if audio_stream == null:
		push_warning("AudioManager: 无法播放背景音乐，音频流为空")
		return

	if bgm_player.playing and bgm_player.stream == audio_stream:
		return

	# 断开旧的循环连接
	if bgm_player.finished.is_connected(_on_bgm_finished):
		bgm_player.finished.disconnect(_on_bgm_finished)

	bgm_player.stream = audio_stream
	var vol = bgm_volume if volume_override < 0 else clampf(volume_override, 0.0, 1.0)
	bgm_player.volume_db = linear_to_db(vol)
	bgm_player.finished.connect(_on_bgm_finished)
	bgm_player.play()


## BGM 播放完毕后重新播放（实现循环）
func _on_bgm_finished() -> void:
	if bgm_player.stream:
		bgm_player.play()


## 停止背景音乐
func stop_bgm(fade_out_time: float = 0.0) -> void:
	if fade_out_time > 0:
		var tween := create_tween()
		tween.tween_property(bgm_player, "volume_db", -80.0, fade_out_time)
		tween.tween_callback(bgm_player.stop)
		tween.tween_callback(func(): bgm_player.volume_db = linear_to_db(bgm_volume))
	else:
		bgm_player.stop()


## 暂停背景音乐
func pause_bgm() -> void:
	bgm_player.stream_paused = true


## 恢复背景音乐
func resume_bgm() -> void:
	bgm_player.stream_paused = false


## 设置游戏音效音量（0.0 ~ 1.0）
func set_game_sfx_volume(value: float) -> void:
	game_sfx_volume = clampf(value, 0.0, 1.0)
	for p in _looping_sfx_players:
		if is_instance_valid(p):
			p.volume_db = linear_to_db(game_sfx_volume)


## 设置 UI 音效音量（0.0 ~ 1.0）
func set_ui_sfx_volume(value: float) -> void:
	ui_sfx_volume = clampf(value, 0.0, 1.0)


## 设置背景音乐音量（0.0 ~ 1.0）
func set_bgm_volume(value: float) -> void:
	bgm_volume = clampf(value, 0.0, 1.0)


## 获取游戏音效音量
func get_game_sfx_volume() -> float:
	return game_sfx_volume


## 获取 UI 音效音量
func get_ui_sfx_volume() -> float:
	return ui_sfx_volume


## 获取背景音乐音量
func get_bgm_volume() -> float:
	return bgm_volume


## 内部辅助函数：将 AudioStream 或 String 路径转为 AudioStream
func _get_stream(stream: Variant) -> AudioStream:
	if stream is AudioStream:
		return stream
	elif stream is String:
		return load(stream) as AudioStream
	else:
		return null


## 将线性值转为分贝
static func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)
