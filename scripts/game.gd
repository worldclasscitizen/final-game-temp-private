extends Node2D
## 게임 씬 — Nidhogg 스타일 방(Room) 기반 장면 전환 맵.
##
## 구조:
##   - 맵은 9개의 방으로 구성 (idx 0..8, 중앙 idx=4 가 아레나).
##   - 좁은 방(1280px) = 뷰포트 1개 크기, 카메라 고정.
##   - 넓은 방(1920px) = 뷰포트 1.5개 크기, 리더 쪽을 따라 팬.
##   - 양 끝 방(idx=0, 8)은 UFO 엔딩 방. 승리측이 UFO 빔에 닿으면 납치 연출 후 승리.
##
## 리더:
##   - 가장 최근에 킬 한 사람이 리더 (leader_id).
##   - 리더만 현재 방의 "진행 방향 엣지" 를 넘어 다음 방으로 전환시킬 수 있다.
##   - 비리더는 방 경계에서 물리적으로 막힘.
##
## 장면 전환:
##   - 페이드 아웃 → 방 인덱스 갱신 + 플레이어 재배치 + 카메라 스냅 → 페이드 인.
##   - 리더는 새 방의 진입 엣지(뒤쪽)에, 비리더는 반대편 엣지(리더 진행 방향 쪽)에 배치.
##
## 리스폰:
##   - 사망 시 현재 방 안에서 리더의 진행 방향 쪽으로 일정 거리 떨어진 지점에 리스폰.
##   - 리스폰 직후 1초 무적(player.gd 가 처리).
##
## UFO 납치:
##   - UFO 방에서 승리 방향의 플레이어가 빔 영역(빔 중심 ±UFO_BEAM_HALF_W)에 들어오면 발동.
##   - 빔이 밝아지고 캐릭터가 위로 끌려올라감 → 페이드 아웃 → WinnerLabel 표시.
##
## 카드:
##   - OOB/UFO/전환 사망이 아닌 "총알 피격" 사망 시 카드 선택 UI 노출.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CARD_UI_SCENE := preload("res://scenes/card_select_ui.tscn")
const SpaceBackground := preload("res://scripts/space_background.gd")

# Player.InputScheme 와 동일 상수
const SCHEME_ONLINE := 0
const SCHEME_LOCAL_P1 := 1
const SCHEME_LOCAL_P2 := 2

# 뷰포트 / 맵 공통
# 뷰포트 1400x800 + 카메라 줌 1.75
const CAMERA_ZOOM := 1.75
const VIEW_W := 1400.0 / CAMERA_ZOOM     # = 800.0
const VIEW_H := 800.0 / CAMERA_ZOOM      # ≈457.1
const VIEW_HALF_W := VIEW_W * 0.5
const MAP_HEIGHT := 720
const FLOOR_TOP := 480.0  # 바닥 윗면 y (올림: 560→480, 바닥 아래가 더 보임)
const FLOOR_CENTER_Y := 560.0  # 바닥 StaticBody 중심 y

# 방 데이터 테이블 (왼쪽 → 오른쪽). 대칭 구성.
# compact: 뷰포트에 딱 맞는 좁은 방 (카메라 이동 없음)
const ROOMS_CFG := [
	{"w": 1000, "type": "ufo_left",   "palette": 0},  # 0  P2 승리방 (UFO)
	{"w": 800, "type": "corridor",     "palette": 1},  # 1  복도 (화면 꽉 참)
	{"w": 1400, "type": "wide",        "palette": 2},  # 2  넓은 안뜰
	{"w": 1000, "type": "warehouse",   "palette": 3},  # 3  창고 (박스 구조물)
	{"w": 1000, "type": "center",      "palette": 4},  # 4  아레나 (스폰)
	{"w": 1000, "type": "fortress",    "palette": 3},  # 5  요새 (다층 건물)
	{"w": 1400, "type": "wide",        "palette": 2},  # 6  넓은 안뜰
	{"w": 800, "type": "corridor",     "palette": 1},  # 7  복도 (화면 꽉 참)
	{"w": 1000, "type": "ufo_right",   "palette": 0},  # 8  P1 승리방
]
const SPAWN_ROOM_IDX := 4

