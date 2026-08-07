extends Character
class_name Player

@onready var basic_attack: BasicAttack = $BasicAttack
@onready var magic_blade: MagicBlade = $MagicBlade
@onready var animation: PlayerAnimation = $PlayerAnimation
@onready var status_hud: PlayerStatusHUD = $HUD/PlayerStatusHUD
@onready var chant_effect: MagicChantEffect = $MagicChantEffect

signal hp_changed(hp: float, max_hp: float)
signal mp_changed(mp: float, max_mp: float, reserved_mp: float)
signal died

@export_group("生命与魔力")
@export var max_hp: float = 100.0
@export var max_mp: float = 100.0
@export var mp_regen_per_second: float = 1.0

var hp: float = 100.0
## mp 始终是实际 MP；吟唱预扣只记录在 reserved_mp 中。
var mp: float = 100.0
var reserved_mp: float = 0.0
var is_dead := false
var _chant_mp_cost: float = 0.0
var _cancel_start_reserved_mp: float = 0.0

# ==========================
# 疾跑系统
# ==========================
var is_running := false
var last_direction := 0.0
var last_press_time := -1.0
const DOUBLE_TAP_TIME := 0.3
var was_direction_pressed := false

# ==========================
# 子场景属性
# ==========================
@export var current_scene: String = "base"
@export var current_sub_scene: String = "outdoor"

func _ready() -> void:
	# 初始化角色基类
	character_id = "shasnow"
	initialize("shasnow")
	hp = max_hp
	mp = max_mp
	chant_effect.charge_changed.connect(_on_chant_charge_changed)
	status_hud.bind(self)
	hp_changed.emit(hp, max_hp)
	mp_changed.emit(mp, max_mp, reserved_mp)

	# 加入 player 组，供 PlotlineManager 等系统查找
	add_to_group("player")

	# 获取当前场景
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager:
		current_scene = scene_manager.get_current_scene()

func set_scene_info(scene: String) -> void:
	current_scene = scene

# ==========================
# 传送
# ==========================
func teleport_to(destination: Vector2) -> void:
	super.teleport_to(destination)
	var camera := get_node_or_null("Camera2D") as PlayerCamera
	if camera:
		camera.smooth_move_to(destination)

func _process(delta: float) -> void:
	if is_dead:
		return
	# 实际 MP 自然恢复；预扣量不参与扣除，因此可视 MP = 实际 MP - 预扣量。
	if mp < max_mp:
		var old_mp := mp
		mp = minf(max_mp, mp + mp_regen_per_second * delta)
		if not is_equal_approx(old_mp, mp):
			mp_changed.emit(mp, max_mp, reserved_mp)


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		return
	# 局外只保留普通攻击。吟唱素材和 MagicBlade 节点继续保留，供回合制技能/未来大招复用。
	if Input.is_action_just_pressed("attack") and not basic_attack.is_busy() and not animation.is_attacking():
		basic_attack.try_attack()

	# 普攻、吟唱及魔法之刃释放期间禁止移动。
	if basic_attack.is_busy() or magic_blade.is_busy() or animation.is_chanting():
		velocity.x = 0.0
		move_and_slide()
		return

	var direction := Input.get_axis("ui_left", "ui_right")

	# ======================
	# 始终疾跑检测
	# ======================
	var always_run := false
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		always_run = settings.always_run

	# ======================
	# 双击检测
	# ======================
	var pressed := direction != 0.0

	if pressed and not was_direction_pressed:
		handle_run_input(direction)

	was_direction_pressed = pressed

	# ======================
	# 移动
	# ======================
	if direction != 0.0:
		var effective_running := is_running or always_run
		var current_speed = run_speed if effective_running else walk_speed
		velocity.x = direction * current_speed
		animation.set_flip_h(direction > 0.0)

		if effective_running:
			animation.request_run()
		else:
			animation.request_walk()
	else:
		# 停止移动
		velocity.x = 0.0
		# 攻击 / 吟唱动画正在播放时，不要让自动 idle 打断它
		if not animation.is_attacking() and not animation.is_chanting():
			animation.request_idle()
		# 松开方向键退出疾跑
		is_running = false

	move_and_slide()

