extends Control
## 메인 메뉴 — 온라인 Host/Join + 로컬 2P

@onready var ip_edit: LineEdit = %IPEdit
@onready var status_label: Label = %StatusLabel
@onready var host_btn: Button = %HostButton
@onready var join_btn: Button = %JoinButton
@onready var local_btn: Button = %LocalButton


func _ready() -> void:
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	local_btn.pressed.connect(_on_local_pressed)
	Network.player_connected.connect(_on_player_connected)
	Network.server_disconnected.connect(func(): status_label.text = "서버 연결이 끊겼습니다.")
	# 이전 게임에서 돌아왔을 수 있으니 상태 초기화
	Network.leave_game()


func _on_host_pressed() -> void:
	var err := Network.host_game()
	if err != "":
		status_label.text = err
		return
	status_label.text = "호스트 시작됨. 상대방 접속 대기중..."
	_lock_buttons()


func _on_join_pressed() -> void:
	var address := ip_edit.text.strip_edges()
	if address == "":
		address = "127.0.0.1"
	var err := Network.join_game(address)
	if err != "":
		status_label.text = err
		return
	status_label.text = "%s 에 접속중..." % address
	_lock_buttons()


func _on_local_pressed() -> void:
	status_label.text = "로컬 2P 시작..."
	_lock_buttons()
	Network.start_local_game()


func _on_player_connected(id: int) -> void:
	status_label.text = "플레이어 %d 연결됨. 게임 시작!" % id


func _lock_buttons() -> void:
	host_btn.disabled = true
	join_btn.disabled = true
	local_btn.disabled = true
