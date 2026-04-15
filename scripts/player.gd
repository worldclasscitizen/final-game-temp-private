extends CharacterBody2D
## 플레이어 — 2D 횡스크롤 캐릭터 + 카드 빌드업 + Nidhogg-style 실루엣 리그
##
## 입력 스킴 (InputScheme):
##   ONLINE   — 멀티플레이어. 자기 peer 만 입력 처리.
##   LOCAL_P1 — WASD + 마우스 + F/좌클릭.
##   LOCAL_P2 — 화살표 + `,`/`.` + `/`.
##
## 실루엣 리그:
##   Silhouette (Node2D, scale.x 로 좌우 플립)
##     ├─ LegPivotL/R → Leg
##     ├─ TorsoPivot → Torso / NeckPivot → Neck / HeadPivot → Head
##     ├─ ArmPivotL → Arm          (달리기 swing)
##     └─ ArmPivotR → Arm + Weapon (조준, aim_angle 로 회전 override)
##   방향 전환은 _facing_visual 을 lerp 해서 squash → reflip.
##   달리기는 _cycle 을 이용한 sine wave 로 다리/왼팔 swing + 몸통 bobbing.
##   점프/낙하 중에는 다리를 접고 왼팔 살짝 들어올림.

signal player_died(who_id: int, killer_id: int)
signal player_won(who_id: int)
signal card_offered(player: Node, card_ids: Array)

enum InputScheme { ONLINE, LOCAL_P1, LOCAL_P2 }

const SPEED := 185.0
const ACCEL := 1800.0
const FRICTION := 1600.0
const JUMP_VELOCITY := -520.0
const GRAVITY := 1400.0
const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const DeathEffect := preload("res://scripts/death_effect.gd")

# ── 스프라이트 텍스처 세트 (P1/P2) ──
const P1_TEX := {
	"head":  preload("res://assets/sprites/p1_head.png"),
	"neck":  preload("res://assets/sprites/p1_neck.png"),
	"torso": preload("res://assets/sprites/p1_torso.png"),
	"arm":   preload("res://assets/sprites/p1_arm.png"),
	"leg":   preload("res://assets/sprites/p1_leg.png"),
}
const P2_TEX := {
	"head":  preload("res://assets/sprites/p2_head.png"),
	"neck":  preload("res://assets/sprites/p2_neck.png"),
	"torso": preload("res://assets/sprites/p2_torso.png"),
	"arm":   preload("res://assets/sprites/p2_arm.png"),
	"leg":   preload("res://assets/sprites/p2_leg.png"),
}
const WEAPON_TEX := preload("res://assets/sprites/weapon.png")
const SHOT_INTERVAL := 0.10     # 탄창 내 연사 간격
const BASE_RELOAD_TIME := 1.2   # 기본 재장전 시간(초)
const BASE_MAG_SIZE := 1        # 기본 탄창 크기
const P2_AIM_TILT := PI / 6    # 30도
const RESPAWN_IMMUNITY := 1.0  # 리스폰 직후 무적시간(초)

# 애니메이션
const FACING_LERP := 14.0
const RUN_CYCLE_SPEED := 14.0   # rad/sec, full speed 기준
const RUN_SWING := 0.55         # 다리/왼팔 swing amplitude (rad)
const RUN_BOB := 1.6             # 몸통 상하 bobbing (px)
const IDLE_LERP := 10.0

@export var player_id: int = 1
@export var spawn_position: Vector2
@export var goal_x: float
@export var goal_direction: int = 1
## 입력 스킴 (int 로 선언하는 이유: game.gd 에서 상수 int 로 대입해야
## 외부에서 Player.InputScheme 접근 없이도 값 전달 가능)
@export var input_scheme: int = InputScheme.ONLINE

@export var aim_angle: float = 0.0
@export var facing: int = 1
@export var is_alive: bool = true

# 카드 (로컬은 그냥 배열, 온라인은 RPC 로 동기화)
var cards: Array[String] = []

var _shot_timer := 0.0         # 탄창 내 연사 쿨다운
var _respawn_timer := 0.0
var _picking_card := false
var _death_by_oob := false
var _immunity_timer := 0.0
var _facing_visual: float = 1.0
var _cycle: float = 0.0

