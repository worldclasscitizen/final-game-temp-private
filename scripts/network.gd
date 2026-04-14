extends Node
## 네트워크 매니저 (Autoload)
## 온라인 연결 관리 + 로컬 2P 모드 플래그 관리.
##
## 모드 구분:
##   - mode == MODE_ONLINE_HOST   : 내가 호스트. ENet 서버 열림.
##   - mode == MODE_ONLINE_CLIENT : 내가 클라이언트. 서버에 접속한 상태.
##   - mode == MODE_LOCAL         : 같은 PC 에서 2P. 네트워킹 없음.
##
## Player / Game 씬은 이 모드를 읽어서 입력 처리 / 동기화 여부를 결정한다.

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected

enum Mode { NONE, ONLINE_HOST, ONLINE_CLIENT, LOCAL }

const DEFAULT_PORT := 9999
const MAX_CLIENTS := 1  # 호스트 + 1명 = 2명

var peer: ENetMultiplayerPeer
var mode: Mode = Mode.NONE
var player_info := {}  # peer_id -> {name: String, ...}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_local() -> bool:
	return mode == Mode.LOCAL


func is_online() -> bool:
	return mode == Mode.ONLINE_HOST or mode == Mode.ONLINE_CLIENT


## ── 모드별 진입 ──────────────────────────────────────────────

func host_game(port: int = DEFAULT_PORT) -> String:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return "포트 %d 를 열 수 없습니다 (err=%d)" % [port, err]
	multiplayer.multiplayer_peer = peer
	mode = Mode.ONLINE_HOST
	player_info[1] = {"name": "Host"}
	return ""


func join_game(address: String, port: int = DEFAULT_PORT) -> String:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return "%s:%d 에 연결할 수 없습니다 (err=%d)" % [address, port, err]
	multiplayer.multiplayer_peer = peer
	mode = Mode.ONLINE_CLIENT
	return ""


func start_local_game() -> void:
	# 로컬 모드: 네트워크 피어 없이 즉시 게임 씬으로 전환
	mode = Mode.LOCAL
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func leave_game() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	mode = Mode.NONE
	player_info.clear()


## ── 시그널 핸들러 ──────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	print("[Network] peer connected: ", id)
	player_info[id] = {"name": "Peer_%d" % id}
	player_connected.emit(id)
	if mode == Mode.ONLINE_HOST and multiplayer.get_peers().size() >= MAX_CLIENTS:
		_start_game.rpc()
		_start_game()


func _on_peer_disconnected(id: int) -> void:
	print("[Network] peer disconnected: ", id)
	player_info.erase(id)
	player_disconnected.emit(id)


func _on_connected_ok() -> void:
	print("[Network] connected to server as ", multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	push_error("[Network] connection failed")
	multiplayer.multiplayer_peer = null
	mode = Mode.NONE


func _on_server_disconnected() -> void:
	print("[Network] server disconnected")
	multiplayer.multiplayer_peer = null
	mode = Mode.NONE
	server_disconnected.emit()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## ── 게임 시작 RPC ─────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
