extends Control
## 메인 메뉴 — Death Stronger 랜딩 페이지

enum S { MAIN, FIND, WAIT }

var _state := S.MAIN
var _t := 0.0

# -- 코드에서 생성하는 노드 --
var _content: VBoxContainer
var _menu_box: VBoxContainer
var _find_box: VBoxContainer
var _wait_box: VBoxContainer
var _back_btn: Button
var _status_lbl: Label
var _ip_edit: LineEdit
var _wait_lbl: Label
var _grains: Array[ColorRect] = []

# -- 팔레트 --
const C_BG      := Color(0.07, 0.07, 0.13)
const C_SAND    := Color(0.92, 0.80, 0.42)
const C_SAND_M  := Color(0.72, 0.62, 0.34)
const C_SAND_D  := Color(0.50, 0.43, 0.28)
const C_PANEL   := Color(0.11, 0.10, 0.17)
const C_PANEL_H := Color(0.17, 0.15, 0.25)
const C_TXT     := Color(0.90, 0.86, 0.76)
const C_ACCENT  := Color(0.95, 0.82, 0.38)
const C_SUBTLE  := Color(0.50, 0.48, 0.42)
const C_GREEN   := Color(0.50, 0.85, 0.55)
const C_RED     := Color(0.85, 0.35, 0.30)


func _ready() -> void:
	# ── 배경 ──
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	# ── 콘텐츠 컬럼 (수직 중앙 정렬) ──
	_content = VBoxContainer.new()
	_content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 0)
	_content.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_content)

	# 타이틀
	var title := _build_title()
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(title)

	# 간격
	var gap := Control.new()
	gap.custom_minimum_size.y = 36
	_content.add_child(gap)

	# 메인 메뉴 버튼
	_menu_box = _build_menu()
	_menu_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(_menu_box)

	# 방 찾기 오버레이
	_find_box = _build_find()
	_find_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_find_box.visible = false
	_content.add_child(_find_box)

	# 대기 오버레이
	_wait_box = _build_wait()
	_wait_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wait_box.visible = false
	_content.add_child(_wait_box)

	# ── 뒤로 가기 (좌측 상단, FIND/WAIT 시 표시) ──
	_back_btn = _flat_btn("◁  뒤로", C_SUBTLE)
	_back_btn.add_theme_font_size_override("font_size", 15)
	_back_btn.set_anchors_preset(PRESET_TOP_LEFT)
	_back_btn.offset_left = 24
	_back_btn.offset_top = 20
	_back_btn.pressed.connect(_go_main)
	_back_btn.visible = false
	add_child(_back_btn)

	# ── 하단 상태 텍스트 ──
	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_color_override("font_color", C_ACCENT)
	_status_lbl.add_theme_font_size_override("font_size", 14)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_lbl.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_status_lbl.offset_top = -38
	_status_lbl.offset_bottom = -12
	_status_lbl.offset_left = 40
	_status_lbl.offset_right = -40
	_status_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_status_lbl)

	# ── 네트워크 시그널 ──
	Network.player_connected.connect(_on_player_connected)
	Network.server_disconnected.connect(_on_server_disconnected)
	Network.leave_game()


# ╔══════════════════════════════════════════════════════╗
# ║  타이틀 — 모래알 질감 + 붓 터치 고스트              ║
# ╚══════════════════════════════════════════════════════╝

func _build_title() -> Control:
	var area := Control.new()
	area.custom_minimum_size = Vector2(520, 130)
	area.mouse_filter = MOUSE_FILTER_IGNORE

	# 붓 터치 고스트 레이어 (약간씩 어긋난 복사본)
	var offsets := [
		Vector2(-3.0, -1.5), Vector2(2.2, 1.8), Vector2(-1.5, 2.8),
		Vector2(3.0, -2.2), Vector2(0.8, -3.0),
	]
	var alphas := [0.22, 0.16, 0.12, 0.08, 0.05]

	for i in offsets.size():
		var ghost := _title_lbl()
		ghost.add_theme_color_override(
			"font_color", C_SAND_M.lerp(C_SAND_D, float(i) / 4.0))
		ghost.modulate.a = alphas[i]
		ghost.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		ghost.offset_left  += offsets[i].x
		ghost.offset_top   += offsets[i].y
		ghost.offset_right += offsets[i].x
		ghost.offset_bottom += offsets[i].y
		area.add_child(ghost)

	# 메인 타이틀
	var main_lbl := _title_lbl()
	main_lbl.add_theme_color_override("font_color", C_SAND)
	main_lbl.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	area.add_child(main_lbl)

	# 모래알 입자 (타이틀 위에 흩뿌려짐)
	for j in 110:
		var g := ColorRect.new()
		var sz := randf_range(1.0, 3.2)
		g.size = Vector2(sz, sz)
		g.position = Vector2(randf_range(15, 505), randf_range(20, 110))
		var colors: Array[Color] = [C_SAND, C_SAND_M, C_SAND_D]
		g.color = colors.pick_random()
		g.modulate.a = randf_range(0.10, 0.50)
		g.mouse_filter = MOUSE_FILTER_IGNORE
		area.add_child(g)
		_grains.append(g)

	return area