# ── 탄창 시스템 ──
var _mag_size: int = BASE_MAG_SIZE
var _ammo: int = BASE_MAG_SIZE
var _reloading := false
var _reload_timer := 0.0
var _reload_duration: float = BASE_RELOAD_TIME
var _ammo_dots: Array[ColorRect] = []
var _reload_bar_bg: ColorRect
var _reload_bar_fill: ColorRect

# ── 사망 애니메이션 ──
var _death_anim_timer := 0.0
var _death_anim_phase := 0          # 0=없음, 1=이펙트 재생 중
var _death_pos := Vector2.ZERO
var _death_color := Color.WHITE
var _last_hit_pos := Vector2.ZERO   # 총알이 맞은 월드 좌표
var _last_hit_dir := Vector2.RIGHT  # 총알 진행 방향 (정규화)
var _last_bullet_force := 1.0       # 총알 충격력 (정규화, 1.0 = 기본)
var _death_vel := Vector2.ZERO      # 사망 직전 속도 (관성 계산용)
var _death_grounded := true          # 사망 시 지면 접촉 여부

@onready var silhouette: Node2D = $Silhouette
@onready var torso_pivot: Node2D = $Silhouette/TorsoPivot
@onready var torso: Sprite2D = $Silhouette/TorsoPivot/Torso
@onready var neck_pivot: Node2D = $Silhouette/NeckPivot
@onready var neck: Sprite2D = $Silhouette/NeckPivot/Neck
@onready var head_pivot: Node2D = $Silhouette/HeadPivot
@onready var head: Sprite2D = $Silhouette/HeadPivot/Head
@onready var leg_pivot_l: Node2D = $Silhouette/LegPivotL
@onready var leg_pivot_r: Node2D = $Silhouette/LegPivotR
@onready var leg_l: Sprite2D = $Silhouette/LegPivotL/Leg
@onready var leg_r: Sprite2D = $Silhouette/LegPivotR/Leg
@onready var arm_pivot_l: Node2D = $Silhouette/ArmPivotL
@onready var arm_pivot_r: Node2D = $Silhouette/ArmPivotR
@onready var arm_l: Sprite2D = $Silhouette/ArmPivotL/Arm
@onready var arm_r: Sprite2D = $Silhouette/ArmPivotR/Arm
@onready var weapon: Sprite2D = $Silhouette/ArmPivotR/Weapon
@onready var hit_area: Area2D = $HitArea
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var name_label: Label = $NameLabel
@onready var card_count_label: Label = $CardCountLabel


func _enter_tree() -> void:
	if Network.is_online():
		set_multiplayer_authority(player_id)
	else:
		set_multiplayer_authority(1)


func _ready() -> void:
	global_position = spawn_position
	name_label.visible = false
	_facing_visual = float(facing)
	silhouette.scale.x = _facing_visual
	_update_color()
	_update_card_count()
	hit_area.area_entered.connect(_on_hit_area_area_entered)
	_recalculate_gun_stats()
	_build_ammo_dots()
	_build_reload_bar()


func _update_color() -> void:
	# 플레이어 ID에 따라 텍스처 세트 교체
	var tex: Dictionary = P1_TEX if player_id == 1 else P2_TEX
	if head:
		head.texture = tex["head"]
	if neck:
		neck.texture = tex["neck"]
	if torso:
		torso.texture = tex["torso"]
	if arm_l:
		arm_l.texture = tex["arm"]
	if arm_r:
		arm_r.texture = tex["arm"]
	if leg_l:
		leg_l.texture = tex["leg"]
	if leg_r:
		leg_r.texture = tex["leg"]
	if weapon:
		weapon.texture = WEAPON_TEX
	# 모든 노드의 modulate 보장 (사망 애니메이션 복원용)
	if silhouette:
		silhouette.modulate = Color.WHITE
		silhouette.self_modulate = Color.WHITE
	for pivot in [leg_pivot_l, leg_pivot_r, arm_pivot_l, arm_pivot_r, torso_pivot, neck_pivot, head_pivot]:
		if pivot:
			pivot.modulate = Color.WHITE
			pivot.self_modulate = Color.WHITE
	for sprite in [head, neck, torso, arm_l, arm_r, leg_l, leg_r, weapon]:
		if sprite:
			sprite.modulate = Color.WHITE
			sprite.self_modulate = Color.WHITE
	self_modulate = Color.WHITE
	modulate = Color.WHITE
	_set_light_mask_recursive(self, 0)


