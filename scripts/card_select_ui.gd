extends Control
## 카드 선택 UI v2 — 마우스 기반 프리미엄 연출.
##
## P1/온라인: 마우스 호버 + 클릭으로 선택
## P2 로컬: 키보드 7/8/9 로 선택 (호버 이펙트는 동일하게 동작)
##
## 호버: 부드러운 확대 + 올라감 + 에너지 테두리 일렁임 + 글로우 배경
## 선택: 펀치 확대 → 중앙 이동 → 빛줄기 + 파티클 폭발 → 페이드아웃

signal card_picked(card_id: String)

const CARD_W := 170.0
const CARD_H := 250.0
const CARD_GAP := 30.0
const CARD_BORDER := 3.0

# ── 호버 ──
const HOVER_SCALE := 1.08
const HOVER_LIFT := 16.0
const HOVER_LERP := 12.0
const SHIMMER_COUNT := 28
const SHIMMER_SPEED := 4.0
const SHIMMER_FLOAT := 5.0

# ── 선택 연출 ──
const PICK_SCALE := 1.38
const PICK_PUNCH := 1.52        # 오버슈트 최대
const PICK_ANIM_DURATION := 0.42
const GLOW_HOLD_DURATION := 0.55
const FINAL_FADE_DURATION := 0.30
const FLY_SPEED := 650.0

var _player: Node
var _card_ids: Array = []
var _card_roots: Array[Control] = []
var _card_states: Array = []     # 카드별 애니메이션 상태
var _is_p2_local := false
var _picked := false
var _picked_idx := -1
var _hovered_idx := -1
var _screen_w := 1400.0
var _screen_h := 800.0
var _time := 0.0

# 연출용 노드
var _rays_container: Control
var _particles: Array[Dictionary] = []
var _particle_canvas: Control
var _glow_rect: ColorRect
var _header_label: Label
var _picked_accent := Color.WHITE
var _anim_phase := 0   # 0=idle, 1=pick_move, 2=glow_hold, 3=fadeout
var _anim_timer := 0.0


func setup(player: Node, card_ids: Array) -> void:
	_player = player
	_card_ids = card_ids
	_is_p2_local = (
		Network.is_local()
		and "input_scheme" in player
		and player.input_scheme == player.InputScheme.LOCAL_P2
	)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vp := get_viewport_rect().size
	_screen_w = vp.x
	_screen_h = vp.y

	# ── 배경 딤 ──
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# ── 빛줄기 컨테이너 ──
	_rays_container = Control.new()
	_rays_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rays_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays_container.modulate.a = 0.0
	add_child(_rays_container)

	# ── 파티클 / 글로우 (나중에 add — 카드 위) ──
	_particle_canvas = Control.new()
	_particle_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_particle_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_particle_canvas.modulate.a = 0.0

	_glow_rect = ColorRect.new()
	_glow_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow_rect.color = Color(1, 0.9, 0.6, 0.0)
	_glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ── 헤더 ──
	var who: String
	if _is_p2_local:
		who = "P2"
	elif "input_scheme" in _player and _player.input_scheme == _player.InputScheme.LOCAL_P1:
		who = "P1"
	else:
		who = "당신"
	_header_label = Label.new()
	_header_label.text = "%s — 카드를 선택하세요" % who
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 22)
	_header_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))

	# ── 카드 배치 ──
	var total_w := CARD_W * 3.0 + CARD_GAP * 2.0
	var start_x := (_screen_w - total_w) * 0.5
	var hdr_h := 36.0
	var hdr_gap := 12.0
	var block_h := hdr_h + hdr_gap + CARD_H
	var block_top := (_screen_h - block_h) * 0.5
	if _is_p2_local:
		block_top = _screen_h * 0.5 + (_screen_h * 0.5 - block_h) * 0.5
	var card_y := block_top + hdr_h + hdr_gap

	_header_label.position = Vector2(0, block_top)
	_header_label.size = Vector2(_screen_w, hdr_h)
	add_child(_header_label)

	for i in 3:
		var data: Dictionary = CardDB.get_card(_card_ids[i])
		var cx := start_x + float(i) * (CARD_W + CARD_GAP)
		var card := _build_card(cx, card_y, data, i)
		add_child(card)
		_card_roots.append(card)
		var accent: Color = data.get("color", Color.WHITE)
		_card_states.append({
			"base_x": cx,
			"base_y": card_y,
			"accent": accent,
			"cur_scale": 1.0,
			"cur_lift": 0.0,
			"shimmer": [],
			"glow_bg": card.get_meta("glow_bg"),
			"card_bg": card.get_meta("card_bg"),
			"fly_vel": Vector2.ZERO,
			"fly_rot": 0.0,
		})

	for i in 3:
		_create_shimmer(i)

	add_child(_particle_canvas)
	add_child(_glow_rect)


