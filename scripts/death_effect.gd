extends Node2D
## 사망 이펙트 v2 — 물리 기반 래그돌 + 관성·충격 반영 + 체형 기반 혈흔.
##
## init_data 필수 키:
##   parts, color, floor_y, facing, body_pos, hit_pos, hit_dir,
##   silhouette_scale_x, player_velocity, was_grounded, bullet_force
##
## process_mode = ALWAYS → 일시정지 중에도 재생.

# ── 물리 ──
const PHY_GRAVITY := 980.0
const PHY_BOUNCE := 0.25
const PHY_GROUND_DRAG := 4.0
const PHY_AIR_DRAG := 0.985
const PHY_ANG_DRAG := 0.93

# ── 타이밍 ──
const RAGDOLL_MAX := 1.6
const SETTLE_TIME := 0.35
const MELT_DELAY := 0.15
const MELT_DURATION := 0.85

# ── 피 튀김 (초기) ──
const SPLAT_COUNT := 14
const SPLAT_SPEED_MIN := 70.0
const SPLAT_SPEED_MAX := 200.0
const SPLAT_CONE := PI * 0.6

# ── 피 흘림 (지속) ──
const TRAIL_RATE := 35.0
const TRAIL_SPEED := 25.0

# ── 녹아내림 ──
const MELT_FLATTEN := 0.05
const MELT_SPREAD := 1.7
const MELT_DRIP_P := 18

# ── 영구 염색 ──
const PUDDLE_H := 3.0
const DRIP_MAX_LEN := 30.0
const DRIP_W := 2.0

## 호출측이 add_child 전에 채워 넣는 데이터.
var init_data: Dictionary = {}

# ── 내부: 데이터 ──
var _color: Color
var _floor_y: float
var _facing: int
var _body_pos: Vector2
var _hit_pos: Vector2
var _hit_dir: Vector2
var _player_vel: Vector2
var _was_grounded: bool
var _bullet_force: float
var _scale_x: float

# ── 내부: 물리 ──
var _body: Node2D
var _body_vel: Vector2
var _body_ang_vel: float = 0.0
var _grounded: bool = false

# ── 내부: 부위별 ──
var _parts: Array = []
var _sprites: Array[Sprite2D] = []
var _hit_idx: int = -1

# ── 내부: 페이즈 ──
var _phase: int = 0          # 0=ragdoll, 1=settle, 2=melt, 3=done
var _timer: float = 0.0
var _rag_t: float = 0.0

# ── 내부: 파티클 ──
var _splat: Array = []
var _melt_p: Array = []
var _trail_accum: float = 0.0

# ── 내부: 영구 염색 ──
var _stain_layer: Node2D
var _puddle_rects: Array = []
var _drip_rects: Array = []
var _stain_built: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# ── 데이터 읽기 ──
	_color       = init_data["color"]
	_floor_y     = init_data["floor_y"]
	_facing      = init_data["facing"]
	_body_pos    = init_data["body_pos"]
	_hit_pos     = init_data["hit_pos"]
	_hit_dir     = init_data["hit_dir"]
	_player_vel  = init_data.get("player_velocity", Vector2.ZERO)
	_was_grounded = init_data.get("was_grounded", true)
	_bullet_force = clampf(init_data.get("bullet_force", 1.0), 0.3, 5.0)
	_scale_x     = init_data.get("silhouette_scale_x", 1.0)

	# ── 영구 염색 레이어 ──
	_stain_layer = Node2D.new()
	_stain_layer.z_index = 0
	add_child(_stain_layer)

	# ── 몸체 그룹 ──
	_body = Node2D.new()
	add_child(_body)
	_body.global_position = _body_pos

	# ── 스프라이트 생성 + 피격 부위 판별 ──
	var pd_arr: Array = init_data["parts"]
	var min_d := INF
	for i in pd_arr.size():
		var pd: Dictionary = pd_arr[i]
		var spr := Sprite2D.new()
		spr.texture = pd["texture"]
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_body.add_child(spr)
		spr.global_position = pd["global_pos"]
		spr.global_rotation = pd["global_rot"]
		_sprites.append(spr)
		var d: float = pd["global_pos"].distance_to(_hit_pos)
		if d < min_d:
			min_d = d
			_hit_idx = i
		_parts.append({
			"spr": spr,
			"off_v": Vector2.ZERO,
			"off_p": Vector2.ZERO,
			"base": spr.position,
			"ang_v": 0.0,
			"rot_off": 0.0,
			"is_hit": false,
		})

	if _hit_idx >= 0:
		_parts[_hit_idx]["is_hit"] = true

	_init_physics()
	_phase = 0
	_timer = RAGDOLL_MAX
	_spawn_splatter()


