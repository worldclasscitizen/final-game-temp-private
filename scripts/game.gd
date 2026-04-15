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
## 구조물 설계 철학:
## - 점프로 넘을 수 있는 것은 확실히 낮게 (h ≤ 35)
## - 문이 있는 건물은 양쪽 통행 보장 (door_side="both")
## - 구조물 사이 최소 150px 여유 공간 확보
## - 복도는 천장이 낮아 점프가 제한되는 압박감
## 플레이어 점프 최대 높이 ≈ 약 96px (JUMP_VELOCITY²/(2*GRAVITY))
## → 35px 박스: 확실히 넘음, 60px: 간신히 넘음, 80px+: 넘지 못함
const STRUCTURE_LAYOUTS := {
	"ufo_left": [
		# UFO 방: 심플하게 낮은 박스 하나
		{"type": "box_stack", "x": 550, "boxes": [{"w": 90, "h": 30}]},
	],
	"ufo_right": [
		{"type": "box_stack", "x": 450, "boxes": [{"w": 90, "h": 30}]},
	],
	"corridor": [
		# 복도: 천장 낮음 (점프 거의 불가) + 장애물 없음 → 순수 달리기/사격전
		{"type": "ceiling", "h": 140},
	],
	"wide": [
		# 넓은 안뜰: 양끝에 넘을 수 있는 박스 + 중앙에 건물 1개
		{"type": "box_stack", "x": 220, "boxes": [{"w": 80, "h": 30}]},
		{"type": "building", "x": 650, "w": 200, "h": 150, "door_side": "both"},
		{"type": "box_stack", "x": 1100, "boxes": [{"w": 80, "h": 30}]},
	],
	"warehouse": [
		# 창고: 넘을 수 있는 낮은 박스들이 간격을 두고 배치
		{"type": "box_stack", "x": 250, "boxes": [{"w": 100, "h": 30}]},
		{"type": "box_stack", "x": 550, "boxes": [{"w": 80, "h": 35}, {"w": 50, "h": 30}]},
		{"type": "box_stack", "x": 800, "boxes": [{"w": 100, "h": 30}]},
	],
	"center": [
		# 아레나: 중앙에 건물 하나, 여유로운 공간
		{"type": "building_roof", "x": 500, "w": 180, "h": 120, "door_side": "both"},
	],
	"fortress": [
		# 요새: 높은 건물 1개 (넘지 못함 → 문으로 통과)
		{"type": "multi_room", "x": 500, "w": 240, "h": 180, "rooms": 2},
	],
}

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

	# 배경 전체 크기
	background.offset_right = cursor_x
	background.offset_bottom = float(MAP_HEIGHT)

	for i in rooms_info.size():
		_build_room_content(i)


func _build_room_content(idx: int) -> void:
	var room: Dictionary = rooms_info[idx]
	var palette: Dictionary = PALETTES[room.palette]

	var room_node := Node2D.new()
	room_node.name = "Room%d" % idx
	map_root.add_child(room_node)

	# 방 배경
	var bg := ColorRect.new()
	bg.offset_left = room.x_start
	bg.offset_right = room.x_end
	bg.offset_top = 0.0
	bg.offset_bottom = float(MAP_HEIGHT)
	bg.color = palette.bg
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_node.add_child(bg)

	# 중세 배경 (하늘 그라데이션 / 먼 언덕 or 성벽 실루엣)
	_build_medieval_backdrop(room_node, room, palette)

	# 방 구분선(엣지)
	_make_divider(room_node, room.x_end, palette.accent)

	# 방 번호 표시 (희미하게)
	var roomnum := Label.new()
	roomnum.text = "ROOM %d" % idx
	roomnum.position = Vector2(room.x_start + 20, 30)
	roomnum.add_theme_color_override("font_color", palette.accent * Color(1, 1, 1, 0.5))
	roomnum.add_theme_font_size_override("font_size", 14)
	room_node.add_child(roomnum)

	# 바닥 (각 방 독립)
	_make_static_box(room_node, room.x_start + room.w * 0.5, FLOOR_CENTER_Y, room.w, 160.0, palette.plat.darkened(0.35))
	# 바닥 윗면 벽돌 디테일
	_build_floor_bricks(room_node, room, palette)

	# 맵 양끝 벽
	if idx == 0:
		_make_static_box(room_node, room.x_start + 10.0, 360.0, 20.0, 720.0, palette.plat)
	if idx == rooms_info.size() - 1:
		_make_static_box(room_node, room.x_end - 10.0, 360.0, 20.0, 720.0, palette.plat)

	# 구조물
	var structures: Array = STRUCTURE_LAYOUTS.get(room.type, [])
	for s in structures:
		_build_structure(room_node, room, palette, s)

	# 전경 데코 (횃불 / 배너 / 풀)
	_build_foreground_decor(room_node, room, palette)

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


