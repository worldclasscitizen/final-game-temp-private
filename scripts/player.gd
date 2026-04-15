extends CharacterBody2D
## 플레이어 — 스프라이트시트 애니메이션 + 자유 조준 총기
##
## 입력 스킴 (InputScheme):
##   ONLINE   — 멀티플레이어. 자기 peer 만 입력 처리.
##   LOCAL_P1 — WASD + 마우스 + F/좌클릭.
##   LOCAL_P2 — 화살표 + `,`/`.` + `/`.
##
## 비주얼:
##   AnimatedSprite2D  — 몸체 (idle, run, jump, fall, death, hurt)
##   GunPivot (Node2D) — 조준 회전 피벗
##     └─ Pistol (Sprite2D) — aim_angle 로 회전
##   방향 전환: AnimatedSprite2D.flip_h
##   총은 독립 회전 → 마우스 조준 자유로움

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

# ── 스프라이트시트 텍스처 ──
const TEX_IDLE  := preload("res://assets/sprites/character/idle.png")
const TEX_RUN   := preload("res://assets/sprites/character/run.png")
const TEX_JUMP  := preload("res://assets/sprites/character/jump.png")
const TEX_FALL  := preload("res://assets/sprites/character/fall.png")
const TEX_DEATH := preload("res://assets/sprites/character/death.png")
const TEX_HURT  := preload("res://assets/sprites/character/hurt.png")
const TEX_PISTOL := preload("res://assets/sprites/character/pistol.png")

const SHOT_INTERVAL := 0.10
const BASE_RELOAD_TIME := 1.2
const BASE_MAG_SIZE := 1
const P2_AIM_TILT := PI / 6
const RESPAWN_IMMUNITY := 1.0


# ── 스프라이트 기준점 (64x64 프레임 내 캐릭터 발 중심) ──
const CHAR_FEET_X := 29   # 프레임 내 캐릭터 X 중심
const CHAR_FEET_Y := 63   # 프레임 내 캐릭터 발 바닥
const FRAME_SIZE := 64

# ── 총 마운트 위치 (캐릭터 발 기준 상대 좌표) ──
const GUN_MOUNT_X := 3.0    # 몸 중심에서 오른쪽 (facing right)
const GUN_MOUNT_Y := -20.0  # 발에서 위쪽 (어깨/팔 높이)
const GUN_MUZZLE_DIST := 12.0  # 총구까지 거리 (피벗에서)

@export var player_id: int = 1
@export var spawn_position: Vector2
@export var goal_x: float
@export var goal_direction: int = 1
@export var input_scheme: int = InputScheme.ONLINE

@export var aim_angle: float = 0.0
@export var facing: int = 1
@export var is_alive: bool = true

var cards: Array[String] = []

var _shot_timer := 0.0
var _respawn_timer := 0.0
var _picking_card := false
var _death_by_oob := false
var _immunity_timer := 0.0

# ── 탄창 시스템 ──
var _mag_size: int = BASE_MAG_SIZE
var _ammo: int = BASE_MAG_SIZE
var _reloading := false
var _reload_timer := 0.0
var _reload_duration: float = BASE_RELOAD_TIME
var _ammo_dots: Array[ColorRect] = []
var _reload_bar_bg: ColorRect
var _reload_bar_fill: ColorRect

var _was_on_floor := true

# ── 사망 애니메이션 ──
var _death_anim_timer := 0.0
var _death_anim_phase := 0
var _death_pos := Vector2.ZERO
var _death_color := Color.WHITE
var _last_hit_pos := Vector2.ZERO
var _last_hit_dir := Vector2.RIGHT
var _last_bullet_force := 1.0
var _death_vel := Vector2.ZERO
var _death_grounded := true

# ── 비주얼 노드 (코드에서 생성) ──
var _body: AnimatedSprite2D
var _gun_pivot: Node2D
var _gun_sprite: Sprite2D
var _anim_state: String = "idle"

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
	_setup_body_sprite()
	_setup_gun()
	_update_color()
	_update_card_count()
	hit_area.area_entered.connect(_on_hit_area_area_entered)
	_recalculate_gun_stats()
	_build_ammo_dots()
	_build_reload_bar()