func _set_light_mask_recursive(node: Node, mask: int) -> void:
	if node is CanvasItem:
		(node as CanvasItem).light_mask = mask
	for child in node.get_children():
		# MultiplayerSynchronizer 등 비-CanvasItem은 건너뜀
		if child is CanvasItem:
			_set_light_mask_recursive(child, mask)


func _update_card_count() -> void:
	card_count_label.text = "card x%d" % cards.size() if cards.size() > 0 else ""


## 이 PC 에서 이 플레이어를 조작할 수 있는가?
func is_controllable() -> bool:
	if Network.is_local():
		return input_scheme == InputScheme.LOCAL_P1 or input_scheme == InputScheme.LOCAL_P2
	return is_multiplayer_authority()


func _physics_process(delta: float) -> void:
	if _immunity_timer > 0.0:
		_immunity_timer = max(0.0, _immunity_timer - delta)
		# 무적 중 깜빡임
		modulate.a = 0.5 if int(_immunity_timer * 10) % 2 == 0 else 1.0
	else:
		modulate.a = 1.0

	if not is_alive:
		_tick_respawn(delta)
		return

	if is_controllable():
		_handle_input(delta)
		# 승리는 game.gd 의 UFO 납치 연출에서 선언된다. _check_goal 은 사용하지 않음.

	_update_animation(delta)


func has_respawn_immunity() -> bool:
	return _immunity_timer > 0.0


func _handle_input(delta: float) -> void:
	if _picking_card:
		return

	var dir := _get_move_axis()
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * SPEED, ACCEL * delta)
		# P2(로컬) 은 이동 방향 = 바라보는 방향 (조준이 facing 기반)
		if input_scheme == InputScheme.LOCAL_P2:
			facing = int(sign(dir))
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	# P1/온라인(마우스 조준) 은 마우스 X 위치로 facing 결정
	if input_scheme != InputScheme.LOCAL_P2:
		var aim_dx: float = get_global_mouse_position().x - global_position.x
		if absf(aim_dx) > 4.0:
			facing = 1 if aim_dx > 0.0 else -1

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	elif _is_jump_just_pressed():
		velocity.y = JUMP_VELOCITY

	move_and_slide()

	aim_angle = _compute_aim_angle()

	# ── 재장전 틱 ──
	if _reloading:
		_reload_timer -= delta
		_update_reload_bar()
		if _reload_timer <= 0.0:
			_reloading = false
			_ammo = _mag_size
			_update_ammo_dots()
			_update_reload_bar()

	# ── 발사 ──
	_shot_timer = max(0.0, _shot_timer - delta)
	if _is_fire_pressed() and _shot_timer <= 0.0 and not _reloading and _ammo > 0:
		_shot_timer = SHOT_INTERVAL
		_ammo -= 1
		_update_ammo_dots()
		# 총구 위치: ArmPivotR 로컬 (0, 29)을 글로벌로 변환
		var muzzle_local := Vector2(0, 29.0)
		var shoot_pos := arm_pivot_r.global_transform * muzzle_local
		var cards_snapshot := cards.duplicate()
		if Network.is_online():
			_fire_bullet.rpc(shoot_pos, aim_angle, player_id, cards_snapshot)
		else:
			_spawn_local_bullet(shoot_pos, aim_angle, player_id, cards_snapshot)
		# 탄창 비면 자동 재장전
		if _ammo <= 0:
			_start_reload()


## ── 탄창 / 재장전 ────────────────────────────────────────────

func _recalculate_gun_stats() -> void:
	var stats: Dictionary = CardDB.compute_bullet_stats(cards)
	_mag_size = BASE_MAG_SIZE + int(stats.get("mag_add", 0))
	var reload_mult: float = float(stats.get("reload_mult", 1.0))
	_reload_duration = BASE_RELOAD_TIME * reload_mult


func _start_reload() -> void:
	_reloading = true
	_reload_timer = _reload_duration
	_update_reload_bar()