## ── 구조물 빌더 ─────────────────────────────────────────────

func _build_structure(parent: Node2D, room: Dictionary, palette: Dictionary, s: Dictionary) -> void:
	var stype: String = s.get("type", "platform")
	match stype:
		"box_stack":
			_build_box_stack(parent, room, palette, s)
		"building":
			_build_building(parent, room, palette, s, false)
		"building_roof":
			_build_building(parent, room, palette, s, true)
		"multi_room":
			_build_multi_room(parent, room, palette, s)
		"ceiling":
			_build_ceiling(parent, room, palette, s)
		"platform":
			var px: float = room.x_start + float(s.get("x", 0))
			_make_static_box(parent, px, float(s.get("y", 400)), float(s.get("w", 200)), 20.0, palette.plat)


## 쌓인 상자: 바닥에서부터 위로 쌓아올림. 위로 갈수록 작아짐.
func _build_box_stack(parent: Node2D, room: Dictionary, palette: Dictionary, s: Dictionary) -> void:
	var cx: float = room.x_start + float(s.get("x", 500))
	var boxes: Array = s.get("boxes", [])
	var y_cursor: float = FLOOR_TOP  # 바닥 표면부터 시작
	var wall_color: Color = palette.plat.lightened(0.05)
	var edge_color: Color = palette.plat.lightened(0.20)
	var dark_color: Color = palette.plat.darkened(0.15)

	for i in boxes.size():
		var bw: float = float(boxes[i].get("w", 100))
		var bh: float = float(boxes[i].get("h", 50))
		var box_top: float = y_cursor - bh
		var box_center_y: float = y_cursor - bh * 0.5

		# 충돌체
		_make_static_box(parent, cx, box_center_y, bw, bh, wall_color)

		# 시각적 디테일: 상단 하이라이트
		var hi := ColorRect.new()
		hi.offset_left = cx - bw * 0.5
		hi.offset_right = cx + bw * 0.5
		hi.offset_top = box_top
		hi.offset_bottom = box_top + 2.0
		hi.color = edge_color
		hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(hi)

		# 하단 그림자
		var shadow := ColorRect.new()
		shadow.offset_left = cx - bw * 0.5
		shadow.offset_right = cx + bw * 0.5
		shadow.offset_top = y_cursor - 2.0
		shadow.offset_bottom = y_cursor
		shadow.color = dark_color
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(shadow)

		y_cursor = box_top  # 다음 상자는 이 위에


## 건물: 벽 + 지붕 + 문. roof_jumpable=true 이면 지붕 위에 올라갈 수 있음.
func _build_building(parent: Node2D, room: Dictionary, palette: Dictionary,
		s: Dictionary, roof_jumpable: bool) -> void:
	var cx: float = room.x_start + float(s.get("x", 500))
	var bw: float = float(s.get("w", 240))
	var bh: float = float(s.get("h", 200))
	var door_side: String = s.get("door_side", "both")
	var wall_thick := 16.0
	var roof_thick: float = 12.0 if roof_jumpable else 20.0
	var door_w := 44.0
	var door_h := 80.0

	var left: float = cx - bw * 0.5
	var right: float = cx + bw * 0.5
	var top: float = FLOOR_TOP - bh
	var wall_color: Color = palette.plat.lightened(0.08)
	var roof_color: Color = palette.plat.lightened(0.15)
	var inner_color: Color = palette.bg.darkened(0.15)

	# 내부 배경 (어두운 색으로 채우기)
	var inner := ColorRect.new()
	inner.offset_left = left + wall_thick
	inner.offset_right = right - wall_thick
	inner.offset_top = top + roof_thick
	inner.offset_bottom = FLOOR_TOP
	inner.color = inner_color
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(inner)

	# 지붕 (플랫폼)
	_make_static_box(parent, cx, top + roof_thick * 0.5, bw, roof_thick, roof_color)
	# 지붕 상단 하이라이트
	var rh := ColorRect.new()
	rh.offset_left = left
	rh.offset_right = right
	rh.offset_top = top
	rh.offset_bottom = top + 2.0
	rh.color = roof_color.lightened(0.15)
	rh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rh)

	# 왼벽
	var has_left_door: bool = (door_side == "left" or door_side == "both")
	if has_left_door:
		# 문 위쪽 벽
		var wall_above_h: float = bh - roof_thick - door_h
		if wall_above_h > 0:
			_make_static_box(parent, left + wall_thick * 0.5,
				top + roof_thick + wall_above_h * 0.5,
				wall_thick, wall_above_h, wall_color)
		# 문턱 시각 표시 (문 윗부분 가로 바)
		var lintel := ColorRect.new()
		lintel.offset_left = left
		lintel.offset_right = left + door_w + 4.0
		lintel.offset_top = FLOOR_TOP - door_h - 4.0
		lintel.offset_bottom = FLOOR_TOP - door_h
		lintel.color = wall_color.darkened(0.1)
		lintel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(lintel)
	else:
		# 풀 왼벽
		_make_static_box(parent, left + wall_thick * 0.5,
			top + roof_thick + (bh - roof_thick) * 0.5,
			wall_thick, bh - roof_thick, wall_color)

	# 오른벽
	var has_right_door: bool = (door_side == "right" or door_side == "both")
	if has_right_door:
		var wall_above_h: float = bh - roof_thick - door_h
		if wall_above_h > 0:
			_make_static_box(parent, right - wall_thick * 0.5,
				top + roof_thick + wall_above_h * 0.5,
				wall_thick, wall_above_h, wall_color)
		var lintel := ColorRect.new()
		lintel.offset_left = right - door_w - 4.0
		lintel.offset_right = right
		lintel.offset_top = FLOOR_TOP - door_h - 4.0
		lintel.offset_bottom = FLOOR_TOP - door_h
		lintel.color = wall_color.darkened(0.1)
		lintel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(lintel)
	else:
		_make_static_box(parent, right - wall_thick * 0.5,
			top + roof_thick + (bh - roof_thick) * 0.5,
			wall_thick, bh - roof_thick, wall_color)