## ── 몸체 스프라이트 설정 ─────────────────────────────────────
func _setup_body_sprite() -> void:
	_body = AnimatedSprite2D.new()
	_body.name = "Body"
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 프레임 중심이 아닌 발 중심 기준으로 오프셋
	_body.centered = false
	_body.offset = Vector2(-CHAR_FEET_X, -CHAR_FEET_Y)

	var frames := SpriteFrames.new()

	# idle: 4 frames, 10 fps
	_add_sheet_anim(frames, "idle", TEX_IDLE, 4, 10.0, true)
	# run: 7 frames, 12 fps
	_add_sheet_anim(frames, "run", TEX_RUN, 7, 12.0, true)
	# jump: 1 frame
	_add_sheet_anim(frames, "jump", TEX_JUMP, 1, 5.0, false)
	# fall: 1 frame
	_add_sheet_anim(frames, "fall", TEX_FALL, 1, 5.0, false)
	# death: 6 frames, 8 fps
	_add_sheet_anim(frames, "death", TEX_DEATH, 6, 8.0, false)
	# hurt: 2 frames, 6 fps
	_add_sheet_anim(frames, "hurt", TEX_HURT, 2, 6.0, false)

	_body.sprite_frames = frames
	_body.play("idle")
	add_child(_body)
	# 몸체를 충돌 셰이프 뒤에 그리기
	move_child(_body, 0)


func _add_sheet_anim(frames: SpriteFrames, anim_name: String,
		sheet_tex: Texture2D, frame_count: int, fps: float, loop: bool) -> void:
	if anim_name != "default":
		frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, loop)
	var sheet_w: int = sheet_tex.get_width()
	var fw: int = sheet_w / frame_count
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet_tex
		atlas.region = Rect2(i * fw, 0, fw, sheet_tex.get_height())
		frames.add_frame(anim_name, atlas)


## ── 총기 설정 ────────────────────────────────────────────────
func _setup_gun() -> void:
	# 총 회전 피벗 (캐릭터 팔 위치)
	_gun_pivot = Node2D.new()
	_gun_pivot.name = "GunPivot"
	_gun_pivot.position = Vector2(GUN_MOUNT_X, GUN_MOUNT_Y)
	add_child(_gun_pivot)

	# 총 스프라이트 (수평 방향, 그립이 왼쪽=피벗 근처)
	_gun_sprite = Sprite2D.new()
	_gun_sprite.name = "Pistol"
	_gun_sprite.texture = TEX_PISTOL
	_gun_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_gun_sprite.centered = false
	# 총 스프라이트는 64x64 프레임 안에 13x5 콘텐츠가 (29,41)에 있음
	# 그립 중심을 피벗에 맞추기 위한 오프셋
	_gun_sprite.region_enabled = true
	_gun_sprite.region_rect = Rect2(29, 41, 13, 5)
	_gun_sprite.offset = Vector2(0, -2)  # 수직 중앙 정렬 (5px 높이의 절반)
	_gun_pivot.add_child(_gun_sprite)


## ── 색상 (P1/P2 구분) ───────────────────────────────────────
func _update_color() -> void:
	if _body:
		if player_id == 1:
			_body.self_modulate = Color(0.85, 0.92, 1.0)  # P1: 약간 푸른 톤
		else:
			_body.self_modulate = Color(1.0, 0.82, 0.75)  # P2: 약간 따뜻한 톤
	modulate = Color.WHITE
	self_modulate = Color.WHITE
	_set_light_mask_recursive(self, 0)


func _set_light_mask_recursive(node: Node, mask: int) -> void:
	if node is CanvasItem:
		(node as CanvasItem).light_mask = mask
	for child in node.get_children():
		if child is CanvasItem:
			_set_light_mask_recursive(child, mask)