func _cancel_reload() -> void:
	_reloading = false
	_reload_timer = 0.0
	_update_reload_bar()


func _refill_ammo() -> void:
	_ammo = _mag_size
	_cancel_reload()
	_update_ammo_dots()


## ── 탄약 도트 (총열 위 흰 점) ────────────────────────────────

func _build_ammo_dots() -> void:
	# 기존 도트 제거
	for dot in _ammo_dots:
		if is_instance_valid(dot):
			dot.queue_free()
	_ammo_dots.clear()
	# Weapon 은 ArmPivotR 자식, y=12~30(총열). 도트는 총열 '위'에 배치.
	# ArmPivotR 로컬 좌표계에서 총이 +Y 방향으로 뻗어 있으므로,
	# 총열 "윗면" = -X 방향. 총구(y≈29)와 가늠좌(y≈14) 사이 위쪽 공간.
	var barrel_start := 14.0
	var barrel_end := 28.0
	var count: int = _mag_size
	if count <= 0:
		return
	var spacing: float = (barrel_end - barrel_start) / float(max(count, 1))
	for i in count:
		var dot := ColorRect.new()
		dot.size = Vector2(2, 2)
		var dy: float = barrel_start + spacing * (float(i) + 0.5) - 1.0
		dot.position = Vector2(-4.0, dy)  # -4: 총열 왼쪽(=위) 표면
		dot.color = Color(1, 1, 1, 0.9)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arm_pivot_r.add_child(dot)
		_ammo_dots.append(dot)
	_update_ammo_dots()


func _update_ammo_dots() -> void:
	for i in _ammo_dots.size():
		if i < _ammo_dots.size() and is_instance_valid(_ammo_dots[i]):
			_ammo_dots[i].visible = (i < _ammo)


## ── 리로드 게이지 바 (플레이어 머리 위) ──────────────────────

const RELOAD_BAR_W := 24.0
const RELOAD_BAR_H := 3.0

func _build_reload_bar() -> void:
	# 배경 (어두운 바)
	_reload_bar_bg = ColorRect.new()
	_reload_bar_bg.size = Vector2(RELOAD_BAR_W, RELOAD_BAR_H)
	_reload_bar_bg.position = Vector2(-RELOAD_BAR_W * 0.5, -28.0)
	_reload_bar_bg.color = Color(0.2, 0.2, 0.2, 0.7)
	_reload_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reload_bar_bg.visible = false
	add_child(_reload_bar_bg)
	# 채움 바
	_reload_bar_fill = ColorRect.new()
	_reload_bar_fill.size = Vector2(0, RELOAD_BAR_H)
	_reload_bar_fill.position = Vector2.ZERO
	_reload_bar_fill.color = Color(1, 1, 1, 0.85)
	_reload_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reload_bar_bg.add_child(_reload_bar_fill)


func _update_reload_bar() -> void:
	if not is_instance_valid(_reload_bar_bg):
		return
	_reload_bar_bg.visible = _reloading
	if _reloading and _reload_duration > 0.0:
		var progress: float = 1.0 - (_reload_timer / _reload_duration)
		_reload_bar_fill.size.x = RELOAD_BAR_W * clampf(progress, 0.0, 1.0)


## ── 입력 추상화 ───────────────────────────────────────────────

func _get_move_axis() -> float:
	if input_scheme == InputScheme.LOCAL_P2:
		return Input.get_axis("p2_move_left", "p2_move_right")
	return Input.get_axis("move_left", "move_right")


func _is_jump_just_pressed() -> bool:
	if input_scheme == InputScheme.LOCAL_P2:
		return Input.is_action_just_pressed("p2_jump")
	return Input.is_action_just_pressed("jump")


func _is_fire_pressed() -> bool:
	if input_scheme == InputScheme.LOCAL_P2:
		return Input.is_action_pressed("p2_fire")
	return Input.is_action_pressed("fire")