## 다중 방 건물: 내부에 칸막이가 있고, 각 칸막이에 문이 있음.
func _build_multi_room(parent: Node2D, room: Dictionary, palette: Dictionary, s: Dictionary) -> void:
	var cx: float = room.x_start + float(s.get("x", 640))
	var bw: float = float(s.get("w", 280))
	var bh: float = float(s.get("h", 220))
	var num_rooms: int = int(s.get("rooms", 2))
	var wall_thick := 16.0
	var roof_thick := 12.0
	var door_w := 44.0
	var door_h := 80.0
	var divider_thick := 10.0

	var left: float = cx - bw * 0.5
	var right: float = cx + bw * 0.5
	var top: float = FLOOR_TOP - bh
	var wall_color: Color = palette.plat.lightened(0.08)
	var roof_color: Color = palette.plat.lightened(0.15)
	var inner_color: Color = palette.bg.darkened(0.15)
	var divider_color: Color = palette.plat

	# 내부 배경
	var inner := ColorRect.new()
	inner.offset_left = left + wall_thick
	inner.offset_right = right - wall_thick
	inner.offset_top = top + roof_thick
	inner.offset_bottom = FLOOR_TOP
	inner.color = inner_color
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(inner)

	# 지붕 (플랫폼 — 위에 올라갈 수 있음)
	_make_static_box(parent, cx, top + roof_thick * 0.5, bw, roof_thick, roof_color)
	var rh := ColorRect.new()
	rh.offset_left = left
	rh.offset_right = right
	rh.offset_top = top
	rh.offset_bottom = top + 2.0
	rh.color = roof_color.lightened(0.15)
	rh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rh)

	# 양 외벽 (문 있음)
	# 왼벽: 문 있음
	var wall_above_h: float = bh - roof_thick - door_h
	if wall_above_h > 0:
		_make_static_box(parent, left + wall_thick * 0.5,
			top + roof_thick + wall_above_h * 0.5,
			wall_thick, wall_above_h, wall_color)
	# 오른벽: 문 있음
	if wall_above_h > 0:
		_make_static_box(parent, right - wall_thick * 0.5,
			top + roof_thick + wall_above_h * 0.5,
			wall_thick, wall_above_h, wall_color)

	# 내부 칸막이 (문 포함)
	var inner_w: float = bw - wall_thick * 2.0
	for i in range(1, num_rooms):
		var div_x: float = left + wall_thick + inner_w * (float(i) / float(num_rooms))
		# 칸막이 윗부분 (문 위)
		if wall_above_h > 0:
			_make_static_box(parent, div_x,
				top + roof_thick + wall_above_h * 0.5,
				divider_thick, wall_above_h, divider_color)
		# 문턱 시각 표시
		var lintel := ColorRect.new()
		lintel.offset_left = div_x - door_w * 0.5 - 2.0
		lintel.offset_right = div_x + door_w * 0.5 + 2.0
		lintel.offset_top = FLOOR_TOP - door_h - 4.0
		lintel.offset_bottom = FLOOR_TOP - door_h
		lintel.color = divider_color.darkened(0.1)
		lintel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(lintel)