# ══════════════════════════════════════════════════════════════
# 초기 물리 — 관성 + 충격 → 래그돌 운동량 결정
# ══════════════════════════════════════════════════════════════

func _init_physics() -> void:
	# 총알 충격 벡터
	var impact := _hit_dir * _bullet_force * 260.0

	if _was_grounded:
		# 지면: 달리기 관성(작게) + 총알 충격
		_body_vel = _player_vel * 0.35 + impact
		# 피격 높이 → 토크 (머리=크게 회전, 다리=작게)
		var hit_h := clampf((_body_pos.y - _hit_pos.y) / 20.0, -1.0, 1.0)
		_body_ang_vel = hit_h * _bullet_force * 3.5 * sign(_hit_dir.x)
	else:
		# 공중: 관성이 더 크고 회전도 더 많이
		_body_vel = _player_vel * 0.65 + impact
		_body_ang_vel = _hit_dir.x * _bullet_force * 5.0 + _player_vel.x * 0.005

	# 부위별 초기 개별 속도
	for i in _parts.size():
		var p: Dictionary = _parts[i]
		var dist := _sprites[i].global_position.distance_to(_hit_pos)
		var falloff := clampf(1.0 - dist / 45.0, 0.0, 1.0)
		if p["is_hit"]:
			# 맞은 부위: 총알 방향으로 강하게
			p["off_v"] = _hit_dir * _bullet_force * 55.0 + Vector2(randf_range(-12, 12), randf_range(-15, 5))
			p["ang_v"] = randf_range(-5, 5) * _bullet_force
		else:
			# 충격파 전파: 거리에 반비례
			p["off_v"] = _hit_dir * 18.0 * falloff * _bullet_force + Vector2(randf_range(-6, 6), randf_range(-8, 3))
			p["ang_v"] = randf_range(-1.5, 1.5) * falloff


func _process(delta: float) -> void:
	match _phase:
		0: _tick_ragdoll(delta)
		1: _tick_settle(delta)
		2: _tick_melt(delta)
		3: _finish()
	_tick_particles(delta)


# ══════════════════════════════════════════════════════════════
# Phase 0 — 래그돌: 관성+충격 기반 물리 쓰러짐
# ══════════════════════════════════════════════════════════════

func _tick_ragdoll(delta: float) -> void:
	_rag_t += delta
	_timer -= delta

	if not _grounded:
		# 중력 + 공기 저항
		_body_vel.y += PHY_GRAVITY * delta
		_body_vel *= PHY_AIR_DRAG
		_body_ang_vel *= PHY_ANG_DRAG

		_body.global_position += _body_vel * delta
		_body.rotation += _body_ang_vel * delta

		# 바닥 충돌
		if _body.global_position.y >= _floor_y:
			_body.global_position.y = _floor_y
			if absf(_body_vel.y) > 40.0:
				# 바운스
				_body_vel.y *= -PHY_BOUNCE
				_body_vel.x *= 0.7
				_body_ang_vel *= 0.4
				_spawn_ground_dust()
			else:
				# 착지 → 눕기
				_body_vel.y = 0.0
				_grounded = true
				var lie_dir: float = sign(_body_vel.x) if absf(_body_vel.x) > 5.0 else sign(_hit_dir.x)
				if lie_dir == 0.0:
					lie_dir = 1.0
				_body.rotation = lerpf(_body.rotation, (PI / 2.0) * lie_dir, 0.7)
				_body_ang_vel = 0.0
	else:
		# 지면 마찰
		_body_vel.x *= exp(-PHY_GROUND_DRAG * delta)
		_body.global_position.x += _body_vel.x * delta

	# 부위별 움직임
	_tick_part_offsets(delta)

	# 피 흘림 (지속적)
	if _hit_idx >= 0 and _rag_t < 1.2:
		_trail_accum += TRAIL_RATE * delta * _bullet_force
		while _trail_accum >= 1.0:
			_trail_accum -= 1.0
			_emit_trail()

	# 종료 조건: 착지 + 거의 멈춤, 또는 시간 초과
	if (_grounded and absf(_body_vel.x) < 8.0) or _timer <= 0.0:
		if not _grounded:
			_body.global_position.y = minf(_body.global_position.y, _floor_y)
			_grounded = true
			var lie_dir: float = sign(_hit_dir.x)
			if lie_dir == 0.0:
				lie_dir = 1.0
			_body.rotation = lerpf(_body.rotation, (PI / 2.0) * lie_dir, 0.7)
		_phase = 1
		_timer = SETTLE_TIME