func _title_lbl() -> Label:
	var l := Label.new()
	l.text = "DEATH  STRONGER"
	l.add_theme_font_size_override("font_size", 52)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


# ╔══════════════════════════════════════════════════════╗
# ║  메인 메뉴 버튼                                      ║
# ╚══════════════════════════════════════════════════════╝

func _build_menu() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	var b_host := _menu_btn("방 만들기", "◈", C_ACCENT)
	b_host.pressed.connect(_on_host)
	box.add_child(b_host)

	var b_find := _menu_btn("방 찾기", "◇", C_ACCENT)
	b_find.pressed.connect(_on_find)
	box.add_child(b_find)

	var b_local := _menu_btn("로컬 플레이 (2P)", "⊞", C_GREEN)
	b_local.pressed.connect(_on_local)
	box.add_child(b_local)

	# 구분 간격
	var sp := Control.new()
	sp.custom_minimum_size.y = 6
	box.add_child(sp)

	var b_set := _menu_btn("설정", "⚙", C_SUBTLE)
	b_set.pressed.connect(func(): _status_lbl.text = "설정은 준비 중입니다.")
	box.add_child(b_set)

	var b_quit := _menu_btn("나가기", "✕", C_RED)
	b_quit.pressed.connect(func(): get_tree().quit())
	box.add_child(b_quit)

	return box


func _menu_btn(text: String, icon: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = "  %s   %s" % [icon, text]
	btn.custom_minimum_size = Vector2(340, 50)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_color_override("font_color", C_TXT)
	btn.add_theme_color_override("font_hover_color", accent)
	btn.add_theme_color_override("font_pressed_color", accent.lightened(0.2))
	btn.add_theme_font_size_override("font_size", 17)

	# Normal
	var sn := StyleBoxFlat.new()
	sn.bg_color = C_PANEL
	sn.border_width_left = 4
	sn.border_color = accent.darkened(0.35)
	sn.set_corner_radius_all(6)
	sn.content_margin_left  = 16
	sn.content_margin_right = 16
	sn.content_margin_top   = 10
	sn.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", sn)

	# Hover
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = C_PANEL_H
	sh.border_color = accent
	sh.border_width_left = 5
	btn.add_theme_stylebox_override("hover", sh)

	# Pressed
	var sp := sh.duplicate() as StyleBoxFlat
	sp.bg_color = C_PANEL_H.lightened(0.08)
	btn.add_theme_stylebox_override("pressed", sp)

	# Disabled
	var sd := sn.duplicate() as StyleBoxFlat
	sd.bg_color = C_PANEL.darkened(0.2)
	sd.border_color = accent.darkened(0.6)
	btn.add_theme_stylebox_override("disabled", sd)

	return btn


# ╔══════════════════════════════════════════════════════╗
# ║  방 찾기 오버레이                                    ║
# ╚══════════════════════════════════════════════════════╝

func _build_find() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)

	# 안내 문구
	var lbl := Label.new()
	lbl.text = "접속할 IP를 입력하세요"
	lbl.add_theme_color_override("font_color", C_TXT)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)

	# IP 입력
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(340, 46)
	_ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ip_edit.add_theme_font_size_override("font_size", 16)
	_ip_edit.add_theme_color_override("font_color", C_TXT)
	_ip_edit.add_theme_color_override("font_placeholder_color", C_SUBTLE)

	var style_n := StyleBoxFlat.new()
	style_n.bg_color = Color(0.08, 0.08, 0.14)
	style_n.border_width_bottom = 2
	style_n.border_color = C_SAND_D
	style_n.set_corner_radius_all(4)
	style_n.content_margin_left  = 14
	style_n.content_margin_right = 14
	style_n.content_margin_top   = 10
	style_n.content_margin_bottom = 10
	_ip_edit.add_theme_stylebox_override("normal", style_n)

	var style_f := style_n.duplicate() as StyleBoxFlat
	style_f.border_color = C_ACCENT
	_ip_edit.add_theme_stylebox_override("focus", style_f)

	_ip_edit.text_submitted.connect(func(_txt: String): _on_join())
	box.add_child(_ip_edit)

	# 접속 버튼
	var conn := _menu_btn("접속", "▶", C_ACCENT)
	conn.pressed.connect(_on_join)
	box.add_child(conn)

	return box