## 복도 천장: 방 전체에 천장을 덮어서 밀폐감 제공.
func _build_ceiling(parent: Node2D, room: Dictionary, palette: Dictionary, s: Dictionary) -> void:
	var ceil_h: float = float(s.get("h", 160))
	var ceil_y: float = ceil_h  # 천장 위치 (맵 상단에서 h 만큼)
	var ceil_thick := 20.0
	var wall_color: Color = palette.plat.lightened(0.05)

	# 천장 StaticBody
	_make_static_box(parent, room.x_start + room.w * 0.5, ceil_y,
		room.w, ceil_thick, wall_color)

	# 천장 위 채움 (시각적으로 어두운 영역)
	var fill := ColorRect.new()
	fill.offset_left = room.x_start
	fill.offset_right = room.x_end
	fill.offset_top = 0
	fill.offset_bottom = ceil_y - ceil_thick * 0.5
	fill.color = palette.bg.darkened(0.3)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fill)

	# 천장 하단 하이라이트
	var hi := ColorRect.new()
	hi.offset_left = room.x_start
	hi.offset_right = room.x_end
	hi.offset_top = ceil_y + ceil_thick * 0.5
	hi.offset_bottom = ceil_y + ceil_thick * 0.5 + 2.0
	hi.color = wall_color.darkened(0.2)
	hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hi)


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


## ── 중세 배경 데코 ─────────────────────────────────────────

const DECOR_OUTDOOR := ["wide", "ufo_left", "ufo_right"]

# 광원용 라디얼 그라디언트 텍스처 (캐시)
var _light_tex: GradientTexture2D = null

func _get_light_texture() -> GradientTexture2D:
	if _light_tex != null:
		return _light_tex
	_light_tex = GradientTexture2D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	_light_tex.gradient = grad
	_light_tex.fill = GradientTexture2D.FILL_RADIAL
	_light_tex.fill_from = Vector2(0.5, 0.5)
	_light_tex.fill_to = Vector2(0.5, 0.0)
	_light_tex.width = 256
	_light_tex.height = 256
	return _light_tex