## P1/온라인 = 마우스 방향 / P2(로컬) = 바라보는 방향 + 30° 상/하 틸트
func _compute_aim_angle() -> float:
	if input_scheme == InputScheme.LOCAL_P2:
		var base := 0.0 if facing >= 0 else PI
		var tilt := 0.0
		if Input.is_action_pressed("p2_aim_up"):
			tilt = -P2_AIM_TILT
		elif Input.is_action_pressed("p2_aim_down"):
			tilt = P2_AIM_TILT
		if facing < 0:
			tilt = -tilt
		return base + tilt
	var to_mouse := get_global_mouse_position() - global_position
	return to_mouse.angle()


## ── 애니메이션 ────────────────────────────────────────────────

func _update_animation(delta: float) -> void:
	# 방향 전환 스무스: _facing_visual 을 ±1 로 lerp → squash 후 reflip
	var target_fv := float(facing)
	var t_face := clampf(FACING_LERP * delta, 0.0, 1.0)
	_facing_visual = lerpf(_facing_visual, target_fv, t_face)
	silhouette.scale.x = _facing_visual

	var grounded := is_on_floor()
	var running := grounded and absf(velocity.x) > 30.0

	if not grounded:
		_apply_air_pose(delta)
	elif running:
		_advance_cycle(delta)
		_apply_run_pose()
	else:
		_cycle = 0.0
		_apply_idle_pose(delta)

	# 오른팔은 항상 조준 각도 override (다른 포즈 이후 덮어쓰기)
	_apply_aim_arm()


func _advance_cycle(delta: float) -> void:
	var speed_ratio: float = clampf(absf(velocity.x) / SPEED, 0.3, 1.2)
	_cycle += RUN_CYCLE_SPEED * speed_ratio * delta


func _apply_run_pose() -> void:
	var s := sin(_cycle)
	var c := cos(_cycle)
	# 다리: 서로 반대 phase
	leg_pivot_l.rotation = s * RUN_SWING
	leg_pivot_r.rotation = -s * RUN_SWING
	# 몸통/머리 bobbing (두 다리가 교차할 때 살짝 내려감)
	var bob: float = -absf(c) * RUN_BOB
	torso_pivot.position.y = bob
	neck_pivot.position.y = bob
	head_pivot.position.y = bob
	# 왼팔은 달리기 swing (오른팔은 _apply_aim_arm 에서 override)
	arm_pivot_l.rotation = -s * (RUN_SWING * 0.9)


func _apply_air_pose(delta: float) -> void:
	# 점프 올라갈 땐 다리 당겨올림, 낙하는 조금 펴기
	var target_leg: float = -0.45 if velocity.y < 0.0 else -0.15
	var t: float = clampf(IDLE_LERP * delta, 0.0, 1.0)
	leg_pivot_l.rotation = lerpf(leg_pivot_l.rotation, target_leg, t)
	leg_pivot_r.rotation = lerpf(leg_pivot_r.rotation, target_leg * 1.2, t)
	# 왼팔은 살짝 들어올림
	arm_pivot_l.rotation = lerpf(arm_pivot_l.rotation, -0.6, t)
	torso_pivot.position.y = 0.0
	neck_pivot.position.y = 0.0
	head_pivot.position.y = 0.0


func _apply_idle_pose(delta: float) -> void:
	var t: float = clampf(IDLE_LERP * delta, 0.0, 1.0)
	leg_pivot_l.rotation = lerpf(leg_pivot_l.rotation, 0.0, t)
	leg_pivot_r.rotation = lerpf(leg_pivot_r.rotation, 0.0, t)
	arm_pivot_l.rotation = lerpf(arm_pivot_l.rotation, 0.0, t)
	torso_pivot.position.y = 0.0
	neck_pivot.position.y = 0.0
	head_pivot.position.y = 0.0


## 오른팔(총 든 팔) 이 aim_angle 방향을 향하도록 로컬 rotation 설정.
## ArmPivotR 은 Silhouette 자식. Silhouette.scale.x 가 음수이면 반사됨.
## Arm 의 기본 방향은 +Y (아래) 이므로:
##   scale.x > 0 : local_rot = aim_angle - PI/2
##   scale.x < 0 : local_rot = PI/2 - aim_angle   (반사 보정)
func _apply_aim_arm() -> void:
	if facing >= 0:
		arm_pivot_r.rotation = aim_angle - PI / 2.0
	else:
		arm_pivot_r.rotation = PI / 2.0 - aim_angle