func _tick_part_offsets(delta: float) -> void:
	for p in _parts:
		var spr: Sprite2D = p["spr"]
		if not is_instance_valid(spr):
			continue
		# 오프셋 물리: 빠른 감쇠 + 복원력
		p["off_v"] *= (1.0 - 4.5 * delta)
		if not _grounded:
			p["off_v"].y += 120.0 * delta
		p["off_p"] += p["off_v"] * delta
		p["off_p"] *= (1.0 - 2.0 * delta)
		# 회전 오프셋
		p["ang_v"] *= (1.0 - 3.5 * delta)
		p["rot_off"] += p["ang_v"] * delta
		p["rot_off"] *= (1.0 - 2.0 * delta)
		spr.position = p["base"] + p["off_p"]


func _emit_trail() -> void:
	if _hit_idx < 0 or _hit_idx >= _parts.size():
		return
	var spr: Sprite2D = _parts[_hit_idx]["spr"]
	if not is_instance_valid(spr):
		return
	var r := ColorRect.new()
	var sz := randf_range(1.0, 2.8)
	r.size = Vector2(sz, sz)
	r.color = _color.lightened(randf_range(-0.08, 0.1))
	r.color.a = randf_range(0.35, 0.65)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	r.global_position = spr.global_position + Vector2(randf_range(-4, 4), randf_range(-4, 4))
	_splat.append({
		"n": r,
		"v": Vector2(randf_range(-TRAIL_SPEED, TRAIL_SPEED), randf_range(-TRAIL_SPEED * 0.3, TRAIL_SPEED * 0.8)),
		"life": randf_range(0.25, 0.6), "ml": 0.6,
		"g": randf_range(180, 380), "stuck": false, "sz": sz,
	})


# ══════════════════════════════════════════════════════════════
# Phase 1 — 정착: 부위 안정화 + 체형 기반 혈흔
# ══════════════════════════════════════════════════════════════

func _tick_settle(delta: float) -> void:
	_timer -= delta
	for p in _parts:
		p["off_v"] *= (1.0 - 10.0 * delta)
		p["off_p"] *= (1.0 - 6.0 * delta)
		p["ang_v"] *= (1.0 - 10.0 * delta)
		p["rot_off"] *= (1.0 - 6.0 * delta)
		var spr: Sprite2D = p["spr"]
		if is_instance_valid(spr):
			spr.position = p["base"] + p["off_p"]

	if _timer <= 0.0:
		_phase = 2
		_timer = MELT_DELAY + MELT_DURATION
		_build_body_blood()


# ══════════════════════════════════════════════════════════════
# 체형 기반 혈흔 — 쓰러진 자세에 맞게 혈흔 생성
# ══════════════════════════════════════════════════════════════

func _build_body_blood() -> void:
	# 각 body part의 월드 위치 → 바닥 접촉 여부 판별
	var contact_xs: Array[float] = []
	var elevated: Array = []

	for spr in _sprites:
		if not is_instance_valid(spr):
			continue
		var gp := spr.global_position
		if gp.y >= _floor_y - 6.0:
			# 바닥 접촉 → 웅덩이 소스
			contact_xs.append(gp.x)
		else:
			# 공중 → 드립 소스
			elevated.append({"x": gp.x, "y": gp.y})

	# 접촉점 → 메인 웅덩이 (체형 전체 span)
	if contact_xs.size() > 0:
		contact_xs.sort()
		var min_x: float = contact_xs[0] - 8.0
		var max_x: float = contact_xs[contact_xs.size() - 1] + 8.0
		var puddle_w: float = clampf(max_x - min_x, 10.0, 80.0)
		var puddle := ColorRect.new()
		puddle.size = Vector2(0, PUDDLE_H)
		puddle.color = _color.darkened(0.2)
		puddle.color.a = 0.0
		puddle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stain_layer.add_child(puddle)
		puddle.global_position = Vector2(min_x, _floor_y - 1)
		_puddle_rects.append({"n": puddle, "tw": puddle_w, "x": min_x})

	# 개별 접촉점 → 서브 웅덩이 (체형 디테일)
	for cx in contact_xs:
		var sub := ColorRect.new()
		var sw := randf_range(5.0, 12.0)
		sub.size = Vector2(0, randf_range(2.0, 4.0))
		sub.color = _color.darkened(randf_range(0.15, 0.3))
		sub.color.a = 0.0
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stain_layer.add_child(sub)
		sub.global_position = Vector2(cx - sw * 0.5, _floor_y - 1 + randf_range(-1, 2))
		_puddle_rects.append({"n": sub, "tw": sw, "x": cx - sw * 0.5})

	# 공중 파트 → 바닥까지 세로 드립
	for e in elevated:
		if e["y"] > _floor_y - 3.0:
			continue
		var drip := ColorRect.new()
		drip.size = Vector2(DRIP_W, 0)
		drip.color = _color.darkened(randf_range(0.2, 0.4))
		drip.color.a = 0.0
		drip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stain_layer.add_child(drip)
		drip.global_position = Vector2(e["x"] + randf_range(-2, 2), e["y"])
		var max_len: float = _floor_y - float(e["y"])
		_drip_rects.append({
			"n": drip,
			"th": clampf(max_len, 3.0, DRIP_MAX_LEN),
			"del": randf_range(0.0, 0.25),
		})

	_stain_built = true