func _build_medieval_backdrop(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	if DECOR_OUTDOOR.has(room.type):
		_build_sky_strip(parent, room, palette)
		if room.type == "ufo_left" or room.type == "ufo_right":
			_build_night_details(parent, room, palette)
		elif room.type == "wide":
			_build_sun(parent, room, palette)
		_build_distant_silhouette(parent, room, palette)
	else:
		_build_interior_wall(parent, room, palette)
		_build_columns(parent, room, palette)


func _build_sky_strip(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	# 상단 하늘 (살짝 밝게) — 그라데이션 대용으로 2단 분할
	var sky := ColorRect.new()
	sky.offset_left = room.x_start
	sky.offset_right = room.x_end
	sky.offset_top = 0.0
	sky.offset_bottom = 300.0
	sky.color = palette.bg.lightened(0.12)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sky)
	var mid := ColorRect.new()
	mid.offset_left = room.x_start
	mid.offset_right = room.x_end
	mid.offset_top = 300.0
	mid.offset_bottom = FLOOR_TOP
	mid.color = palette.bg.lightened(0.05)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(mid)


func _build_night_details(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	# 달
	var moon_x: float = room.x_start + (240.0 if room.type == "ufo_left" else room.w - 240.0)
	var moon := ColorRect.new()
	moon.offset_left = moon_x - 26.0
	moon.offset_right = moon_x + 26.0
	moon.offset_top = 70.0
	moon.offset_bottom = 122.0
	moon.color = Color(0.95, 0.93, 0.82, 0.9)
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(moon)
	# 달의 크레이터
	for d in [[-8.0, 8.0, 3.0], [6.0, -4.0, 2.5], [2.0, 12.0, 2.0]]:
		var cr := ColorRect.new()
		cr.offset_left = moon_x + d[0] - d[2]
		cr.offset_right = moon_x + d[0] + d[2]
		cr.offset_top = 96.0 + d[1] - d[2]
		cr.offset_bottom = 96.0 + d[1] + d[2]
		cr.color = Color(0.82, 0.80, 0.70, 0.85)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(cr)
	# ── 달빛 PointLight2D ──
	var moon_light := PointLight2D.new()
	moon_light.texture = _get_light_texture()
	moon_light.position = Vector2(moon_x, 96.0)
	moon_light.color = Color(0.7, 0.75, 0.95)      # 차가운 달빛
	moon_light.energy = 0.35
	moon_light.texture_scale = 6.0
	moon_light.blend_mode = PointLight2D.BLEND_MODE_ADD
	parent.add_child(moon_light)
	# 별
	var rng := RandomNumberGenerator.new()
	rng.seed = int(room.x_start) + 31
	for i in 34:
		var sx: float = room.x_start + rng.randf() * room.w
		var sy: float = 20.0 + rng.randf() * 260.0
		var ssz: float = 1.2 + rng.randf() * 1.6
		var star := ColorRect.new()
		star.offset_left = sx - ssz
		star.offset_right = sx + ssz
		star.offset_top = sy - ssz
		star.offset_bottom = sy + ssz
		star.color = Color(1, 1, 0.9, 0.55 + rng.randf() * 0.35)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(star)


func _build_sun(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	# 해 위치 — 방 중앙 약간 우측 상단
	var sun_x: float = room.x_start + room.w * 0.65
	var sun_y: float = 72.0
	# 해 외곽 글로우 (큰 원)
	var glow := ColorRect.new()
	glow.offset_left = sun_x - 60.0
	glow.offset_right = sun_x + 60.0
	glow.offset_top = sun_y - 60.0
	glow.offset_bottom = sun_y + 60.0
	glow.color = Color(1.0, 0.95, 0.7, 0.12)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(glow)
	# 해 본체
	var sun_body := ColorRect.new()
	sun_body.offset_left = sun_x - 22.0
	sun_body.offset_right = sun_x + 22.0
	sun_body.offset_top = sun_y - 22.0
	sun_body.offset_bottom = sun_y + 22.0
	sun_body.color = Color(1.0, 0.96, 0.78, 0.95)
	sun_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sun_body)
	# 해 내심 (밝은 중심)
	var sun_core := ColorRect.new()
	sun_core.offset_left = sun_x - 12.0
	sun_core.offset_right = sun_x + 12.0
	sun_core.offset_top = sun_y - 12.0
	sun_core.offset_bottom = sun_y + 12.0
	sun_core.color = Color(1.0, 1.0, 0.92, 1.0)
	sun_core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sun_core)
	# ── PointLight2D: 넓은 햇빛 광원 ──
	var sun_light := PointLight2D.new()
	sun_light.texture = _get_light_texture()
	sun_light.position = Vector2(sun_x, sun_y)
	sun_light.color = Color(1.0, 0.95, 0.8)       # 따뜻한 햇빛
	sun_light.energy = 0.45
	sun_light.texture_scale = 8.0                   # 넓은 반경
	sun_light.blend_mode = PointLight2D.BLEND_MODE_ADD
	parent.add_child(sun_light)


func _build_distant_silhouette(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	# 먼 성/언덕 실루엣 (하단이 바닥 라인에 붙는 Polygon2D)
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	var base_y: float = FLOOR_TOP
	var rng := RandomNumberGenerator.new()
	rng.seed = int(room.x_start) * 7 + 11
	pts.append(Vector2(room.x_start, base_y))
	var x: float = room.x_start
	var top_base := 430.0
	while x < room.x_end:
		var seg_w: float = 70.0 + rng.randf() * 40.0
		var h: float = top_base + rng.randf_range(-20.0, 25.0)
		# 확률적으로 성탑(크레넬레이션)
		if rng.randf() < 0.28 and x + 40.0 < room.x_end:
			pts.append(Vector2(x, h))
			pts.append(Vector2(x, h - 55.0))
			pts.append(Vector2(x + 12.0, h - 55.0))
			pts.append(Vector2(x + 12.0, h - 66.0))
			pts.append(Vector2(x + 24.0, h - 66.0))
			pts.append(Vector2(x + 24.0, h - 55.0))
			pts.append(Vector2(x + 36.0, h - 55.0))
			pts.append(Vector2(x + 36.0, h))
			x += 40.0
		else:
			pts.append(Vector2(x, h))
			x += seg_w
	pts.append(Vector2(room.x_end, base_y))
	poly.polygon = pts
	poly.color = palette.bg.lightened(0.18).darkened(0.25)
	parent.add_child(poly)


func _build_interior_wall(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	# 실내 벽 톤 (바닥 위 구역을 bg 보다 살짝 밝게)
	var wall := ColorRect.new()
	wall.offset_left = room.x_start
	wall.offset_right = room.x_end
	wall.offset_top = 0.0
	wall.offset_bottom = FLOOR_TOP
	wall.color = palette.bg.lightened(0.06)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(wall)
	# 가로 벽돌 음각 라인
	for i in 9:
		var ly: float = 70.0 + float(i) * 55.0
		if ly > FLOOR_TOP - 30.0:
			break
		var line := ColorRect.new()
		line.offset_left = room.x_start
		line.offset_right = room.x_end
		line.offset_top = ly
		line.offset_bottom = ly + 1.2
		line.color = Color(palette.bg.r, palette.bg.g, palette.bg.b, 0.7)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(line)
	# 세로 돌결 (엇갈려)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(room.x_start) * 13 + 3
	for i in 9:
		var ly: float = 70.0 + float(i) * 55.0
		if ly > FLOOR_TOP - 30.0:
			break
		var sx: float = room.x_start
		var offset: float = 60.0 if i % 2 == 0 else 0.0
		sx += offset
		while sx < room.x_end:
			var seam := ColorRect.new()
			seam.offset_left = sx
			seam.offset_right = sx + 1.2
			seam.offset_top = ly
			seam.offset_bottom = ly + 55.0
			seam.color = Color(palette.bg.r, palette.bg.g, palette.bg.b, 0.5)
			seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(seam)
			sx += 120.0


func _build_columns(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	var positions: Array = [room.x_start + 80.0, room.x_end - 80.0]
	if room.type == "center":
		positions = [room.x_start + 80.0, room.x_start + room.w * 0.5, room.x_end - 80.0]
	for cx in positions:
		# 기둥 본체
		var col := ColorRect.new()
		col.offset_left = cx - 14.0
		col.offset_right = cx + 14.0
		col.offset_top = 80.0
		col.offset_bottom = FLOOR_TOP
		col.color = palette.plat.darkened(0.2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(col)
		# 세로 홈 (기둥 장식)
		for k in 3:
			var flute := ColorRect.new()
			var fx: float = cx - 8.0 + float(k) * 8.0
			flute.offset_left = fx - 0.8
			flute.offset_right = fx + 0.8
			flute.offset_top = 92.0
			flute.offset_bottom = FLOOR_TOP - 6.0
			flute.color = palette.plat.darkened(0.4)
			flute.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(flute)
		# 상단 캡
		var cap := ColorRect.new()
		cap.offset_left = cx - 22.0
		cap.offset_right = cx + 22.0
		cap.offset_top = 72.0
		cap.offset_bottom = 84.0
		cap.color = palette.plat
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(cap)
		# 하단 베이스
		var base := ColorRect.new()
		base.offset_left = cx - 22.0
		base.offset_right = cx + 22.0
		base.offset_top = FLOOR_TOP - 8.0
		base.offset_bottom = FLOOR_TOP
		base.color = palette.plat
		base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(base)


func _build_floor_bricks(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	## Nidhogg 스타일 다층 지면.
	## 층 구성 (위→아래):
	##   1) 러프 엣지 — 불규칙한 작은 블록으로 표면 질감
	##   2) 표면 하이라이트 — 얇은 밝은 띠
	##   3) 상부 지층 — 밝은 플랫폼 색
	##   4) 중부 지층 — 중간 톤 + 돌/자갈 점
	##   5) 하부 지층 — 어두운 톤 + 깊이감
	##   6) 최하부 — 가장 어두운 바닥

	var rng := RandomNumberGenerator.new()
	rng.seed = int(room.x_start) + 42

	var top: float = FLOOR_TOP
	var is_outdoor: bool = DECOR_OUTDOOR.has(room.type)

	# ── 1) 러프 엣지: 불규칙한 작은 블록이 표면 위로 튀어나옴 ──
	var edge_color: Color = palette.plat.lightened(0.15) if not is_outdoor else palette.plat.lightened(0.05)
	var edge_dark: Color = palette.plat.darkened(0.05)
	var ex: float = room.x_start
	while ex < room.x_end:
		var bw: float = rng.randf_range(6.0, 18.0)
		var bh: float = rng.randf_range(1.5, 5.0)
		if rng.randf() < 0.65:  # 65% 확률로 블록 생성
			var block := ColorRect.new()
			block.offset_left = ex
			block.offset_right = minf(ex + bw, room.x_end)
			block.offset_top = top - bh
			block.offset_bottom = top
			block.color = edge_color if rng.randf() > 0.3 else edge_dark
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(block)
		ex += bw + rng.randf_range(1.0, 8.0)

	# ── 2) 표면 하이라이트 ──
	var hi := ColorRect.new()
	hi.offset_left = room.x_start
	hi.offset_right = room.x_end
	hi.offset_top = top
	hi.offset_bottom = top + 2.0
	hi.color = palette.plat.lightened(0.30)
	hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hi)

	# ── 3) 상부 지층 (6px) ──
	var layer1 := ColorRect.new()
	layer1.offset_left = room.x_start
	layer1.offset_right = room.x_end
	layer1.offset_top = top + 2.0
	layer1.offset_bottom = top + 8.0
	layer1.color = palette.plat
	layer1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer1)

	# 상부 지층에 수평 금 (돌 이음매 느낌)
	var crack_color: Color = palette.plat.darkened(0.20)
	var cx: float = room.x_start + rng.randf_range(20.0, 60.0)
	while cx < room.x_end:
		var cw: float = rng.randf_range(12.0, 50.0)
		if rng.randf() < 0.5:
			var crack := ColorRect.new()
			crack.offset_left = cx
			crack.offset_right = minf(cx + cw, room.x_end)
			crack.offset_top = top + rng.randf_range(3.0, 6.0)
			crack.offset_bottom = crack.offset_top + 1.0
			crack.color = crack_color
			crack.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(crack)
		cx += rng.randf_range(30.0, 80.0)

	# ── 4) 중부 지층 (10px) — 어두운 톤 + 돌/자갈 텍스처 ──
	var mid_y: float = top + 8.0
	var mid_color: Color = palette.plat.darkened(0.25)
	var layer2 := ColorRect.new()
	layer2.offset_left = room.x_start
	layer2.offset_right = room.x_end
	layer2.offset_top = mid_y
	layer2.offset_bottom = mid_y + 10.0
	layer2.color = mid_color
	layer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer2)

	# 자갈/돌 점 (작은 사각형으로 텍스처 표현)
	var pebble_light: Color = palette.plat.darkened(0.10)
	var pebble_dark: Color = palette.plat.darkened(0.40)
	for _i in int(room.w / 12.0):
		var px: float = room.x_start + rng.randf() * room.w
		var py: float = mid_y + rng.randf_range(1.5, 8.0)
		var pw: float = rng.randf_range(2.0, 5.0)
		var ph: float = rng.randf_range(1.5, 3.5)
		var peb := ColorRect.new()
		peb.offset_left = px
		peb.offset_right = px + pw
		peb.offset_top = py
		peb.offset_bottom = py + ph
		peb.color = pebble_light if rng.randf() > 0.5 else pebble_dark
		peb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(peb)

	# 중간 구분선 (희미한 수평선)
	var sep := ColorRect.new()
	sep.offset_left = room.x_start
	sep.offset_right = room.x_end
	sep.offset_top = mid_y + 10.0
	sep.offset_bottom = mid_y + 10.5
	sep.color = palette.plat.darkened(0.50)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sep)

	# ── 5) 하부 지층 (12px) — 깊은 흙/암석 ──
	var deep_y: float = mid_y + 10.5
	var deep_color: Color = palette.plat.darkened(0.45)
	var layer3 := ColorRect.new()
	layer3.offset_left = room.x_start
	layer3.offset_right = room.x_end
	layer3.offset_top = deep_y
	layer3.offset_bottom = deep_y + 12.0
	layer3.color = deep_color
	layer3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer3)

	# 하부 지층 세로 균열
	var deep_crack: Color = palette.plat.darkened(0.55)
	var dcx: float = room.x_start + rng.randf_range(40.0, 100.0)
	while dcx < room.x_end:
		if rng.randf() < 0.4:
			var dc := ColorRect.new()
			dc.offset_left = dcx
			dc.offset_right = dcx + rng.randf_range(1.0, 2.0)
			dc.offset_top = deep_y + rng.randf_range(0.0, 3.0)
			dc.offset_bottom = deep_y + rng.randf_range(6.0, 12.0)
			dc.color = deep_crack
			dc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(dc)
		dcx += rng.randf_range(50.0, 120.0)

	# ── 6) 최하부 — 가장 어두운 영역 (나머지 공간) ──
	var bottom_y: float = deep_y + 12.0
	var layer4 := ColorRect.new()
	layer4.offset_left = room.x_start
	layer4.offset_right = room.x_end
	layer4.offset_top = bottom_y
	layer4.offset_bottom = float(MAP_HEIGHT)
	layer4.color = palette.plat.darkened(0.60)
	layer4.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer4)