# 색 팔레트 (70/20/10: 배경 / 바닥·구조물 / 액센트)
# 모래 사막 톤 — 어두운 밤 배경 + 따뜻한 모래색 구조물
const PALETTES := [
	{"bg": Color(0.07, 0.06, 0.055, 1), "plat": Color(0.33, 0.28, 0.22, 1), "accent": Color(0.63, 0.56, 0.44, 1)}, # 깊은 사막 밤
	{"bg": Color(0.09, 0.07, 0.06, 1),  "plat": Color(0.38, 0.30, 0.24, 1), "accent": Color(0.7, 0.55, 0.40, 1)},  # 황혼 모래
	{"bg": Color(0.10, 0.09, 0.08, 1),  "plat": Color(0.42, 0.36, 0.28, 1), "accent": Color(0.56, 0.50, 0.39, 1)}, # 안뜰 모래
	{"bg": Color(0.06, 0.07, 0.08, 1),  "plat": Color(0.30, 0.28, 0.25, 1), "accent": Color(0.50, 0.46, 0.38, 1)}, # 어두운 모래
	{"bg": Color(0.08, 0.08, 0.07, 1),  "plat": Color(0.35, 0.32, 0.26, 1), "accent": Color(0.60, 0.54, 0.42, 1)}, # 아레나 모래
]

# 구조물 레이아웃 (방 local 좌표 기준)
# type: "box_stack" / "building" / "building_roof" / "multi_room" / "platform"
# platform: 기존 단순 발판 (하위 호환)
# box_stack: 쌓인 상자들 (바닥에서 올라감)
# building: 벽 + 지붕 + 문 (출입 가능)
# building_roof: 벽 + 문 + 지붕 위로 점프 가능 (지붕 얇음)
# multi_room: 여러 방이 있는 건물 (내부 칸막이 + 문)
## 구조물 제거됨 — 우주 배경 + 평면 맵
const STRUCTURE_LAYOUTS := {}

# 튜닝값
const FADE_TIME := 0.28
const TRANSITION_EDGE_THRESHOLD := 10.0  # 방 끝에서 이만큼 더 가까워지면 전환 트리거
const ENTRY_INSET := 140.0                # 새 방에서 진입 캐릭터 배치 inset
const OPPOSITE_INSET := 140.0             # 비리더(멀어진 쪽) 배치 inset
const RESPAWN_FORWARD := 220.0            # 리더 앞쪽으로 리스폰
const RESPAWN_EDGE_PAD := 80.0            # 방 경계와의 최소 거리
const CAMERA_LERP := 8.0
const FALL_DEATH_Y := 1400.0
const UFO_BEAM_HALF_W := 60.0
const UFO_BEAM_TOP_Y := 140.0
const UFO_Y := 120.0
const UFO_ABDUCT_TIME := 1.4

@onready var map_root: Node2D = $Map
@onready var background: ColorRect = $Background
@onready var players_root: Node2D = $Players
@onready var camera: Camera2D = $Camera2D
@onready var winner_label: Label = $UI/WinnerLabel
@onready var hint_label: Label = $UI/HintLabel
@onready var leader_label: Label = $UI/LeaderLabel
@onready var room_label: Label = $UI/RoomLabel
@onready var fade_overlay: ColorRect = $UI/FadeOverlay
@onready var ui_layer: CanvasLayer = $UI

# ── 일시정지 메뉴 ──
var _paused := false
var _pause_timer := 0.0
const PAUSE_MAX_SEC := 30.0
var _pause_overlay: ColorRect
var _pause_vbox: VBoxContainer
var _pause_timer_label: Label
var _btn_resume: Button
var _btn_restart: Button
var _btn_main_menu: Button

# 런타임 방 정보: { x_start, x_end, w, type, palette, center_x, wide, ufo_x }
var rooms_info: Array = []
var current_room_idx: int = SPAWN_ROOM_IDX
var players: Dictionary = {}   # peer_id -> Player
var leader_id: int = 0
var game_over: bool = false
var transitioning: bool = false
var ufo_sequence_active: bool = false
var card_selecting: bool = false   # 카드 선택 중 플래그


