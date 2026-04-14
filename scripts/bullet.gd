extends Area2D
## 총알 — 통합 물리 모델.
##
## 설계 의도:
##   기본 총알은 약하다. 짧은 추력(thrust) 이후 중력과 공기저항에 의해
##   자연스럽게 호를 그리며 떨어진다. 카드 강화 없이는 먼 적에게 닿기 어렵다.
##
## 물리 모델 (매 프레임 동시 적용):
##   1) 추력 — 발사 방향으로 가속. 지속시간의 마지막 35% 동안 부드럽게 감쇠.
##   2) 중력 — 항상 적용. 아래로 끌어당김.
##   3) 공기저항 — 항상 적용. 수평은 강한 감쇠, 수직은 약한 감쇠.
##      → 중력 가속도가 제대로 붙어서, 위로 쏜 탄이 떨어질 때 빠르게 내려옴.
##   추력이 줄어들수록 중력과 드래그가 지배적이 되어 탄이 자연스럽게 꺼진다.
##
## 카드 효과:
##   speed_mult / size_mult / homing / bounces / pierces (기존)
##   thrust_time_add / gravity_scale_add / drag_scale_add (확장)

const BASE_SPEED := 780.0
const GRAVITY := 980.0
const DRAG := 1.6
const VERT_DRAG_RATIO := 0.3   # 수직 드래그 비율 (중력 가속 허용)
const THRUST_FORCE := 850.0    # 초반 직진 유지 (너무 강하지 않게)
const THRUST_DURATION := 0.35  # 추력 지속 시간
const THRUST_FADE_RATIO := 0.45  # 추력 마지막 45% 에서 페이드아웃
const GRAVITY_SUPPRESS := 0.08  # 추력 활성 중 중력 억제 비율 (8%만 적용)
const GRAVITY_RAMP_TIME := 0.20 # 추력 종료 후 중력이 100%까지 올라가는 시간

# OOB 안전 삭제 (맵 범위를 크게 벗어났을 때만)
const OOB_MARGIN := 800.0
const OOB_Y_TOP := -600.0
const OOB_Y_BOTTOM := 2000.0

# 충격 이펙트
const IMPACT_PARTICLE_COUNT := 6
const IMPACT_PARTICLE_SPEED := 120.0
const IMPACT_LIFETIME := 0.25

var velocity_vec: Vector2
var _thrust_timer: float
var _total_thrust: float
var _thrust_dir: Vector2  # 발사 시 고정되는 추력 방향
var _gravity_scale: float = 1.0
var _drag_scale: float = 1.0
var _post_thrust_time: float = 0.0  # 추력 종료 후 경과 시간

var speed: float = BASE_SPEED
var homing: float = 0.0
var bounces_remaining: int = 0
var pierces_remaining: int = 0
var shooter_id: int = 0

@onready var sprite: Sprite2D = $Sprite
@onready var shape: CollisionShape2D = $CollisionShape2D


func setup(angle: float, _shooter_id: int, stats: Dictionary) -> void:
	shooter_id = _shooter_id
	speed = BASE_SPEED * float(stats.get("speed_mult", 1.0))
	homing = float(stats.get("homing", 0.0))
	bounces_remaining = int(stats.get("bounces", 0))
	pierces_remaining = int(stats.get("pierces", 0))
	_total_thrust = THRUST_DURATION + float(stats.get("thrust_time_add", 0.0))
	_thrust_timer = _total_thrust
	_gravity_scale = maxf(0.0, 1.0 + float(stats.get("gravity_scale_add", 0.0)))
	_drag_scale = maxf(0.1, 1.0 + float(stats.get("drag_scale_add", 0.0)))

	velocity_vec = Vector2.RIGHT.rotated(angle) * speed
	_thrust_dir = Vector2.RIGHT.rotated(angle)
	rotation = angle

	var size_mult: float = float(stats.get("size_mult", 1.0))
	scale = Vector2.ONE * size_mult

	set_meta("bullet_shooter", _shooter_id)
	# P1: 형광 오렌지-옐로우 / P2: 형광 코랄-핑크
	sprite.modulate = Color(0.92, 0.75, 0.24) if _shooter_id == 1 else Color(0.86, 0.37, 0.33)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	# ── 유도 (추력 활성 중에만 의미가 있음) ──
	if homing > 0.0 and _thrust_timer > 0.0:
		_apply_homing(delta)

	# ── 추력 (부드러운 페이드아웃) ──
	var thrusting := _thrust_timer > 0.0
	if thrusting:
		var power: float = 1.0
		var fade_start: float = _total_thrust * THRUST_FADE_RATIO
		if _thrust_timer < fade_start and fade_start > 0.01:
			power = _thrust_timer / fade_start
		velocity_vec += _thrust_dir * THRUST_FORCE * power * delta
		_thrust_timer -= delta
	else:
		_post_thrust_time += delta

	# ── 중력 (추력 중 억제 → 종료 후 점진적 증가) ──
	var gravity_ratio: float
	if thrusting:
		gravity_ratio = GRAVITY_SUPPRESS  # 추력 중: 5%만 적용
	elif _post_thrust_time < GRAVITY_RAMP_TIME:
		# 추력 종료 직후: 0.05 → 1.0 으로 부드럽게 증가
		var ramp_t: float = _post_thrust_time / GRAVITY_RAMP_TIME
		gravity_ratio = lerpf(GRAVITY_SUPPRESS, 1.0, ramp_t * ramp_t)
	else:
		gravity_ratio = 1.0
	velocity_vec.y += GRAVITY * _gravity_scale * gravity_ratio * delta

	# ── 공기저항 (수평 강하게, 수직 약하게 → 중력 가속도가 제대로 붙음) ──
	var drag_factor := DRAG * _drag_scale * delta
	velocity_vec.x *= exp(-drag_factor)
	velocity_vec.y *= exp(-drag_factor * VERT_DRAG_RATIO)

	# ── 이동 ──
	position += velocity_vec * delta
	rotation = velocity_vec.angle()

	# ── OOB 안전 삭제 (맵 밖으로 크게 벗어난 경우만) ──
	if position.y > OOB_Y_BOTTOM or position.y < OOB_Y_TOP:
		queue_free()
	elif position.x < -OOB_MARGIN or position.x > 14000.0:
		queue_free()