func _build_foreground_decor(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	if DECOR_OUTDOOR.has(room.type):
		_build_grass_tufts(parent, room, palette)
	else:
		_build_wall_torches(parent, room, palette)
		_build_banners(parent, room, palette)


func _build_grass_tufts(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(room.x_start) + 7
	var tuft_color := Color(0.38, 0.50, 0.30, 0.95)
	if room.type == "ufo_left" or room.type == "ufo_right":
		tuft_color = Color(0.30, 0.38, 0.25, 0.90)  # 밤이라 어두운 풀
	var count: int = int(room.w / 55.0)
	for i in count:
		var gx: float = room.x_start + 30.0 + rng.randf() * (room.w - 60.0)
		# 풀 더미: 3줄 세로 라인
		for k in 3:
			var ox: float = float(k - 1) * 2.8
			var taller: bool = (k == 1)
			var tall_add: float = 2.0 if taller else 0.0
			var t := ColorRect.new()
			t.offset_left = gx + ox - 0.9
			t.offset_right = gx + ox + 0.9
			t.offset_top = FLOOR_TOP - 5.0 - tall_add
			t.offset_bottom = FLOOR_TOP
			t.color = tuft_color
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(t)


func _build_wall_torches(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	var torch_xs: Array = [room.x_start + 60.0, room.x_end - 60.0]
	if room.type == "center":
		torch_xs.append(room.x_start + room.w * 0.3)
		torch_xs.append(room.x_start + room.w * 0.7)
	for tx in torch_xs:
		_build_torch(parent, tx, 250.0, palette)


func _build_torch(parent: Node2D, x: float, top_y: float, palette: Dictionary) -> void:
	# 받침대 (벽에 박힌 브래킷)
	var bracket := ColorRect.new()
	bracket.offset_left = x - 7.0
	bracket.offset_right = x + 7.0
	bracket.offset_top = top_y - 4.0
	bracket.offset_bottom = top_y + 4.0
	bracket.color = Color(0.18, 0.12, 0.08, 1)
	bracket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bracket)
	# 손잡이(짧은 자루)
	var handle := ColorRect.new()
	handle.offset_left = x - 2.0
	handle.offset_right = x + 2.0
	handle.offset_top = top_y + 4.0
	handle.offset_bottom = top_y + 30.0
	handle.color = Color(0.22, 0.14, 0.1, 1)
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(handle)
	# 불꽃 외곽
	var flame1 := ColorRect.new()
	flame1.offset_left = x - 7.5
	flame1.offset_right = x + 7.5
	flame1.offset_top = top_y - 24.0
	flame1.offset_bottom = top_y - 4.0
	flame1.color = Color(1.0, 0.52, 0.12, 0.95)
	flame1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(flame1)
	# 내심
	var flame2 := ColorRect.new()
	flame2.offset_left = x - 3.5
	flame2.offset_right = x + 3.5
	flame2.offset_top = top_y - 18.0
	flame2.offset_bottom = top_y - 6.0
	flame2.color = Color(1.0, 0.93, 0.55, 1)
	flame2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(flame2)
	# 불빛 헤일로 (희미한 accent)
	var halo := ColorRect.new()
	halo.offset_left = x - 28.0
	halo.offset_right = x + 28.0
	halo.offset_top = top_y - 30.0
	halo.offset_bottom = top_y + 10.0
	halo.color = Color(palette.accent.r, palette.accent.g, palette.accent.b, 0.06)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(halo)
	# ── PointLight2D 실제 광원 ──
	var light := PointLight2D.new()
	light.texture = _get_light_texture()
	light.position = Vector2(x, top_y - 14.0)  # 불꽃 중심
	light.color = Color(1.0, 0.75, 0.35)        # 따뜻한 오렌지
	light.energy = 0.55
	light.texture_scale = 3.0                    # 빛 반경
	light.blend_mode = PointLight2D.BLEND_MODE_ADD
	parent.add_child(light)


func _build_banners(parent: Node2D, room: Dictionary, palette: Dictionary) -> void:
	var banner_xs: Array
	if room.type == "center":
		banner_xs = [room.x_start + room.w * 0.25, room.x_start + room.w * 0.5, room.x_start + room.w * 0.75]
	else:
		banner_xs = [room.x_start + room.w * 0.3, room.x_start + room.w * 0.7]
	for bx in banner_xs:
		# 상단 봉
		var rod := ColorRect.new()
		rod.offset_left = bx - 32.0
		rod.offset_right = bx + 32.0
		rod.offset_top = 60.0
		rod.offset_bottom = 66.0
		rod.color = Color(0.22, 0.15, 0.08, 1)
		rod.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(rod)
		# 배너 본체
		var banner := ColorRect.new()
		banner.offset_left = bx - 28.0
		banner.offset_right = bx + 28.0
		banner.offset_top = 66.0
		banner.offset_bottom = 186.0
		banner.color = palette.accent.darkened(0.25)
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(banner)
		# 하단 V 컷 (삼각형으로 배경색 채워 마감 느낌)
		var cut := Polygon2D.new()
		cut.polygon = PackedVector2Array([
			Vector2(bx - 28.0, 186.0),
			Vector2(bx + 28.0, 186.0),
			Vector2(bx, 208.0),
		])
		cut.color = palette.bg.lightened(0.06)
		parent.add_child(cut)
		# 문양 (다이아몬드)
		var crest := Polygon2D.new()
		crest.polygon = PackedVector2Array([
			Vector2(bx, 104.0),
			Vector2(bx + 10.0, 126.0),
			Vector2(bx, 148.0),
			Vector2(bx - 10.0, 126.0),
		])
		crest.color = palette.accent.lightened(0.2)
		parent.add_child(crest)


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


## 구조물 AABB 와 겹치면 좌우로 밀어냄
func _avoid_structure_overlap(x: float, room: Dictionary) -> float:
	var structures: Array = STRUCTURE_LAYOUTS.get(room.type, [])
	var player_half_w := 8.0  # 플레이어 폭 절반 (충돌 12px + 여유)
	for s in structures:
		var stype: String = s.get("type", "")
		if stype == "ceiling":
			continue
		var sx: float = room.x_start + float(s.get("x", 0))
		var sw: float = float(s.get("w", 0))
		# box_stack: x는 중심, 가장 넓은 박스의 폭 사용
		if stype == "box_stack":
			var boxes: Array = s.get("boxes", [])
			if boxes.size() > 0:
				sw = float(boxes[0].get("w", 60))
		var left: float = sx - sw * 0.5 - player_half_w
		var right: float = sx + sw * 0.5 + player_half_w
		if x > left and x < right:
			# 겹침 — 가까운 쪽으로 밀어냄
			var dist_left: float = x - left
			var dist_right: float = right - x
			if dist_left < dist_right:
				x = left - 10.0
			else:
				x = right + 10.0
	x = clampf(x, room.x_start + RESPAWN_EDGE_PAD, room.x_end - RESPAWN_EDGE_PAD)
	return x


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
      