# ══════════════════════════════════════════════════════════════
# 카드 빌드
# ══════════════════════════════════════════════════════════════

func _build_card(x: float, y: float, data: Dictionary, idx: int) -> Control:
	var accent: Color = data.get("color", Color.WHITE)

	var root := Control.new()
	root.position = Vector2(x, y)
	root.size = Vector2(CARD_W, CARD_H)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	root.set_meta("accent", accent)

	# 글로우 배경 (카드보다 약간 크게, 뒤에 깔림)
	var glow_expand := 10.0
	var glow_bg := ColorRect.new()
	glow_bg.position = Vector2(-glow_expand, -glow_expand)
	glow_bg.size = Vector2(CARD_W + glow_expand * 2, CARD_H + glow_expand * 2)
	glow_bg.color = Color(accent.r, accent.g, accent.b, 0.0)
	glow_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(glow_bg)
	root.set_meta("glow_bg", glow_bg)

	# 카드 배경
	var bg := ColorRect.new()
	bg.size = Vector2(CARD_W, CARD_H)
	bg.color = Color(0.10, 0.09, 0.13)
	root.add_child(bg)
	root.set_meta("card_bg", bg)

	# 테두리
	_add_border(root, accent)

	# 상단 이름
	var name_bg := ColorRect.new()
	name_bg.position = Vector2(CARD_BORDER, CARD_BORDER)
	name_bg.size = Vector2(CARD_W - CARD_BORDER * 2, 36)
	name_bg.color = accent.darkened(0.55)
	root.add_child(name_bg)

	var name_label := Label.new()
	name_label.text = data.get("name", "?")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", accent.lightened(0.35))
	name_label.position = Vector2(CARD_BORDER, CARD_BORDER)
	name_label.size = Vector2(CARD_W - CARD_BORDER * 2, 36)
	root.add_child(name_label)

	# 중앙 아이콘
	var icon_y := 44.0
	var icon_h := 100.0
	var diamond := Polygon2D.new()
	var ccx := CARD_W * 0.5
	var ccy := icon_y + icon_h * 0.5
	diamond.polygon = PackedVector2Array([
		Vector2(ccx, ccy - 44), Vector2(ccx + 44, ccy),
		Vector2(ccx, ccy + 44), Vector2(ccx - 44, ccy),
	])
	diamond.color = accent.darkened(0.35)
	root.add_child(diamond)

	var icon_label := Label.new()
	icon_label.text = data.get("icon", "?")
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 38)
	icon_label.add_theme_color_override("font_color", accent.lightened(0.5))
	icon_label.position = Vector2(CARD_BORDER, icon_y)
	icon_label.size = Vector2(CARD_W - CARD_BORDER * 2, icon_h)
	root.add_child(icon_label)

	# 구분선
	var sep := ColorRect.new()
	sep.position = Vector2(18, icon_y + icon_h + 4)
	sep.size = Vector2(CARD_W - 36, 1)
	sep.color = Color(accent.r, accent.g, accent.b, 0.35)
	root.add_child(sep)

	# 설명
	var desc := Label.new()
	desc.text = data.get("desc", "")
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.72, 0.72, 0.75))
	desc.position = Vector2(10, icon_y + icon_h + 8)
	desc.size = Vector2(CARD_W - 20, 56)
	root.add_child(desc)

	# P2 로컬만 키 힌트
	if _is_p2_local:
		var kl := Label.new()
		kl.text = "[%d]" % (idx + 7)
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kl.add_theme_font_size_override("font_size", 14)
		kl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
		kl.position = Vector2(0, CARD_H - 32)
		kl.size = Vector2(CARD_W, 24)
		root.add_child(kl)

	# 모서리 장식
	for corner in [Vector2(12, 48), Vector2(CARD_W - 28, CARD_H - 32)]:
		var mini := Label.new()
		mini.text = data.get("icon", "?")
		mini.add_theme_font_size_override("font_size", 12)
		mini.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.55))
		mini.position = corner
		mini.size = Vector2(16, 16)
		root.add_child(mini)

	# 인터랙션
	root.gui_input.connect(_on_card_input.bind(idx))
	root.mouse_entered.connect(_on_hover_enter.bind(idx))
	root.mouse_exited.connect(_on_hover_exit.bind(idx))

	return root