func _update_card_count() -> void:
	card_count_label.text = "card x%d" % cards.size() if cards.size() > 0 else ""


func is_controllable() -> bool:
	if Network.is_local():
		return input_scheme == InputScheme.LOCAL_P1 or input_scheme == InputScheme.LOCAL_P2
	return is_multiplayer_authority()


func _physics_process(delta: float) -> void:
	if _immunity_timer > 0.0:
		_immunity_timer = max(0.0, _immunity_timer - delta)
		modulate.a = 0.5 if int(_immunity_timer * 10) % 2 == 0 else 1.0
	else:
		modulate.a = 1.0

	if not is_alive:
		_tick_respawn(delta)
		return

	if is_controllable():
		_handle_input(delta)

	_update_animation(delta)


func has_respawn_immunity() -> bool:
	return _immunity_timer > 0.0


func _handle_input(delta: float) -> void:
	if _picking_card:
		return

	var dir := _get_move_axis()
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * SPEED, ACCEL * delta)
		if input_scheme == InputScheme.LOCAL_P2:
			facing = int(sign(dir))
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

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
		var shoot_pos := _gun_pivot.global_position + Vector2.RIGHT.rotated(aim_angle) * GUN_MUZZLE_DIST
		var cards_snapshot := cards.duplicate()
		if Network.is_online():
			_fire_bullet.rpc(shoot_pos, aim_angle, player_id, cards_snapshot)
		else:
			_spawn_local_bullet(shoot_pos, aim_angle, player_id, cards_snapshot)
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


## ── 탄약 도트 (총 위 노란 원형) ──────────────────────────────

const AMMO_DOT_SZ := 2.0
const AMMO_DOT_GAP := 1.0
const AMMO_COLS := 5

func _build_ammo_dots() -> void:
	for dot in _ammo_dots:
		if is_instance_valid(dot):
			dot.queue_free()
	_ammo_dots.clear()
	if not is_instance_valid(_gun_pivot):
		return
	var count: int = _mag_size
	if count <= 0:
		return
	var step: float = AMMO_DOT_SZ + AMMO_DOT_GAP
	for i in count:
		var col: int = i % AMMO_COLS
		var row: int = i / AMMO_COLS
		var dot := ColorRect.new()
		dot.size = Vector2(AMMO_DOT_SZ, AMMO_DOT_SZ)
		# 총 위에 배치 (피벗 기준 오프셋)
		dot.position = Vector2(
			3.0 + float(col) * step,
			-5.0 - float(row) * step
		)
		dot.color = Color(0.95, 0.82, 0.35, 0.9)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gun_pivot.add_child(dot)
		_ammo_dots.append(dot)
	_update_ammo_dots()


func _update_ammo_dots() -> void:
	for i in _ammo_dots.size():
		if i < _ammo_dots.size() and is_instance_valid(_ammo_dots[i]):
			_ammo_dots[i].visible = (i < _ammo)


## ── 리로드 게이지 바 ─────────────────────────────────────────

const RELOAD_BAR_W := 24.0
const RELOAD_BAR_H := 3.0

func _build_reload_bar() -> void:
	_reload_bar_bg = ColorRect.new()
	_reload_bar_bg.size = Vector2(RELOAD_BAR_W, RELOAD_BAR_H)
	_reload_bar_bg.position = Vector2(-RELOAD_BAR_W * 0.5, -28.0)
	_reload_bar_bg.color = Color(0.2, 0.2, 0.2, 0.7)
	_reload_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reload_bar_bg.visible = false
	add_child(_reload_bar_bg)
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

