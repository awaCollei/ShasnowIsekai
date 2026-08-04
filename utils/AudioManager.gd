extends Node

## 全局音频管理器
## 用法：在任何脚本中调用 AudioManager.play_sfx(sound_effect) 即可播放

# 音效播放器（用于短音效）
@onready var sfx_player: AudioStreamPlayer = AudioStreamPlayer.new()

# 背景音乐播放器（用于长音乐）
@onready var bgm_player: AudioStreamPlayer = AudioStreamPlayer.new()

# 音量控制（范围 0.0 ~ 1.0）
var sfx_volume: float = 1.0:
    set(value):
        sfx_volume = clampf(value, 0.0, 1.0)
        sfx_player.volume_db = linear_to_db(sfx_volume)

var bgm_volume: float = 1.0:
    set(value):
        bgm_volume = clampf(value, 0.0, 1.0)
        bgm_player.volume_db = linear_to_db(bgm_volume)


func _ready() -> void:
    # 将两个播放器添加到场景树中
    add_child(sfx_player)
    add_child(bgm_player)
    
    # 设置名称方便调试
    sfx_player.name = "SFXPlayer"
    bgm_player.name = "BGMPlayer"


## 播放音效（短音效，支持重叠播放）
## @param stream: AudioStream 资源，或者音频文件的路径（String）
## @param volume_override: 可选，临时覆盖音量（0.0~1.0）
func play_sfx(stream: Variant, volume_override: float = -1.0) -> void:
    var audio_stream = _get_stream(stream)
    if audio_stream == null:
        push_warning("AudioManager: 无法播放音效，音频流为空")
        return
    
    # 每次播放音效都创建一个新的播放器，支持音效重叠
    var player := AudioStreamPlayer.new()
    player.stream = audio_stream
    player.finished.connect(player.queue_free)
    
    # 设置音量
    var vol = sfx_volume if volume_override < 0 else clampf(volume_override, 0.0, 1.0)
    player.volume_db = linear_to_db(vol)
    
    # 添加到管理器节点下，播放后自动清理
    add_child(player)
    player.play()


## 播放背景音乐（同一时间只能有一首）
## @param stream: AudioStream 资源，或者音频文件的路径（String）
## @param fade_in_time: 渐入时间（秒），默认 0
## @param volume_override: 可选，临时覆盖音量
func play_bgm(stream: Variant, fade_in_time: float = 0.0, volume_override: float = -1.0) -> void:
    var audio_stream = _get_stream(stream)
    if audio_stream == null:
        push_warning("AudioManager: 无法播放背景音乐，音频流为空")
        return
    
    # 如果正在播放相同的音乐，不重复播放
    if bgm_player.playing and bgm_player.stream == audio_stream:
        return
    
    bgm_player.stream = audio_stream
    var vol = bgm_volume if volume_override < 0 else clampf(volume_override, 0.0, 1.0)
    bgm_player.volume_db = linear_to_db(vol)
    bgm_player.play()


## 停止背景音乐
## @param fade_out_time: 渐出时间（秒），默认 0
func stop_bgm(fade_out_time: float = 0.0) -> void:
    if fade_out_time > 0:
        var tween := create_tween()
        tween.tween_property(bgm_player, "volume_db", -80.0, fade_out_time)
        tween.tween_callback(bgm_player.stop)
        # 重置音量
        tween.tween_callback(func(): bgm_player.volume_db = linear_to_db(bgm_volume))
    else:
        bgm_player.stop()


## 暂停背景音乐
func pause_bgm() -> void:
    bgm_player.stream_paused = true


## 恢复背景音乐
func resume_bgm() -> void:
    bgm_player.stream_paused = false


## 设置音效音量（0.0 ~ 1.0）
func set_sfx_volume(value: float) -> void:
    sfx_volume = clampf(value, 0.0, 1.0)


## 设置背景音乐音量（0.0 ~ 1.0）
func set_bgm_volume(value: float) -> void:
    bgm_volume = clampf(value, 0.0, 1.0)


## 获取音效音量
func get_sfx_volume() -> float:
    return sfx_volume


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


## 将线性值转为分贝（Godot 的 volume_db 用分贝）
static func linear_to_db(linear: float) -> float:
    if linear <= 0.0:
        return -80.0
    return 20.0 * log(linear) / log(10.0)