# ╔══════════════════════════════════════════════════════╗
# ║  대기 오버레이                                       ║
# ╚══════════════════════════════════════════════════════╝

func _build_wait() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)

	_wait_lbl = Label.new()
	_wait_lbl.text = "대기 중…"
	_wait_lbl.add_theme_color_override("font_color", C_ACCENT)
	_wait_lbl.add_theme_font_size_override("font_size", 20)
	_wait_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_wait_lbl)

	var cancel := _menu_btn("취소", "◁", C_RED)
	cancel.pressed.connect(_on_cancel)
	box.add_child(cancel)

	return box


# ╔══════════════════════════════════════════════════════╗
# ║  투명 배경 버튼 (뒤로 가기 등)                       ║
# ╚══════════════════════════════════════════════════════╝

func _flat_btn(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", C_TXT)
	var empty := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	b.add_theme_stylebox_override("focus", empty)
	return b


# ╔══════════════════════════════════════════════════════╗
# ║  상태 전환                                           ║
# ╚══════════════════════════════════════════════════════╝

func _switch(ns: S) -> void:
	_state = ns
	_menu_box.visible = (ns == S.MAIN)
	_find_box.visible = (ns == S.FIND)
	_wait_box.visible = (ns == S.WAIT)
	_back_btn.visible = (ns == S.FIND or ns == S.WAIT)
	if ns == S.FIND:
		_ip_edit.call_deferred("grab_focus")


func _go_main() -> void:
	if _state == S.WAIT:
		Network.leave_game()
	_status_lbl.text = ""
	_switch(S.MAIN)


# ╔══════════════════════════════════════════════════════╗
# ║  버튼 콜백                                          ║
# ╚══════════════════════════════════════════════════════╝

func _on_host() -> void:
	var err := Network.host_game()
	if err != "":
		_status_lbl.text = err
		return
	_wait_lbl.text = "호스트 시작됨 — 상대 대기 중…"
	_status_lbl.text = ""
	_switch(S.WAIT)


func _on_find() -> void:
	_status_lbl.text = ""
	_switch(S.FIND)


func _on_join() -> void:
	var addr := _ip_edit.text.strip_edges()
	if addr == "":
		addr = "127.0.0.1"
	var err := Network.join_game(addr)
	if err != "":
		_status_lbl.text = err
		return
	_wait_lbl.text = "%s 접속 중…" % addr
	_status_lbl.text = ""
	_switch(S.WAIT)


func _on_local() -> void:
	_status_lbl.text = "로컬 2P 시작…"
	Network.start_local_game()


func _on_cancel() -> void:
	Network.leave_game()
	_status_lbl.text = ""
	_switch(S.MAIN)


# ╔══════════════════════════════════════════════════════╗
# ║  네트워크 시그널                                     ║
# ╚══════════════════════════════════════════════════════╝

func _on_player_connected(id: int) -> void:
	_status_lbl.text = "플레이어 %d 연결됨 — 게임 시작!" % id


func _on_server_disconnected() -> void:
	_status_lbl.text = "서버 연결이 끊겼습니다."
	_switch(S.MAIN)


# ╔══════════════════════════════════════════════════════╗
# ║  모래알 반짝임 애니메이션                            ║
# ╚══════════════════════════════════════════════════════╝

func _process(delta: float) -> void:
	_t += delta
	for i in _grains.size():
		var phase: float = float(i) * 0.73
		var base_a: float = 0.12 + 0.38 * fmod(float(i) * 0.137, 1.0)
		_grains[i].modulate.a = base_a + 0.10 * sin(_t * 1.8 + phase)
