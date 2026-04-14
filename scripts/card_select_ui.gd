extends Control
## 카드 선택 UI — 트럼프 카드 스타일.
##
## 사용:
##   var ui := preload("res://scenes/card_select_ui.tscn").instantiate()
##   ui.setup(player_node, ["fast", "big", "homing"])
##   ui.card_picked.connect(func(id): ...)
##   add_child(ui)
##
## 입력:
##   마우스 클릭 (P1/온라인), 키보드 1/2/3 (P1), 7/8/9 (P2 로컬)

signal card_picked(card_id: String)

const SCREEN_W := 1400.0
const SCREEN_H := 800.0
const CARD_W := 170.0
const CARD_H := 250.0
const CARD_GAP := 30.0
const CARD_BORDER := 3.0
const HOVER_LIFT := 12.0

var _player: Node
var _card_ids: Array = []
var _card_roots: Array[Control] = []
var _card_bgs: Array[ColorRect] = []
var _is_p2_local := false


func setup(player: Node, card_ids: Array) -> void:
	_player = player
	_card_ids = card_ids
	_is_p2_local = (
		Network.is_local()
		and "input_scheme" in player
		and player.input_scheme == player.InputScheme.LOCAL_P2
	)


func _ready() -> void:
	# 배경 딤
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# 헤더
	var who: String
	if _is_p2_local:
		who = "P2"
	elif "input_scheme" in _player and _player.input_scheme == _player.InputScheme.LOCAL_P1:
		who = "P1"
	else:
		who = "당신"
	var header := Label.new()
	header.text = "%s — 카드를 선택하세요" % who
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 26)
	header.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	var header_y: float = 50.0 if not _is_p2_local else 520.0
	header.position = Vector2(0, header_y)
	header.size = Vector2(SCREEN_W, 36)
	header.add_theme_font_size_override("font_size", 22)
	add_child(header)

	# 카드 3장 배치 (화면 중앙 정렬)
	var total_w: float = CARD_W * 3.0 + CARD_GAP * 2.0
	var start_x: float = (SCREEN_W - total_w) * 0.5
	var card_y: float = 100.0 if not _is_p2_local else 560.0

	for i in 3:
		var card_data: Dictionary = CardDB.get_card(_card_ids[i])
		var cx: float = start_x + float(i) * (CARD_W + CARD_GAP)
		var card := _build_card(cx, card_y, card_data, i)
		add_child(card)
		_card_roots.append(card)