# ==========================
# HP / MP
# ==========================
func take_damage(amount: float) -> void:
	if amount <= 0.0 or hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		is_dead = true
		cancel_magic_chant()
		animation.request_idle()
		velocity = Vector2.ZERO
		died.emit()


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + maxf(amount, 0.0))
	hp_changed.emit(hp, max_hp)


func get_hp_ratio() -> float:
	return hp / maxf(max_hp, 1.0)


func get_visible_mp() -> float:
	return maxf(0.0, mp - reserved_mp)


## 回合制技能直接消费实际 MP；局外吟唱预扣期间不允许并行消费。
func spend_mp(amount: float) -> bool:
	amount = maxf(0.0, amount)
	if amount <= 0.0:
		return true
	if reserved_mp > 0.0 or mp + 0.001 < amount:
		return false
	mp = maxf(0.0, mp - amount)
	mp_changed.emit(mp, max_mp, reserved_mp)
	return true


func gain_mp(amount: float) -> void:
	if amount <= 0.0:
		return
	mp = minf(max_mp, mp + amount)
	mp_changed.emit(mp, max_mp, reserved_mp)


## 读档专用：只恢复持久资源，吟唱预扣属于临时状态，不跨存档保存。
func restore_status(saved_hp: float, saved_max_hp: float, saved_mp: float, saved_max_mp: float) -> void:
	if saved_max_hp > 0.0:
		max_hp = saved_max_hp
	if saved_max_mp > 0.0:
		max_mp = saved_max_mp
	if saved_hp >= 0.0:
		hp = clampf(saved_hp, 0.0, max_hp)
	if saved_mp >= 0.0:
		mp = clampf(saved_mp, 0.0, max_mp)
	reserved_mp = 0.0
	_chant_mp_cost = 0.0
	_cancel_start_reserved_mp = 0.0
	is_dead = hp <= 0.0
	hp_changed.emit(hp, max_hp)
	mp_changed.emit(mp, max_mp, reserved_mp)


func begin_magic_chant(cost: float) -> bool:
	# 当前 MP 不足也允许起手；MagicChantEffect 会在可承担进度处等待自然恢复。
	if cost <= 0.0:
		return false
	_chant_mp_cost = cost
	reserved_mp = 0.0
	mp_changed.emit(mp, max_mp, reserved_mp)
	return true


func get_magic_chant_progress_limit() -> float:
	if _chant_mp_cost <= 0.0:
		return 0.0
	# 实际 MP 未扣除，所以它同时也是“可视 MP + 缓冲 MP”的总量。
	return clampf(mp / _chant_mp_cost, 0.0, 1.0)


func _on_chant_charge_changed(progress: float) -> void:
	if _chant_mp_cost <= 0.0:
		return
	# 唯一绑定源是吟唱进度，不依赖 HUD 自己计时。
	reserved_mp = minf(mp, _chant_mp_cost * clampf(progress, 0.0, 1.0))
	mp_changed.emit(mp, max_mp, reserved_mp)


## 开始取消吟唱。归还速度由逆向吟唱动画帧驱动，不在这里计时。
func begin_magic_chant_cancel() -> void:
	_cancel_start_reserved_mp = reserved_mp


## remaining_ratio: 1 表示刚开始收招，0 表示收招结束。
func update_magic_chant_cancel(remaining_ratio: float) -> void:
	reserved_mp = _cancel_start_reserved_mp * clampf(remaining_ratio, 0.0, 1.0)
	mp_changed.emit(mp, max_mp, reserved_mp)


func cancel_magic_chant() -> void:
	_chant_mp_cost = 0.0
	_cancel_start_reserved_mp = 0.0
	reserved_mp = 0.0
	mp_changed.emit(mp, max_mp, reserved_mp)


func commit_magic_chant() -> bool:
	if _chant_mp_cost <= 0.0 or reserved_mp + 0.001 < _chant_mp_cost:
		return false
	mp = maxf(0.0, mp - reserved_mp)
	_chant_mp_cost = 0.0
	_cancel_start_reserved_mp = 0.0
	reserved_mp = 0.0
	mp_changed.emit(mp, max_mp, reserved_mp)
	return true


# ==========================
# 双击检测
# ==========================
func handle_run_input(direction: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	# 同方向快速再次按下
	if direction == last_direction:
		if now - last_press_time <= DOUBLE_TAP_TIME:
			is_running = true

	last_direction = direction
	last_press_time = now