func _ready() -> void:
	Engine.time_scale = 1.4
	process_mode = Node.PROCESS_MODE_ALWAYS  # ESC 입력을 일시정지 중에도 받기 위해
	# 게임플레이 노드들은 일시정지 시 멈추도록 설정
	map_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	players_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	background.process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_rooms()
	_spawn_players()
	winner_label.visible = false
	# 좌상단 UI 텍스트 숨김
	hint_label.visible = false
	leader_label.visible = false
	room_label.visible = false
	_snap_camera_to_room(current_room_idx)
	fade_overlay.color = Color(0, 0, 0, 0)
	_build_pause_menu()


## ── 방 생성 ─────────────────────────────────────────────────

func _build_rooms() -> void:
	rooms_info.clear()
	var cursor_x := 0.0
	for i in ROOMS_CFG.size():
		var cfg: Dictionary = ROOMS_CFG[i]
		var w: float = float(cfg.w)
		var room := {
			"x_start": cursor_x,
			"x_end": cursor_x + w,
			"w": w,
			"type": cfg.type,
			"palette": cfg.palette,
			"center_x": cursor_x + w * 0.5,
			"wide": w > VIEW_W + 1.0,
			"ufo_x": 0.0,
		}
		if cfg.type == "ufo_left":
			room.ufo_x = cursor_x + 220.0
		elif cfg.type == "ufo_right":
			room.ufo_x = cursor_x + w - 220.0
		rooms_info.append(room)
		cursor_x += w

	# 배경: 기존 ColorRect 숨기고 프로시저럴 우주 배경 생성
	background.visible = false

	var space_bg := SpaceBackground.new()
	space_bg.generate(cursor_x, float(MAP_HEIGHT))
	add_child(space_bg)
	move_child(space_bg, 0)  # 가장 뒤로

	for i in rooms_info.size():
		_build_room_content(i)


func _build_room_content(idx: int) -> void:
	var room: Dictionary = rooms_info[idx]
	var palette: Dictionary = PALETTES[room.palette]

	var room_node := Node2D.new()
	room_node.name = "Room%d" % idx
	map_root.add_child(room_node)

	# 방 구분선 (희미한 세로선)
	var divider_color := Color(0.4, 0.5, 0.7, 0.12)
	_make_divider(room_node, room.x_end, divider_color)

	# 바닥 (우주 스테이션 느낌 — 얇은 금속 플랫폼)
	var floor_color := Color(0.22, 0.24, 0.30, 1.0)
	_make_static_box(room_node, room.x_start + room.w * 0.5, FLOOR_CENTER_Y, room.w, 160.0, floor_color)
	# 바닥 표면 하이라이트
	var hi := ColorRect.new()
	hi.offset_left = room.x_start
	hi.offset_right = room.x_end
	hi.offset_top = FLOOR_TOP
	hi.offset_bottom = FLOOR_TOP + 2.0
	hi.color = Color(0.45, 0.50, 0.65, 0.9)
	hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_node.add_child(hi)

	# 맵 양끝 벽
	var wall_color := Color(0.25, 0.27, 0.33, 1.0)
	if idx == 0:
		_make_static_box(room_node, room.x_start + 10.0, 360.0, 20.0, 720.0, wall_color)
	if idx == rooms_info.size() - 1:
		_make_static_box(room_node, room.x_end - 10.0, 360.0, 20.0, 720.0, wall_color)

	# UFO (엔딩 방)
	if room.type == "ufo_left" or room.type == "ufo_right":
		_build_ufo(room_node, room.ufo_x, palette)


func _make_static_box(parent: Node, x: float, y: float, w: float, h: float, color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(x, y)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, h)
	var col := CollisionShape2D.new()
	col.shape = shape
	body.add_child(col)
	var vis := ColorRect.new()
	vis.offset_left = -w * 0.5
	vis.offset_top = -h * 0.5
	vis.offset_right = w * 0.5
	vis.offset_bottom = h * 0.5
	vis.color = color
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(vis)
	parent.add_child(body)