func _apply_homing(delta: float) -> void:
	var target: Node2D = _find_target()
	if not target:
		return
	var desired := (target.global_position - global_position).angle()
	var current := velocity_vec.angle()
	var diff := wrapf(desired - current, -PI, PI)
	var max_turn := homing * delta
	var turn := clampf(diff, -max_turn, max_turn)
	velocity_vec = velocity_vec.rotated(turn)
	# 추력 방향도 같이 돌린다 (유도 중 추력이 엉뚱한 곳을 향하지 않도록)
	_thrust_dir = _thrust_dir.rotated(turn)


func _find_target() -> Node2D:
	var players_root := get_tree().current_scene.get_node_or_null("Players")
	if not players_root:
		return null
	var best: Node2D = null
	var best_dist := INF
	for p in players_root.get_children():
		if not (p is Node2D):
			continue
		if "player_id" in p and p.player_id == shooter_id:
			continue
		if "is_alive" in p and not p.is_alive:
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


## ── 벽 충돌 / 반사 / 관통 ───────────────────────────────────

func _on_body_entered(body: Node) -> void:
	if not (body is StaticBody2D or body is TileMap):
		return

	var normal := _estimate_collision_normal(body)

	if pierces_remaining > 0:
		pierces_remaining -= 1
		_spawn_impact(global_position, normal, 0.5)  # 관통 시 약한 이펙트
		position += velocity_vec.normalized() * 8.0
		return

	if bounces_remaining > 0:
		bounces_remaining -= 1
		_spawn_impact(global_position, normal, 0.7)  # 반사 시 중간 이펙트
		_bounce_off_with_normal(body, normal)
		return

	_spawn_impact(global_position, normal, 1.0)  # 소멸 시 풀 이펙트
	queue_free()


func _bounce_off_with_normal(_body: Node, normal: Vector2) -> void:
	# 법선 반대 방향으로 이동 중이어야 반사가 의미 있음
	if velocity_vec.dot(normal) < 0.0:
		velocity_vec = velocity_vec.bounce(normal)
	else:
		# 이미 벽에서 멀어지는 중이면 속도는 유지, 위치만 밀어냄
		pass
	# 벽에서 밀어내서 재충돌 방지 (속도 비례로 좀 더 넉넉하게)
	position += normal * 12.0


## Ray-AABB 교차 기반 충돌면 법선 추정.
## 총알의 속도를 역추적하여 어떤 면을 먼저 관통했는지 계산한다.
## 침투 깊이 방식의 약점(고속 총알이 깊이 파고들면 오판)을 해결.
func _estimate_collision_normal(body: Node) -> Vector2:
	if body is StaticBody2D:
		var col := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if col and col.shape is RectangleShape2D:
			var half: Vector2 = col.shape.size * 0.5
			var body_pos: Vector2 = body.global_position
			# AABB 경계
			var box_left: float = body_pos.x - half.x
			var box_right: float = body_pos.x + half.x
			var box_top: float = body_pos.y - half.y
			var box_bottom: float = body_pos.y + half.y
			# 레이 원점: 현재 위치에서 속도 역방향으로 충분히 되돌림
			var dir: Vector2 = velocity_vec.normalized()
			var origin: Vector2 = global_position - dir * 40.0
			var normal := Vector2.ZERO
			var t_min := -INF
			# X축 교차
			if absf(dir.x) > 0.001:
				var t1: float = (box_left - origin.x) / dir.x
				var t2: float = (box_right - origin.x) / dir.x
				var t_enter: float = minf(t1, t2)
				if t_enter > t_min:
					t_min = t_enter
					normal = Vector2(-1.0, 0.0) if dir.x > 0.0 else Vector2(1.0, 0.0)
			# Y축 교차
			if absf(dir.y) > 0.001:
				var t1: float = (box_top - origin.y) / dir.y
				var t2: float = (box_bottom - origin.y) / dir.y
				var t_enter: float = minf(t1, t2)
				if t_enter > t_min:
					t_min = t_enter
					normal = Vector2(0.0, -1.0) if dir.y > 0.0 else Vector2(0.0, 1.0)
			if normal != Vector2.ZERO:
				return normal
	# fallback: 속도의 주된 성분 반대 방향
	if absf(velocity_vec.x) > absf(velocity_vec.y):
		return Vector2(-1.0 if velocity_vec.x > 0.0 else 1.0, 0.0)
	return Vector2(0.0, -1.0 if velocity_vec.y > 0.0 else 1.0)