## game.gd 에서 카메라 기준 바깥으로 판정하면 호출됨
func oob_kill() -> void:
	if not is_alive:
		return
	if has_respawn_immunity():
		return
	_death_by_oob = true
	_request_die(0)


## ── 사망 / 리스폰 / 카드 ─────────────────────────────────────

func _request_die(killer_id: int = 0) -> void:
	if not is_controllable():
		return
	if Network.is_online():
		_apply_die.rpc(killer_id)
	else:
		_apply_die(killer_id)


@rpc("authority", "call_local", "reliable")
func _apply_die(killer_id: int = 0) -> void:
	if not is_alive:
		return
	is_alive = false
	_death_vel = velocity
	_death_grounded = is_on_floor()
	velocity = Vector2.ZERO
	_cancel_reload()
	hit_area.set_deferred("monitoring", false)
	hit_area.set_deferred("monitorable", false)
	player_died.emit(player_id, killer_id)
	# 사망 애니메이션 시작 (OOB 사망은 즉시 숨김)
	if _death_by_oob:
		visible = false
		_respawn_timer = 1.0
	else:
		_death_pos = global_position
		_death_color = Color(0.58, 0.48, 0.20) if player_id == 1 else Color(0.55, 0.28, 0.22)
		_spawn_death_effect()
		visible = false
		_death_anim_phase = 1
		_death_anim_timer = 3.5  # 래그돌(~1.6) + 정착(0.35) + 녹아내림(1.0) + 여유
	# 조작 가능한 피어만 카드 UI
	if is_controllable() and not _death_by_oob:
		_picking_card = true
		var offered := CardDB.draw_three()
		card_offered.emit(self, offered)


func _tick_respawn(delta: float) -> void:
	# 사망 애니메이션 처리
	if _death_anim_phase > 0:
		_tick_death_anim(delta)
		return
	if not is_controllable():
		return
	if _picking_card:
		return  # 카드 고를 때까지 리스폰 대기
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		if Network.is_online():
			_apply_respawn.rpc(spawn_position)
		else:
			_apply_respawn(spawn_position)


## ── 사망 애니메이션 ─────────────────────────────────────────

func _tick_death_anim(delta: float) -> void:
	_death_anim_timer -= delta
	if _death_anim_timer <= 0.0:
		_death_anim_phase = 0
		_respawn_timer = 0.4


func _spawn_death_effect() -> void:
	# 각 신체 부위의 텍스처, 로컬 오프셋(Silhouette 기준), 글로벌 정보 수집
	var parts_info: Array = []
	var sprite_list: Array = [
		{"sprite": head, "pivot": head_pivot},
		{"sprite": neck, "pivot": neck_pivot},
		{"sprite": torso, "pivot": torso_pivot},
		{"sprite": arm_l, "pivot": arm_pivot_l},
		{"sprite": arm_r, "pivot": arm_pivot_r},
		{"sprite": leg_l, "pivot": leg_pivot_l},
		{"sprite": leg_r, "pivot": leg_pivot_r},
	]
	for part in sprite_list:
		var spr: Sprite2D = part["sprite"]
		if spr and spr.texture:
			parts_info.append({
				"texture": spr.texture,
				"global_pos": spr.global_position,
				"global_rot": spr.global_rotation,
				"local_offset": spr.position,  # pivot 기준 오프셋
				"pivot_offset": part["pivot"].position,  # silhouette 기준 오프셋
			})

	# 바닥 Y: 플레이어 충돌 셰이프 하단 (대략 +19px)
	var floor_y: float = _death_pos.y + 19.0

	var fx := DeathEffect.new()
	fx.init_data = {
		"parts": parts_info,
		"color": _death_color,
		"floor_y": floor_y,
		"facing": facing,
		"body_pos": _death_pos,
		"hit_pos": _last_hit_pos,
		"hit_dir": _last_hit_dir,
		"silhouette_scale_x": silhouette.scale.x,
		"player_velocity": _death_vel,
		"was_grounded": _death_grounded,
		"bullet_force": _last_bullet_force,
	}
	get_tree().current_scene.add_child(fx)


