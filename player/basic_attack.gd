extends Node
class_name BasicAttack

signal attack_started
signal attack_ended

@onready var player: Player = get_parent()
@onready var animation: PlayerAnimation = player.get_node("PlayerAnimation")
@onready var attack_area: Area2D = player.get_node("AttackArea")

# 攻击判定帧
const HIT_FRAME_START: int = 4
const HIT_FRAME_END: int = 11

# 两次攻击之间的最短间隔
const COOLDOWN_TIME: float = 0.3

const DAMAGE: int = 10

var attack_stream: AudioStream
var cooldown_remaining: float = 0.0

var hit_enemies: Array = []

enum State {
	IDLE,
	ATTACKING
}

var state: State = State.IDLE

func _ready() -> void:
	attack_stream = load("res://assets/sound_effects/basic_attack.mp3")
	attack_area.monitoring = false
	attack_area.monitorable = false

	attack_area.area_entered.connect(_on_attack_area_entered)
	animation.attack_finished.connect(_on_attack_animation_finished)

func is_busy() -> bool:
	# 动作占用和冷却都必须阻止移动/新动作；攻击动画长于冷却时间。
	return state == State.ATTACKING or cooldown_remaining > 0.0


func cancel() -> void:
	# 统一锁定玩家时中止普攻：结束判定并清空冷却，避免残留占用。
	cooldown_remaining = 0.0
	_end_attack()

func try_attack() -> bool:
	if cooldown_remaining > 0:
		return false

	_start_attack()
	return true

func _start_attack() -> void:
	state = State.ATTACKING

	# 播放攻击音效
	if attack_stream:
		AudioManager.play_game_sfx(attack_stream)

	# 清空本次攻击命中的敌人
	hit_enemies.clear()

	# 重新开始冷却
	cooldown_remaining = COOLDOWN_TIME

	# 关闭旧攻击判定
	attack_area.monitoring = false

	animation.request_attack()
	attack_started.emit()

func _process(delta: float) -> void:
	# 更新攻击冷却
	if cooldown_remaining > 0:
		cooldown_remaining -= delta

	if state == State.ATTACKING:
		_update_hitbox()

func _update_hitbox() -> void:
	# 动画已被打断（例如移动打断了攻击），结束本次攻击
	if not animation.is_attacking():
		_end_attack()
		return

	var frame := animation.get_current_frame()
	var hit_active := (
		frame >= HIT_FRAME_START
		and frame <= HIT_FRAME_END
	)

	attack_area.monitoring = hit_active

	# flip_h=true 表示面朝右
	attack_area.position.x = (
		30.0 if animation.sprite.flip_h else -30.0
	)

func _on_attack_animation_finished() -> void:
	if state == State.ATTACKING:
		_end_attack()

func _end_attack() -> void:
	attack_area.monitoring = false
	state = State.IDLE
	attack_ended.emit()

func _on_attack_area_entered(area: Area2D) -> void:
	if area is Enemy and not hit_enemies.has(area):
		hit_enemies.append(area)
		var enemy := area as Enemy
		# 训练设施等明确禁用回合制的对象继续使用原本的受击反馈。
		if not enemy.battle_enabled:
			enemy.take_damage(DAMAGE)
		else:
			# 局外命中不再直接扣血，而是携带我方先手进入回合制战斗。
			BattleManager.begin_battle(player, enemy, true)