# ══════════════════════════════════════════════════════════════
# 에너지 테두리 (시머 파티클) 생성
# ══════════════════════════════════════════════════════════════

func _create_shimmer(card_idx: int) -> void:
	var card: Control = _card_roots[card_idx]
	var state: Dictionary = _card_states[card_idx]
	var accent: Color = state["accent"]
	var shimmer_arr: Array = []

	for i in SHIMMER_COUNT:
		var t := float(i) / float(SHIMMER_COUNT)
		var pos := _perimeter_pos(t)
		var nrm := _perimeter_normal(t)
		var sz := randf_range(2.0, 4.5)

		var r := ColorRect.new()
		r.size = Vector2(sz, sz)
		r.pivot_offset = Vector2(sz * 0.5, sz * 0.5)
		r.color = accent.lightened(0.3)
		r.color.a = 0.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.position = pos - Vector2(sz * 0.5, sz * 0.5)
		card.add_child(r)

		shimmer_arr.append({
			"node": r,
			"t": t,
			"base": pos,
			"normal": nrm,
			"size": sz,
		})

	state["shimmer"] = shimmer_arr


## 카드 테두리 위의 위치 (t ∈ [0,1])
func _perimeter_pos(t: float) -> Vector2:
	var perim := 2.0 * (CARD_W + CARD_H)
	var d := t * perim
	if d < CARD_W:
		return Vector2(d, 0)
	d -= CARD_W
	if d < CARD_H:
		return Vector2(CARD_W, d)
	d -= CARD_H
	if d < CARD_W:
		return Vector2(CARD_W - d, CARD_H)
	d -= CARD_W
	return Vector2(0, CARD_H - d)


## 카드 테두리의 바깥 방향 법선
func _perimeter_normal(t: float) -> Vector2:
	var perim := 2.0 * (CARD_W + CARD_H)
	var d := t * perim
	if d < CARD_W:
		return Vector2(0, -1)
	d -= CARD_W
	if d < CARD_H:
		return Vector2(1, 0)
	d -= CARD_H
	if d < CARD_W:
		return Vector2(0, 1)
	return Vector2(-1, 0)


# ══════════════════════════════════════════════════════════════
# 유틸: 테두리 / rect
# ══════════════════════════════════════════════════════════════

func _add_border(parent: Control, c: Color) -> void:
	var b := CARD_BORDER
	var w := CARD_W
	var h := CARD_H
	_rect(parent, 0, 0, w, b, c)
	_rect(parent, 0, h - b, w, b, c)
	_rect(parent, 0, b, b, h - b * 2, c)
	_rect(parent, w - b, b, b, h - b * 2, c)


func _rect(parent: Control, x: float, y: float, w: float, h: float, c: Color) -> void:
	var r := ColorRect.new()
	r.position = Vector2(x, y)
	r.size = Vector2(w, h)
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)


# ══════════════════════════════════════════════════════════════
# 입력
# ══════════════════════════════════════════════════════════════

func _on_card_input(event: InputEvent, idx: int) -> void:
	if _picked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_p2_local:
			return
		_pick(idx)


func _on_hover_enter(idx: int) -> void:
	if _picked:
		return
	_hovered_idx = idx
	# 호버 카드를 앞으로
	if idx >= 0 and idx < _card_roots.size():
		_card_roots[idx].z_index = 1


func _on_hover_exit(idx: int) -> void:
	if _picked:
		return
	if _hovered_idx == idx:
		_hovered_idx = -1
	if idx >= 0 and idx < _card_roots.size():
		_card_roots[idx].z_index = 0