# ══════════════════════════════════════════════════════════════
# Phase 2 — 녹아내림 + 염색 애니메이션
# ══════════════════════════════════════════════════════════════

func _tick_melt(delta: float) -> void:
	_timer -= delta
	if _timer > MELT_DURATION:
		return

	var t := 1.0 - clampf(_timer / MELT_DURATION, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)   # smoothstep

	# 스프라이트 녹아내림
	for spr in _sprites:
		if not is_instance_valid(spr):
			continue
		spr.scale = Vector2(lerpf(1.0, MELT_SPREAD, e * 0.6), lerpf(1.0, MELT_FLATTEN, e))
		var at := clampf((t - 0.15) / 0.85, 0.0, 1.0)
		spr.modulate.a = lerpf(1.0, 0.0, at * at)

	# 녹는 파티클
	if t > 0.08 and t < 0.75:
		if randf() < delta * float(MELT_DRIP_P) / MELT_DURATION:
			_spawn_melt_drop()

	# 염색 애니메이션
	_anim_stain(clampf((t - 0.1) / 0.9, 0.0, 1.0))

	if _timer <= 0.0:
		_phase = 3


func _spawn_melt_drop() -> void:
	var src: Sprite2D = _sprites[randi() % _sprites.size()]
	if not is_instance_valid(src) or src.modulate.a < 0.15:
		return
	var r := ColorRect.new()
	var sz := randf_range(1.5, 3.0)
	r.size = Vector2(sz, sz)
	r.color = _color.lightened(randf_range(-0.05, 0.08))
	r.color.a = randf_range(0.3, 0.55)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	r.global_position = src.global_position + Vector2(randf_range(-5, 5), randf_range(-2, 2))
	_melt_p.append({
		"n": r,
		"v": Vector2(randf_range(-15, 15), randf_range(8, 30)),
		"life": randf_range(0.2, 0.45),
	})


func _anim_stain(t: float) -> void:
	# 웅덩이 확장
	for pr in _puddle_rects:
		var n: ColorRect = pr["n"]
		if not is_instance_valid(n):
			continue
		var w := lerpf(0.0, pr["tw"], 1.0 - pow(1.0 - t, 3.0))
		n.size.x = w
		n.color.a = lerpf(0.0, 0.5, minf(t * 3.0, 1.0))

	# 드립 성장
	for dd in _drip_rects:
		var n: ColorRect = dd["n"]
		if not is_instance_valid(n):
			continue
		var dl: float = dd["del"]
		var dt := clampf((t - dl) / maxf(1.0 - dl, 0.01), 0.0, 1.0)
		n.size.y = lerpf(0.0, dd["th"], 1.0 - (1.0 - dt) * (1.0 - dt))
		n.size.x = lerpf(DRIP_W, DRIP_W * 0.4, dt)
		n.color.a = lerpf(0.0, 0.45, minf(dt * 4.0, 1.0))


# ══════════════════════════════════════════════════════════════
# Phase 3 — 완료: 몸체 삭제, 영구 염색만 잔류
# ══════════════════════════════════════════════════════════════

func _finish() -> void:
	if is_instance_valid(_body):
		_body.queue_free()

	# 바닥에 붙은 피 파티클 → 영구 레이어로 이전
	for p in _splat:
		if not p["stuck"]:
			continue
		var node: ColorRect = p["n"]
		if not is_instance_valid(node):
			continue
		var gp := node.global_position
		var c := node.color
		var s := node.size
		node.queue_free()
		var st := ColorRect.new()
		st.size = s
		st.color = c
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stain_layer.add_child(st)
		st.global_position = gp

	# 영구 레이어 → scene root 로 이전
	if is_instance_valid(_stain_layer) and _stain_layer.get_parent() == self:
		remove_child(_stain_layer)
		get_tree().current_scene.add_child(_stain_layer)

	queue_free()