func _make_divider(parent: Node2D, x: float, accent: Color) -> void:
	var line := ColorRect.new()
	line.offset_left = x - 1.0
	line.offset_right = x + 1.0
	line.offset_top = 0.0
	line.offset_bottom = float(MAP_HEIGHT)
	line.color = Color(accent.r, accent.g, accent.b, 0.12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


## ── 구조물 빌더 제거됨 (우주 배경 모드) ──
func _build_ufo(parent: Node2D, x: float, palette: Dictionary) -> void:
	var ufo := Node2D.new()
	ufo.name = "UFO"
	ufo.position = Vector2(x, UFO_Y)
	# 본체
	var disc := ColorRect.new()
	disc.offset_left = -90
	disc.offset_top = -18
	disc.offset_right = 90
	disc.offset_bottom = 18
	disc.color = Color(0.55, 0.55, 0.62, 1)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ufo.add_child(disc)
	# 돔
	var dome := ColorRect.new()
	dome.offset_left = -42
	dome.offset_top = -46
	dome.offset_right = 42
	dome.offset_bottom = -18
	dome.color = palette.accent
	dome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ufo.add_child(dome)
	# 하단 램프 점
	for i in 3:
		var light := ColorRect.new()
		light.offset_left = -60 + i * 60 - 5
		light.offset_top = 16
		light.offset_right = -60 + i * 60 + 5
		light.offset_bottom = 26
		light.color = palette.accent
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ufo.add_child(light)
	# 빔 (평소엔 희미, 승리 시 밝아짐)
	var beam := ColorRect.new()
	beam.name = "Beam"
	beam.offset_left = -UFO_BEAM_HALF_W
	beam.offset_top = 22.0
	beam.offset_right = UFO_BEAM_HALF_W
	beam.offset_bottom = FLOOR_TOP - UFO_Y
	beam.color = Color(palette.accent.r, palette.accent.g, palette.accent.b, 0.15)
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ufo.add_child(beam)
	parent.add_child(ufo)



## ── 플레이어 스폰 ──────────────────────────────────────────

func _spawn_players() -> void:
	var spawn_room: Dictionary = rooms_info[SPAWN_ROOM_IDX]
	var p1_spawn := Vector2(spawn_room.x_start + 180.0, FLOOR_TOP - 30.0)
	var p2_spawn := Vector2(spawn_room.x_end - 180.0, FLOOR_TOP - 30.0)
	var right_goal_x: float = rooms_info[ROOMS_CFG.size() - 1].ufo_x  # UFO_RIGHT
	var left_goal_x: float = rooms_info[0].ufo_x                      # UFO_LEFT

	var p1_id := 1
	var p2_id := 2
	var p1_scheme: int
	var p2_scheme: int

	if Network.is_local():
		p1_scheme = SCHEME_LOCAL_P1
		p2_scheme = SCHEME_LOCAL_P2
	else:
		if multiplayer.is_server():
			var peers := multiplayer.get_peers()
			if peers.is_empty():
				push_error("클라이언트가 연결되지 않았습니다.")
				return
			p2_id = peers[0]
		else:
			p2_id = multiplayer.get_unique_id()
		p1_scheme = SCHEME_ONLINE
		p2_scheme = SCHEME_ONLINE

	var p1 := _instantiate_player(p1_id, p1_spawn, right_goal_x, 1, p1_scheme)
	var p2 := _instantiate_player(p2_id, p2_spawn, left_goal_x, -1, p2_scheme)

	players[p1_id] = p1
	players[p2_id] = p2

	for p in [p1, p2]:
		p.player_died.connect(_on_player_died)
		p.player_won.connect(_on_player_won)
		p.card_offered.connect(_on_card_offered)

	_update_hint_label(p1_id)


func _instantiate_player(pid: int, spawn: Vector2, goal_x: float, goal_dir: int, scheme: int) -> Node:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(pid)
	p.player_id = pid
	p.spawn_position = spawn
	p.goal_x = goal_x
	p.goal_direction = goal_dir
	p.input_scheme = scheme
	players_root.add_child(p, true)
	return p


## ── UI 라벨 ────────────────────────────────────────────────

func _update_hint_label(p1_id: int) -> void:
	if Network.is_local():
		hint_label.text = "P1(빨강 · WASD+마우스+클릭/F) →     |    P2(파랑 · 화살표+,/.+/) ←"
	else:
		var me := multiplayer.get_unique_id()
		if me == p1_id:
			hint_label.text = "당신은 P1 (빨강) — 오른쪽 UFO까지"
		else:
			hint_label.text = "당신은 P2 (파랑) — 왼쪽 UFO까지"


func _update_leader_label() -> void:
	if leader_id == 0:
		leader_label.text = "LEAD: — (먼저 킬하세요)"
	elif leader_id == 1:
		leader_label.text = "LEAD: P1 (빨강)"
	else:
		leader_label.text = "LEAD: P2 (파랑)"


func _update_room_label() -> void:
	var total := rooms_info.size()
	room_label.text = "ROOM %d / %d" % [current_room_idx + 1, total]


## ── 프레임 업데이트 ───────────────────────────────────────

func _process(delta: float) -> void:
	# 일시정지 타이머 (process_mode=ALWAYS 이므로 paused 중에도 호출됨)
	if _paused:
		var real_delta: float = delta / maxf(Engine.time_scale, 0.01)
		_pause_timer -= real_delta
		_update_pause_timer_label()
		if _pause_timer <= 0.0:
			_toggle_pause()
		return
	if game_over:
		return
	if transitioning or ufo_sequence_active or card_selecting:
		return
	if players.size() != 2:
		return
	_update_camera(delta)
	_enforce_room_bounds()
	_check_ufo_victory()
	_check_leader_advance()
	_check_fall_death()


## 현재 방 기준 카메라. 좁은 방은 고정, 넓은 방은 리더 추적(팬).
func _update_camera(delta: float) -> void:
	var room: Dictionary = rooms_info[current_room_idx]
	var target_x: float
	if not room.wide:
		target_x = room.center_x
	else:
		var leader: Node2D = players.get(leader_id) as Node2D
		if leader != null and leader.is_alive:
			target_x = leader.global_position.x
		else:
			var keys := players.keys()
			target_x = (players[keys[0]].global_position.x + players[keys[1]].global_position.x) * 0.5
		target_x = clampf(target_x, room.x_start + VIEW_HALF_W, room.x_end - VIEW_HALF_W)
	var t: float = clampf(CAMERA_LERP * delta, 0.0, 1.0)
	camera.position.x = lerpf(camera.position.x, target_x, t)
	camera.position.y = MAP_HEIGHT * 0.5


func _snap_camera_to_room(idx: int) -> void:
	var room: Dictionary = rooms_info[idx]
	if not room.wide:
		camera.position.x = room.center_x
	else:
		camera.position.x = clampf(room.center_x, room.x_start + VIEW_HALF_W, room.x_end - VIEW_HALF_W)
	camera.position.y = MAP_HEIGHT * 0.5


## 비리더는 방 경계에서 막힘. 리더가 진행 방향 엣지를 넘을 때만 전환 처리.
func _enforce_room_bounds() -> void:
	var room: Dictionary = rooms_info[current_room_idx]
	for pid in players:
		var p: Node2D = players[pid] as Node2D
		if p == null or not p.is_alive:
			continue
		var is_leader: bool = (pid == leader_id)
		var dir: int = int(p.goal_direction)
		var x: float = p.global_position.x
		# 왼쪽 경계
		if x < room.x_start + 15.0:
			if is_leader and dir < 0:
				pass  # 전환 트리거에서 처리
			else:
				p.global_position.x = room.x_start + 15.0
				if p.velocity.x < 0.0:
					p.velocity.x = 0.0
		# 오른쪽 경계
		if x > room.x_end - 15.0:
			if is_leader and dir > 0:
				pass
			else:
				p.global_position.x = room.x_end - 15.0
				if p.velocity.x > 0.0:
					p.velocity.x = 0.0


func _check_leader_advance() -> void:
	if leader_id == 0:
		return
	var leader: Node2D = players.get(leader_id) as Node2D
	if leader == null or not leader.is_alive:
		return
	var room: Dictionary = rooms_info[current_room_idx]
	var dir: int = int(leader.goal_direction)
	if dir > 0 and leader.global_position.x >= room.x_end - TRANSITION_EDGE_THRESHOLD:
		# UFO 엔딩 방에서 오른쪽 끝이면 빔 접근 처리 (전환 X)
		if room.type == "ufo_right":
			return
		_begin_transition(current_room_idx + 1)
	elif dir < 0 and leader.global_position.x <= room.x_start + TRANSITION_EDGE_THRESHOLD:
		if room.type == "ufo_left":
			return
		_begin_transition(current_room_idx - 1)


## UFO 빔에 진입 방향이 맞는 플레이어가 있으면 납치 연출 개시
func _check_ufo_victory() -> void:
	var room: Dictionary = rooms_info[current_room_idx]
	if room.type != "ufo_left" and room.type != "ufo_right":
		return
	var required_dir: int = -1 if room.type == "ufo_left" else 1
	for pid in players:
		var p: Node2D = players[pid] as Node2D
		if p == null or not p.is_alive:
			continue
		if int(p.goal_direction) != required_dir:
			continue
		if absf(p.global_position.x - room.ufo_x) <= UFO_BEAM_HALF_W and p.global_position.y < FLOOR_TOP + 10.0:
			_begin_ufo_sequence(pid)
			return


func _check_fall_death() -> void:
	for pid in players:
		var p: Node2D = players[pid] as Node2D
		if p == null or not p.is_alive:
			continue
		if p.has_respawn_immunity():
			continue
		if p.global_position.y > FALL_DEATH_Y:
			p.oob_kill()


## ── 장면 전환 ──────────────────────────────────────────────

func _begin_transition(new_idx: int) -> void:
	if transitioning or game_over:
		return
	if new_idx < 0 or new_idx >= rooms_info.size():
		return
	transitioning = true
	# 플레이어 입력 잠시 중단 (물리는 유지하되 조작 불가 — 간단히 픽킹 플래그 대신 physics 유지)
	var t := create_tween()
	t.tween_property(fade_overlay, "color:a", 1.0, FADE_TIME)
	t.tween_callback(Callable(self, "_swap_to_room").bind(new_idx))
	t.tween_property(fade_overlay, "color:a", 0.0, FADE_TIME)
	t.tween_callback(Callable(self, "_finish_transition"))


func _swap_to_room(new_idx: int) -> void:
	current_room_idx = new_idx
	var room: Dictionary = rooms_info[new_idx]
	_snap_camera_to_room(new_idx)
	_update_room_label()

	# 배치: 리더는 진입 엣지, 비리더는 반대편(리더 전진 방향)
	var leader: Node2D = players.get(leader_id) as Node2D
	if leader == null:
		return
	var leader_dir: int = int(leader.goal_direction)
	var leader_x: float
	var other_x: float
	if leader_dir > 0:
		leader_x = room.x_start + ENTRY_INSET
		other_x = room.x_end - OPPOSITE_INSET
	else:
		leader_x = room.x_end - ENTRY_INSET
		other_x = room.x_start + OPPOSITE_INSET

	for pid in players:
		var p: Node2D = players[pid] as Node2D
		if p == null:
			continue
		var target_x: float = leader_x if pid == leader_id else other_x
		var pos := Vector2(target_x, 500.0)
		if p.is_alive:
			p.global_position = pos
			p.velocity = Vector2.ZERO
		else:
			p.set_respawn_position(pos)


func _finish_transition() -> void:
	transitioning = false


## ── UFO 납치 연출 ─────────────────────────────────────────

func _begin_ufo_sequence(winner_id: int) -> void:
	if ufo_sequence_active or game_over:
		return
	ufo_sequence_active = true
	# 빔 밝히기
	_activate_ufo_beam(current_room_idx)
	# 모든 플레이어 입력 차단
	for p in players.values():
		if p:
			p.set_physics_process(false)
	var winner: Node2D = players[winner_id] as Node2D
	# 승자를 UFO 아래로 당기고 끌어올림
	var room: Dictionary = rooms_info[current_room_idx]
	var t := create_tween()
	t.set_parallel(false)
	t.tween_property(winner, "global_position:x", room.ufo_x, 0.35)
	t.tween_property(winner, "global_position:y", UFO_Y + 30.0, UFO_ABDUCT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(Callable(self, "_on_ufo_abducted").bind(winner_id))


func _activate_ufo_beam(idx: int) -> void:
	var room_node: Node = map_root.get_node_or_null("Room%d" % idx)
	if room_node == null:
		return
	var ufo: Node = room_node.get_node_or_null("UFO")
	if ufo == null:
		return
	var beam: ColorRect = ufo.get_node_or_null("Beam") as ColorRect
	if beam == null:
		return
	var c := beam.color
	c.a = 0.75
	beam.color = c


func _on_ufo_abducted(winner_id: int) -> void:
	# 페이드 아웃 → 승리 라벨
	var winner: Node2D = players[winner_id] as Node2D
	if winner:
		winner.visible = false
	var t := create_tween()
	t.tween_property(fade_overlay, "color:a", 1.0, 0.45)
	t.tween_callback(Callable(self, "_declare_winner").bind(winner_id))
	t.tween_property(fade_overlay, "color:a", 0.0, 0.45)


func _declare_winner(winner_id: int) -> void:
	_on_player_won(winner_id)


## ── 사망 / 리스폰 ──────────────────────────────────────────

func _on_player_died(victim_id: int, killer_id: int) -> void:
	print("[Game] P%d died (killer=%d)" % [victim_id, killer_id])
	if killer_id != 0 and killer_id != victim_id:
		leader_id = killer_id
		_update_leader_label()
	var victim: Node2D = players.get(victim_id) as Node2D
	if victim == null:
		return
	victim.set_respawn_position(_compute_respawn_position(victim))


## 현재 방 안에서 리더의 진행 방향 쪽으로 리스폰
func _compute_respawn_position(victim: Node2D) -> Vector2:
	var room: Dictionary = rooms_info[current_room_idx]
	var leader: Node2D = players.get(leader_id) as Node2D
	var x: float
	if leader != null and leader.is_alive:
		var ldir: int = int(leader.goal_direction)
		x = leader.global_position.x + ldir * RESPAWN_FORWARD
	else:
		x = room.center_x
	x = clampf(x, room.x_start + RESPAWN_EDGE_PAD, room.x_end - RESPAWN_EDGE_PAD)
	# 구조물 안에 끼지 않도록 보정
	x = _avoid_structure_overlap(x, room)
	return Vector2(x, FLOOR_TOP - 30.0)


## 구조물 없으므로 clamp만 수행
func _avoid_structure_overlap(x: float, room: Dictionary) -> float:
	return clampf(x, room.x_start + RESPAWN_EDGE_PAD, room.x_end - RESPAWN_EDGE_PAD)


## ── 카드 ───────────────────────────────────────────────────

func _on_card_offered(player: Node, card_ids: Array) -> void:
	var ui: Control = CARD_UI_SCENE.instantiate()
	ui.setup(player, card_ids)
	ui_layer.add_child(ui)
	# 카드 선택 중 게임 일시정지 (죽는 플레이어만 ALWAYS로 — 사망 애니메이션 계속 재생)
	get_tree().paused = true
	card_selecting = true
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.card_picked.connect(func(card_id: String):
		player.process_mode = Node.PROCESS_MODE_INHERIT
		get_tree().paused = false
		card_selecting = false
		player.on_card_selected(card_id)
	)


## ── 승리 / 종료 ────────────────────────────────────────────

func _on_player_won(winner_id: int) -> void:
	if game_over:
		return
	game_over = true
	var label_name: String
	if Network.is_local():
		label_name = "P1 (빨강)" if winner_id == 1 else "P2 (파랑)"
	else:
		label_name = "P1 (HOST)" if winner_id == 1 else "P2 (CLIENT)"
	winner_label.text = "%s 승리!\nUFO에 납치당했다…\n메인: ESC 또는 버튼" % label_name
	winner_label.visible = true
	for p in players.values():
		if p:
			p.set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if game_over:
			_go_to_main()
		else:
			_toggle_pause()


func _go_to_main() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.4
	Network.leave_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## ── 일시정지 메뉴 ────────────────────────────────────────────────

func _build_pause_menu() -> void:
	# 반투명 어두운 오버레이
	_pause_overlay = ColorRect.new()
	_pause_overlay.color = Color(0, 0, 0, 0.55)
	_pause_overlay.anchor_left = 0.0
	_pause_overlay.anchor_right = 1.0
	_pause_overlay.anchor_top = 0.0
	_pause_overlay.anchor_bottom = 1.0
	_pause_overlay.offset_left = 0.0
	_pause_overlay.offset_right = 0.0
	_pause_overlay.offset_top = 0.0
	_pause_overlay.offset_bottom = 0.0
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.visible = false
	ui_layer.add_child(_pause_overlay)

	# 중앙 버튼 컨테이너
	_pause_vbox = VBoxContainer.new()
	_pause_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_vbox.anchor_left = 0.5
	_pause_vbox.anchor_right = 0.5
	_pause_vbox.anchor_top = 0.5
	_pause_vbox.anchor_bottom = 0.5
	_pause_vbox.offset_left = -100
	_pause_vbox.offset_right = 100
	_pause_vbox.offset_top = -80
	_pause_vbox.offset_bottom = 80
	_pause_vbox.add_theme_constant_override("separation", 14)
	_pause_overlay.add_child(_pause_vbox)

	# PAUSED 타이틀
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.6, 1))
	_pause_vbox.add_child(title)

	# 남은 시간 표시 (멀티플레이 30초 제한)
	_pause_timer_label = Label.new()
	_pause_timer_label.text = ""
	_pause_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_timer_label.add_theme_font_size_override("font_size", 16)
	_pause_timer_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.8))
	_pause_vbox.add_child(_pause_timer_label)

	# 재개 버튼
	_btn_resume = Button.new()
	_btn_resume.text = "재개"
	_btn_resume.custom_minimum_size = Vector2(180, 44)
	_btn_resume.pressed.connect(_toggle_pause)
	_pause_vbox.add_child(_btn_resume)

	# 다시 시작 버튼
	_btn_restart = Button.new()
	_btn_restart.text = "다시 시작"
	_btn_restart.custom_minimum_size = Vector2(180, 44)
	_btn_restart.pressed.connect(_on_restart_pressed)
	_pause_vbox.add_child(_btn_restart)

	# 메인으로 버튼
	_btn_main_menu = Button.new()
	_btn_main_menu.text = "메인으로"
	_btn_main_menu.custom_minimum_size = Vector2(180, 44)
	_btn_main_menu.pressed.connect(_go_to_main)
	_pause_vbox.add_child(_btn_main_menu)


func _toggle_pause() -> void:
	if game_over:
		return
	_paused = not _paused
	if _paused:
		_pause_timer = PAUSE_MAX_SEC
		get_tree().paused = true
		_pause_overlay.visible = true
		_update_pause_timer_label()
		# 멀티플레이 시 상대에게 PAUSED 알림
		if Network.is_online():
			_notify_pause.rpc(true)
	else:
		get_tree().paused = false
		_pause_overlay.visible = false
		if Network.is_online():
			_notify_pause.rpc(false)


func _update_pause_timer_label() -> void:
	if not _pause_timer_label:
		return
	if Network.is_online():
		_pause_timer_label.text = "%ds 후 자동 재개" % ceili(_pause_timer)
		_pause_timer_label.visible = true
	else:
		_pause_timer_label.visible = false


@rpc("any_peer", "call_remote", "reliable")
func _notify_pause(paused: bool) -> void:
	# 상대 화면에 PAUSED 표시만 (상대는 조작 불가 상태)
	if paused:
		winner_label.text = "PAUSED"
		winner_label.visible = true
	else:
		winner_label.text = ""
		winner_label.visible = false


func _on_restart_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.4
	get_tree().reload_current_scene()