func _unhandled_input(event: InputEvent) -> void:
	if _picked:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# P2 로컬만 키보드 입력
	if _is_p2_local:
		if event.is_action("p2_card_pick_1"):
			_pick(0)
		elif event.is_action("p2_card_pick_2"):
			_pick(1)
		elif event.is_action("p2_card_pick_3"):
			_pick(2)


# ══════════════════════════════════════════════════════════════
# 메인 루프
# ══════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_time += delta

	if _anim_phase == 0:
		# idle: 호버 효과
		_update_hover(delta)
		_update_shimmer(delta)
		return

	_anim_timer -= delta

	match _anim_phase:
		1:
			_tick_pick_move(delta)
			if _anim_timer <= 0.0:
				_anim_phase = 2
				_anim_timer = GLOW_HOLD_DURATION
				_start_glow_hold()
		2:
			_tick_glow_hold(delta)
			if _anim_timer <= 0.0:
				_anim_phase = 3
				_anim_timer = FINAL_FADE_DURATION
		3:
			_tick_final_fade(delta)
			if _anim_timer <= 0.0:
				_finish_pick()

	_update_shimmer(delta)
	_tick_particles(delta)
	_tick_flying_cards(delta)


# ══════════════════════════════════════════════════════════════
# 호버 애니메이션 (부드러운 스케일 + 리프트)
# ══════════════════════════════════════════════════════════════

func _update_hover(delta: float) -> void:
	for i in _card_states.size():
		var st: Dictionary = _card_states[i]
		var card: Control = _card_roots[i]
		var hovered := (i == _hovered_idx)

		# 목표 스케일/리프트
		var ts := HOVER_SCALE if hovered else 1.0
		var tl := HOVER_LIFT if hovered else 0.0
		var t := clampf(HOVER_LERP * delta, 0.0, 1.0)
		st["cur_scale"] = lerpf(float(st["cur_scale"]), ts, t)
		st["cur_lift"] = lerpf(float(st["cur_lift"]), tl, t)

		card.scale = Vector2(st["cur_scale"], st["cur_scale"])
		card.position.y = float(st["base_y"]) - float(st["cur_lift"])

		# 글로우 배경
		var glow: ColorRect = st["glow_bg"]
		if is_instance_valid(glow):
			var ga := 0.18 if hovered else 0.0
			glow.color.a = lerpf(glow.color.a, ga, t)

		# 카드 배경 살짝 밝게
		var cbg: ColorRect = st["card_bg"]
		if is_instance_valid(cbg):
			var target_col := Color(0.16, 0.14, 0.20) if hovered else Color(0.10, 0.09, 0.13)
			cbg.color = cbg.color.lerp(target_col, t)


# ══════════════════════════════════════════════════════════════
# 에너지 테두리 시머 애니메이션
# ══════════════════════════════════════════════════════════════

func _update_shimmer(delta: float) -> void:
	for i in _card_states.size():
		var st: Dictionary = _card_states[i]
		var hovered := (i == _hovered_idx) or (i == _picked_idx and _anim_phase > 0)
		var shimmer_arr: Array = st["shimmer"]

		for sp in shimmer_arr:
			var node: ColorRect = sp["node"]
			if not is_instance_valid(node):
				continue

			if hovered:
				var t_param: float = sp["t"]
				# 두 방향 파동의 간섭 — 유기적 에너지 흐름
				var wave1 := sin((_time * SHIMMER_SPEED - t_param * TAU * 2.0)) * 0.5 + 0.5
				var wave2 := sin((_time * SHIMMER_SPEED * 0.7 + t_param * TAU * 1.5)) * 0.5 + 0.5
				var wave := maxf(wave1, wave2)

				# 바깥으로 떠오르기
				var float_d := wave * SHIMMER_FLOAT
				var base: Vector2 = sp["base"]
				var nrm: Vector2 = sp["normal"]
				var sz: float = sp["size"] * (0.6 + wave * 0.8)
				var pos := base + nrm * float_d

				node.position = pos - Vector2(sz * 0.5, sz * 0.5)
				node.size = Vector2(sz, sz)
				# 색상: 밝기 변조 + 흰색으로 살짝 시프트
				var accent: Color = st["accent"]
				node.color = accent.lightened(wave * 0.5)
				node.color.a = (0.25 + wave * 0.65)
				node.rotation = _time * 2.2
			else:
				node.color.a = lerpf(node.color.a, 0.0, 8.0 * delta)