# ══════════════════════════════════════════════════════════════
# 피 튀김 (초기 — 총알 충격력에 비례)
# ══════════════════════════════════════════════════════════════

func _spawn_splatter() -> void:
	var base_a := _hit_dir.angle()
	var count := int(SPLAT_COUNT * clampf(_bullet_force, 0.8, 2.5))
	for i in count:
		var a := base_a + randf_range(-SPLAT_CONE * 0.5, SPLAT_CONE * 0.5)
		var spd := randf_range(SPLAT_SPEED_MIN, SPLAT_SPEED_MAX) * _bullet_force
		var sz := randf_range(1.2, 3.5) * clampf(_bullet_force, 0.8, 1.5)
		var c := _color.lightened(randf_range(-0.08, 0.12))
		c.a = randf_range(0.65, 1.0)
		var r := ColorRect.new()
		r.size = Vector2(sz, sz)
		r.color = c
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		r.global_position = _hit_pos + Vector2(randf_range(-2, 2), randf_range(-2, 2))
		_splat.append({
			"n": r, "v": Vector2(cos(a), sin(a)) * spd,
			"life": randf_range(0.3, 0.7), "ml": 0.7,
			"g": randf_range(200, 400), "stuck": false, "sz": sz,
		})


func _spawn_ground_dust() -> void:
	var ix := _body.global_position.x
	for i in 6:
		var a := -PI * 0.5 + randf_range(-PI * 0.35, PI * 0.35)
		var spd := randf_range(20, 65)
		var sz := randf_range(0.8, 2.0)
		var c := _color.darkened(randf_range(0.0, 0.3))
		c.a = randf_range(0.4, 0.7)
		var r := ColorRect.new()
		r.size = Vector2(sz, sz)
		r.color = c
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		r.global_position = Vector2(ix + randf_range(-12, 12), _floor_y)
		_splat.append({
			"n": r, "v": Vector2(cos(a), sin(a)) * spd,
			"life": randf_range(0.15, 0.35), "ml": 0.35,
			"g": 300.0, "stuck": false, "sz": sz,
		})


# ══════════════════════════════════════════════════════════════
# 파티클 물리
# ══════════════════════════════════════════════════════════════

func _tick_particles(delta: float) -> void:
	# ── 피 튀김 ──
	var rem: Array[int] = []
	for i in _splat.size():
		var p: Dictionary = _splat[i]
		if p["stuck"]:
			continue
		var n: ColorRect = p["n"]
		if not is_instance_valid(n):
			rem.append(i)
			continue
		p["life"] -= delta
		if p["life"] <= 0.0:
			p["stuck"] = true
			n.color.a = clampf(n.color.a, 0.2, 0.55)
			continue
		p["v"].y += p["g"] * delta
		n.global_position += p["v"] * delta
		if n.global_position.y >= _floor_y:
			n.global_position.y = _floor_y - randf_range(0, 1.0)
			p["stuck"] = true
			n.size.x = p["sz"] * randf_range(1.3, 2.2)
			n.size.y = p["sz"] * randf_range(0.3, 0.65)
			n.color.a = clampf(n.color.a, 0.2, 0.55)
			continue
		n.color.a = (p["life"] / p["ml"]) * 0.8

	for i in range(rem.size() - 1, -1, -1):
		_splat.remove_at(rem[i])

	# ── 녹아내림 파티클 ──
	var mrem: Array[int] = []
	for i in _melt_p.size():
		var p: Dictionary = _melt_p[i]
		var n: ColorRect = p["n"]
		if not is_instance_valid(n):
			mrem.append(i)
			continue
		p["life"] -= delta
		if p["life"] <= 0.0:
			n.queue_free()
			mrem.append(i)
			continue
		p["v"].y += 90.0 * delta
		p["v"] *= 0.97
		n.global_position += p["v"] * delta
		if n.global_position.y >= _floor_y:
			n.global_position.y = _floor_y
			p["v"] = Vector2.ZERO
		n.color.a = maxf(p["life"] / 0.5, 0.0) * 0.5

	for i in range(mrem.size() - 1, -1, -1):
		_melt_p.remove_at(mrem[i])