@rpc("authority", "call_local", "reliable")
func _apply_respawn(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	is_alive = true
	visible = true
	_death_by_oob = false
	_immunity_timer = RESPAWN_IMMUNITY
	_death_anim_phase = 0
	silhouette.rotation = 0.0
	silhouette.scale = Vector2(_facing_visual, 1.0)
	modulate = Color.WHITE
	_update_color()  # 사망 애니메이션에서 변경된 색상/투명도 완전 복원
	_refill_ammo()
	hit_area.set_deferred("monitoring", true)
	hit_area.set_deferred("monitorable", true)


## game.gd 가 리더 위치 기준으로 계산해서 리스폰 좌표를 갱신
func set_respawn_position(pos: Vector2) -> void:
	spawn_position = pos


func on_card_selected(card_id: String) -> void:
	_picking_card = false
	if Network.is_online():
		_apply_card.rpc(card_id)
	else:
		_apply_card(card_id)


@rpc("authority", "call_local", "reliable")
func _apply_card(card_id: String) -> void:
	cards.append(card_id)
	_update_card_count()
	_recalculate_gun_stats()
	_build_ammo_dots()   # 도트 수 갱신 (탄창 카드 반영)


## ── 피격 판정 ────────────────────────────────────────────────

func _on_hit_area_area_entered(area: Area2D) -> void:
	if not is_alive:
		return
	if has_respawn_immunity():
		return
	if not area.has_meta("bullet_shooter"):
		return
	var shooter_id: int = area.get_meta("bullet_shooter")
	if shooter_id == player_id:
		return
	if is_controllable():
		# 총알 피격 정보 캡처 (사망 이펙트용)
		_last_hit_pos = area.global_position
		if "velocity_vec" in area and area.velocity_vec.length() > 0.1:
			_last_hit_dir = area.velocity_vec.normalized()
		else:
			_last_hit_dir = Vector2.RIGHT * float(sign(area.global_position.x - global_position.x))
		# 총알 충격력 계산 (속도 × 크기 기반, 1.0 = 기본 총알)
		_last_bullet_force = 1.0
		if "velocity_vec" in area:
			_last_bullet_force = area.velocity_vec.length() / 480.0
		_last_bullet_force *= area.scale.x
		_last_bullet_force = clampf(_last_bullet_force, 0.3, 5.0)
		_death_by_oob = false
		_request_die(shooter_id)
		area.queue_free()


## ── 발사 ─────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func _fire_bullet(pos: Vector2, angle: float, shooter_id: int, card_ids: Array) -> void:
	_spawn_local_bullet(pos, angle, shooter_id, card_ids)


func _spawn_local_bullet(pos: Vector2, angle: float, sid: int, card_ids: Array) -> void:
	var stats: Dictionary = CardDB.compute_bullet_stats(card_ids)
	# 메인 탄
	_create_single_bullet(pos, angle, sid, stats)
	# 산탄 추가 발사 (부채꼴)
	var extra: int = int(stats.get("extra_shots", 0))
	if extra > 0:
		var spread_step := 0.18  # ~10° 간격
		for i in extra:
			var idx: int = (i / 2) + 1
			var sign_f: float = 1.0 if (i % 2 == 0) else -1.0
			var offset_angle: float = spread_step * float(idx) * sign_f
			_create_single_bullet(pos, angle + offset_angle, sid, stats)


func _create_single_bullet(pos: Vector2, angle: float, sid: int, stats: Dictionary) -> void:
	var b := BULLET_SCENE.instantiate()
	# add_child 가 되어야 @onready 가 채워지므로 setup 은 트리 진입 뒤에 호출
	get_tree().current_scene.add_child(b)
	var offset_dist: float = 28.0 * float(stats.get("size_mult", 1.0))
	b.global_position = pos + Vector2.RIGHT.rotated(angle) * offset_dist
	b.setup(angle, sid, stats)


## ── 승리 ─────────────────────────────────────────────────────

func _announce_win_local_or_rpc(winner_id: int) -> void:
	if Network.is_online():
		_announce_win.rpc(winner_id)
	else:
		_announce_win(winner_id)


@rpc("any_peer", "call_local", "reliable")
func _announce_win(winner_id: int) -> void:
	player_won.emit(winner_id)