# ══════════════════════════════════════════════════════════════
# 선택 시작
# ══════════════════════════════════════════════════════════════

func _pick(idx: int) -> void:
	if idx < 0 or idx >= _card_ids.size() or _picked:
		return
	_picked = true
	_picked_idx = idx
	_hovered_idx = -1

	var card: Control = _card_roots[idx]
	_picked_accent = card.get_meta("accent") if card.has_meta("accent") else Color.WHITE

	# 최상단으로
	move_child(card, get_child_count() - 1)
	move_child(_particle_canvas, get_child_count() - 1)
	move_child(_glow_rect, get_child_count() - 1)

	# 빛줄기
	_build_rays(card)

	# 헤더
	var card_data: Dictionary = CardDB.get_card(_card_ids[idx])
	_header_label.text = card_data.get("name", "?") + " 획득!"
	_header_label.add_theme_color_override("font_color", _picked_accent.lightened(0.3))

	# 목표 위치 (화면 중앙)
	var target_x := (_screen_w - CARD_W * PICK_SCALE) * 0.5
	var target_y := (_screen_h - CARD_H * PICK_SCALE) * 0.5
	card.set_meta("start_pos", card.position)
	card.set_meta("target_pos", Vector2(target_x, target_y))

	# 나머지 카드에 탈출 속도 부여
	var center := card.position + Vector2(CARD_W * 0.5, CARD_H * 0.5)
	for i in _card_roots.size():
		if i == idx:
			continue
		var other: Control = _card_roots[i]
		var other_c := other.position + Vector2(CARD_W * 0.5, CARD_H * 0.5)
		var away := (other_c - center).normalized()
		if away.length() < 0.1:
			away = Vector2(-1 if i < idx else 1, -0.3).normalized()
		_card_states[i]["fly_vel"] = away * FLY_SPEED
		_card_states[i]["fly_rot"] = randf_range(-8.0, 8.0)

	# 스크린 플래시
	_glow_rect.color = Color(_picked_accent.r, _picked_accent.g, _picked_accent.b, 0.25)

	_anim_phase = 1
	_anim_timer = PICK_ANIM_DURATION


# ══════════════════════════════════════════════════════════════
# Phase 1 — 펀치 확대 + 중앙 이동 + 빛줄기 등장
# ══════════════════════════════════════════════════════════════

func _tick_pick_move(_delta: float) -> void:
	var t := 1.0 - clampf(_anim_timer / PICK_ANIM_DURATION, 0.0, 1.0)
	var card: Control = _card_roots[_picked_idx]
	var start_pos: Vector2 = card.get_meta("start_pos")
	var target_pos: Vector2 = card.get_meta("target_pos")

	# 스케일: 오버슈트 (처음 25%에서 PUNCH까지 갔다가 PICK_SCALE로)
	var s: float
	if t < 0.25:
		var pt := t / 0.25
		s = lerpf(float(_card_states[_picked_idx]["cur_scale"]), PICK_PUNCH, pt * pt)
	else:
		var st := (t - 0.25) / 0.75
		var ease_out := 1.0 - pow(1.0 - st, 3.0)
		s = lerpf(PICK_PUNCH, PICK_SCALE, ease_out)
	card.scale = Vector2(s, s)

	# 위치: ease out cubic
	var move_e := 1.0 - pow(1.0 - t, 3.0)
	card.position = start_pos.lerp(target_pos, move_e)

	# 빛줄기 서서히 등장
	_rays_container.modulate.a = lerpf(0.0, 0.75, t)

	# 플래시 감쇠
	_glow_rect.color.a = lerpf(0.25, 0.0, t)

	# 헤더 올라가며 투명
	_header_label.modulate.a = lerpf(1.0, 0.65, t)


## 나머지 카드 날아가기 (독립 틱)
func _tick_flying_cards(delta: float) -> void:
	if _anim_phase == 0:
		return
	for i in _card_roots.size():
		if i == _picked_idx:
			continue
		var st: Dictionary = _card_states[i]
		var fv: Vector2 = st["fly_vel"]
		if fv.length_squared() < 1.0:
			continue
		var card: Control = _card_roots[i]
		card.position += fv * delta
		card.rotation += float(st["fly_rot"]) * delta
		card.modulate.a = maxf(0.0, card.modulate.a - 2.5 * delta)
		# 감속
		st["fly_vel"] = fv * 0.96