func _update_animation(_delta: float) -> void:
	var grounded := is_on_floor()
	var running := grounded and absf(velocity.x) > 30.0
	_was_on_floor = grounded

	# ── 방향 (flip) ──
	# 캐릭터 발 중심이 프레임 내 x=29 (비대칭)이므로
	# flip_h 시 오프셋을 보정해 시각적 중심을 유지한다.
	if _body:
		_body.flip_h = (facing < 0)
		if facing < 0:
			_body.offset.x = -(FRAME_SIZE - 1 - CHAR_FEET_X)
		else:
			_body.offset.x = -CHAR_FEET_X

	# ── 총 피벗 위치 + 회전 ──
	if _gun_pivot:
		_gun_pivot.position.x = GUN_MOUNT_X * float(facing)
		_gun_pivot.rotation = aim_angle
		if _gun_sprite:
			_gun_sprite.flip_v = (facing < 0)

	# ── 애니메이션 상태 전환 ──
	var new_state: String
	if not grounded:
		new_state = "jump" if velocity.y < 0.0 else "fall"
	elif running:
		new_state = "run"
	else:
		new_state = "idle"

	if new_state != _anim_state:
		_anim_state = new_state
		if _body and _body.sprite_frames and _body.sprite_frames.has_animation(_anim_state):
			_body.play(_anim_state)


## ── OOB 킬 ──────────────────────────────────────────────────

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

	if _death_by_oob:
		visible = false
		_respawn_timer = 1.0
	else:
		_death_pos = global_position
		# 사망 애니메이션 재생
		if _body and _body.sprite_frames and _body.sprite_frames.has_animation("death"):
			_body.play("death")
		if _gun_pivot:
			_gun_pivot.visible = false
		_death_anim_phase = 1
		_death_anim_timer = 2.5

	if is_controllable() and not _death_by_oob:
		_picking_card = true
		var offered := CardDB.draw_three()
		card_offered.emit(self, offered)


func _tick_respawn(delta: float) -> void:
	if _death_anim_phase > 0:
		_tick_death_anim(delta)
		return
	if not is_controllable():
		return
	if _picking_card:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		if Network.is_online():
			_apply_respawn.rpc(spawn_position)
		else:
			_apply_respawn(spawn_position)


func _tick_death_anim(delta: float) -> void:
	_death_anim_timer -= delta
	# 사망 애니메이션 중 페이드아웃
	if _death_anim_timer < 1.0:
		modulate.a = maxf(0.0, _death_anim_timer)
	if _death_anim_timer <= 0.0:
		_death_anim_phase = 0
		visible = false
		_respawn_timer = 0.4


@rpc("authority", "call_local", "reliable")
func _apply_respawn(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	is_alive = true
	visible = true
	_death_by_oob = false
	_immunity_timer = RESPAWN_IMMUNITY
	_death_anim_phase = 0
	_was_on_floor = true
	if _body:
		_body.rotation = 0.0
		_body.play("idle")
	if _gun_pivot:
		_gun_pivot.visible = true
	_anim_state = "idle"
	modulate = Color.WHITE
	_update_color()
	_refill_ammo()
	hit_area.set_deferred("monitoring", true)
	hit_area.set_deferred("monitorable", true)


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
	_build_ammo_dots()


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
		_last_hit_pos = area.global_position
		if "velocity_vec" in area and area.velocity_vec.length() > 0.1:
			_last_hit_dir = area.velocity_vec.normalized()
		else:
			_last_hit_dir = Vector2.RIGHT * float(sign(area.global_position.x - global_position.x))
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
	_create_single_bullet(pos, angle, sid, stats)
	var extra: int = int(stats.get("extra_shots", 0))
	if extra > 0:
		var spread_step := 0.18
		for i in extra:
			var idx: int = (i / 2) + 1
			var sign_f: float = 1.0 if (i % 2 == 0) else -1.0
			var offset_angle: float = spread_step * float(idx) * sign_f
			_create_single_bullet(pos, angle + offset_angle, sid, stats)


func _create_single_bullet(pos: Vector2, angle: float, sid: int, stats: Dictionary) -> void:
	var b := BULLET_SCENE.instantiate()
	get_tree().current_scene.add_child(b)
	var offset_dist: float = 20.0 * float(stats.get("size_mult", 1.0))
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