## ── 충격 이펙트 ─────────────────────────────────────────────
## 총알이 벽/바닥에 닿았을 때 작은 파편이 법선 방향 반구로 퍼짐.
## intensity: 0.0~1.0 (관통=0.5, 반사=0.7, 소멸=1.0)

func _spawn_impact(pos: Vector2, normal: Vector2, intensity: float) -> void:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	var impact := _ImpactFX.new()
	impact.setup(pos, normal, sprite.modulate, intensity,
		IMPACT_PARTICLE_COUNT, IMPACT_PARTICLE_SPEED, IMPACT_LIFETIME)
	scene_root.add_child(impact)


## 충격 이펙트 노드: 법선 반구 방향으로 파편이 퍼지고, 섬광이 번쩍인 후 사라짐.
class _ImpactFX extends Node2D:
	var _particles: Array = []  # [{node, vel, life}]
	var _flash: ColorRect
	var _timer: float = 0.0
	var _max_life: float = 0.25

	func setup(pos: Vector2, normal: Vector2, bullet_color: Color, intensity: float,
			particle_count: int, particle_speed: float, lifetime: float) -> void:
		global_position = pos
		_max_life = lifetime * intensity

		# 섬광 (밝은 사각형, 빠르게 사라짐)
		_flash = ColorRect.new()
		var flash_size: float = 8.0 * intensity
		_flash.position = Vector2(-flash_size * 0.5, -flash_size * 0.5)
		_flash.size = Vector2(flash_size, flash_size)
		_flash.color = Color(1.0, 0.95, 0.8, 0.9)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_flash)

		# 파편 (법선 방향 반구로 퍼짐)
		var count: int = int(float(particle_count) * intensity)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var base_angle: float = normal.angle()
		for i in count:
			# 법선 중심으로 ±80° 범위 내 랜덤 방향
			var spread: float = rng.randf_range(-1.4, 1.4)  # ~±80°
			var dir := Vector2.RIGHT.rotated(base_angle + spread)
			var spd: float = particle_speed * rng.randf_range(0.4, 1.2) * intensity

			var p := ColorRect.new()
			var pw: float = rng.randf_range(1.5, 3.5)
			var ph: float = rng.randf_range(1.0, 2.5)
			p.position = Vector2(-pw * 0.5, -ph * 0.5)
			p.size = Vector2(pw, ph)
			# 파편 색: 총알색 + 약간 밝게/어둡게 변주
			var color_var: float = rng.randf_range(-0.15, 0.15)
			p.color = bullet_color.lightened(color_var) if color_var > 0.0 else bullet_color.darkened(-color_var)
			p.color.a = 1.0
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(p)
			_particles.append({"node": p, "vel": dir * spd, "life": _max_life * rng.randf_range(0.6, 1.0)})

	func _process(delta: float) -> void:
		_timer += delta

		# 섬광 페이드아웃
		if _flash:
			var flash_life: float = 0.08
			if _timer < flash_life:
				_flash.color.a = 0.9 * (1.0 - _timer / flash_life)
				var s: float = 1.0 + _timer / flash_life * 2.0
				_flash.scale = Vector2(s, s)
			else:
				_flash.queue_free()
				_flash = null

		# 파편 이동 + 페이드아웃
		var alive := false
		for pd in _particles:
			pd.life -= delta
			if pd.life <= 0.0:
				if is_instance_valid(pd.node):
					pd.node.visible = false
				continue
			alive = true
			var n: ColorRect = pd.node
			if is_instance_valid(n):
				n.position += pd.vel * delta
				# 중력
				pd.vel.y += 400.0 * delta
				# 페이드
				var ratio: float = pd.life / _max_life
				n.color.a = ratio
				# 축소
				n.scale = Vector2(ratio, ratio)

		if not alive and _flash == null:
			queue_free()