# ══════════════════════════════════════════════════════════════
# Phase 2 — 글로우 유지 + 파티클
# ══════════════════════════════════════════════════════════════

func _start_glow_hold() -> void:
	_particle_canvas.modulate.a = 1.0
	var card: Control = _card_roots[_picked_idx]
	var center := card.position + Vector2(CARD_W * PICK_SCALE * 0.5, CARD_H * PICK_SCALE * 0.5)
	_spawn_sparkles(center, 32)


func _tick_glow_hold(_delta: float) -> void:
	var t := 1.0 - clampf(_anim_timer / GLOW_HOLD_DURATION, 0.0, 1.0)
	# 글로우 사인 펄스
	_glow_rect.color.a = sin(t * PI) * 0.16
	# 빛줄기 회전
	_rays_container.rotation = t * 0.08


# ══════════════════════════════════════════════════════════════
# Phase 3 — 전체 페이드아웃
# ══════════════════════════════════════════════════════════════

func _tick_final_fade(_delta: float) -> void:
	var t := 1.0 - clampf(_anim_timer / FINAL_FADE_DURATION, 0.0, 1.0)
	modulate.a = lerpf(1.0, 0.0, t * t)


func _finish_pick() -> void:
	card_picked.emit(_card_ids[_picked_idx])
	queue_free()


# ══════════════════════════════════════════════════════════════
# 빛줄기
# ══════════════════════════════════════════════════════════════

func _build_rays(card: Control) -> void:
	var center := Vector2(
		card.position.x + CARD_W * 0.5,
		card.position.y + CARD_H * 0.5
	)
	_rays_container.pivot_offset = center

	var ray_count := 14
	var ray_len := maxf(_screen_w, _screen_h) * 0.9

	for i in ray_count:
		var angle := (float(i) / float(ray_count)) * TAU
		var half := TAU / float(ray_count) * 0.28
		var p1 := center
		var p2 := center + Vector2(cos(angle - half), sin(angle - half)) * ray_len
		var p3 := center + Vector2(cos(angle + half), sin(angle + half)) * ray_len

		var ray := Polygon2D.new()
		ray.polygon = PackedVector2Array([p1, p2, p3])
		ray.color = Color(
			_picked_accent.r, _picked_accent.g, _picked_accent.b,
			0.20 if i % 2 == 0 else 0.10
		)
		_rays_container.add_child(ray)


# ══════════════════════════════════════════════════════════════
# 파티클
# ══════════════════════════════════════════════════════════════

func _spawn_sparkles(center: Vector2, count: int) -> void:
	for i in count:
		var angle := randf() * TAU
		var speed := randf_range(90.0, 280.0)
		var life := randf_range(0.4, 0.9)
		var sz := randf_range(2.0, 6.5)

		var col := _picked_accent.lightened(randf_range(0.15, 0.55))
		col.h = fmod(col.h + randf_range(-0.06, 0.06) + 1.0, 1.0)

		var rect := ColorRect.new()
		rect.size = Vector2(sz, sz)
		rect.color = col
		rect.position = center - Vector2(sz * 0.5, sz * 0.5)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.pivot_offset = Vector2(sz * 0.5, sz * 0.5)
		rect.rotation = randf() * TAU
		_particle_canvas.add_child(rect)

		_particles.append({
			"node": rect,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"life": life,
			"max_life": life,
			"size": sz,
			"rot_speed": randf_range(-6.0, 6.0),
		})


func _tick_particles(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in _particles.size():
		var p: Dictionary = _particles[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			if is_instance_valid(p["node"]):
				p["node"].queue_free()
			to_remove.append(i)
			continue

		var node: ColorRect = p["node"]
		if not is_instance_valid(node):
			to_remove.append(i)
			continue

		var vel: Vector2 = p["vel"]
		vel *= 0.97
		p["vel"] = vel
		node.position += vel * delta
		node.rotation += float(p["rot_speed"]) * delta

		var lr: float = float(p["life"]) / float(p["max_life"])
		node.modulate.a = lr
		var s: float = float(p["size"]) * lr
		node.size = Vector2(s, s)

	for i in range(to_remove.size() - 1, -1, -1):
		_particles.remove_at(to_remove[i])