func _build_card(x: float, y: float, data: Dictionary, idx: int) -> Control:
	var accent: Color = data.get("color", Color.WHITE)

	# 카드 루트 컨테이너
	var root := Control.new()
	root.position = Vector2(x, y)
	root.size = Vector2(CARD_W, CARD_H)
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	# ── 카드 배경 (어두운 기본색) ──
	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(CARD_W, CARD_H)
	bg.color = Color(0.10, 0.09, 0.13)
	root.add_child(bg)
	_card_bgs.append(bg)

	# ── 테두리 (accent 색) ──
	_add_border(root, accent)

	# ── 상단 이름 영역 ──
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

	# ── 중앙 아이콘 영역 (다이아몬드 배경 + 아이콘 텍스트) ──
	var icon_area_y := 44.0
	var icon_area_h := 100.0

	# 다이아몬드 배경
	var diamond := Polygon2D.new()
	var cx: float = CARD_W * 0.5
	var cy: float = icon_area_y + icon_area_h * 0.5
	var dx: float = 44.0
	var dy: float = 44.0
	diamond.polygon = PackedVector2Array([
		Vector2(cx, cy - dy),
		Vector2(cx + dx, cy),
		Vector2(cx, cy + dy),
		Vector2(cx - dx, cy),
	])
	diamond.color = accent.darkened(0.35)
	root.add_child(diamond)

	# 아이콘 글자
	var icon_label := Label.new()
	icon_label.text = data.get("icon", "?")
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 38)
	icon_label.add_theme_color_override("font_color", accent.lightened(0.5))
	icon_label.position = Vector2(CARD_BORDER, icon_area_y)
	icon_label.size = Vector2(CARD_W - CARD_BORDER * 2, icon_area_h)
	root.add_child(icon_label)

	# ── 구분선 ──
	var sep := ColorRect.new()
	sep.position = Vector2(18, icon_area_y + icon_area_h + 4)
	sep.size = Vector2(CARD_W - 36, 1)
	sep.color = Color(accent.r, accent.g, accent.b, 0.35)
	root.add_child(sep)

	# ── 하단 설명 ──
	var desc_label := Label.new()
	desc_label.text = data.get("desc", "")
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.75))
	desc_label.position = Vector2(10, icon_area_y + icon_area_h + 8)
	desc_label.size = Vector2(CARD_W - 20, 56)
	root.add_child(desc_label)

	# ── 하단 키 힌트 ──
	var key_label := Label.new()
	key_label.text = "[%d]" % (idx + 7 if _is_p2_local else idx + 1)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", 14)
	key_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
	key_label.position = Vector2(0, CARD_H - 32)
	key_label.size = Vector2(CARD_W, 24)
	root.add_child(key_label)

	# ── 모서리 장식 (좌상단, 우하단에 작은 아이콘) ──
	for corner in [Vector2(12, 48), Vector2(CARD_W - 28, CARD_H - 32)]:
		var mini := Label.new()
		mini.text = data.get("icon", "?")
		mini.add_theme_font_size_override("font_size", 12)
		mini.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.55))
		mini.position = corner
		mini.size = Vector2(16, 16)
		root.add_child(mini)

	# ── 인터랙션 ──
	root.gui_input.connect(_on_card_input.bind(idx))
	root.mouse_entered.connect(_on_card_hover.bind(idx, true))
	root.mouse_exited.connect(_on_card_hover.bind(idx, false))

	return root


func _add_border(parent: Control, c: Color) -> void:
	var b := CARD_BORDER
	var w := CARD_W
	var h := CARD_H
	# top
	_rect(parent, 0, 0, w, b, c)
	# bottom
	_rect(parent, 0, h - b, w, b, c)
	# left
	_rect(parent, 0, b, b, h - b * 2, c)
	# right
	_rect(parent, w - b, b, b, h - b * 2, c)


func _rect(parent: Control, x: float, y: float, w: float, h: float, c: Color) -> void:
	var r := ColorRect.new()
	r.position = Vector2(x, y)
	r.size = Vector2(w, h)
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)


func _on_card_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_p2_local:
			return
		_pick(idx)


func _on_card_hover(idx: int, hovered: bool) -> void:
	if idx < 0 or idx >= _card_roots.size():
		return
	var card: Control = _card_roots[idx]
	var base_y: float = card.position.y
	if hovered:
		card.position.y = base_y - HOVER_LIFT if not card.has_meta("lifted") else card.position.y
		card.set_meta("lifted", true)
		_card_bgs[idx].color = Color(0.16, 0.14, 0.20)
	else:
		if card.has_meta("lifted"):
			card.position.y = base_y + HOVER_LIFT
			card.remove_meta("lifted")
		_card_bgs[idx].color = Color(0.10, 0.09, 0.13)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _is_p2_local:
		if event.is_action("p2_card_pick_1"): _pick(0)
		elif event.is_action("p2_card_pick_2"): _pick(1)
		elif event.is_action("p2_card_pick_3"): _pick(2)
	else:
		if event.is_action("card_pick_1"): _pick(0)
		elif event.is_action("card_pick_2"): _pick(1)
		elif event.is_action("card_pick_3"): _pick(2)


func _pick(idx: int) -> void:
	if idx < 0 or idx >= _card_ids.size():
		return
	var picked: String = _card_ids[idx]
	card_picked.emit(picked)
	queue_free()
