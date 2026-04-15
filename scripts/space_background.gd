extends Node2D
## 프로시저럴 우주 배경 생성기 (Godot 4)
##
## 셰이더 기반 성운 + 별먼지 + 큰 별 + 행성을 생성.
## 카메라 뷰포트 기준으로 요소를 배치하여 실제 플레이 화면에서 예쁘게 보이도록 설계.
##
## 카메라 정보 (game.gd 기준):
##   뷰포트 1400x800, 줌 1.75
##   → 월드 가시 영역: 800 x 457
##   카메라 Y 고정 = MAP_HEIGHT/2 = 360
##   → 가시 Y 범위: 약 131 ~ 589
##   바닥(FLOOR_TOP) = 480  →  하늘 영역: 131 ~ 480 (약 350px)

const NEBULAE_SHADER := preload("res://assets/background/nebulae.gdshader")
const STARSTUFF_SHADER := preload("res://assets/background/starstuff.gdshader")
const BIGSTAR_SHADER := preload("res://assets/background/bigstar.gdshader")
const PLANET_SHADER := preload("res://assets/background/planet.gdshader")
const STAR_TEX := preload("res://assets/background/stars.png")
const STAR_SPECIAL_TEX := preload("res://assets/background/stars-special.png")
const PLANET_TEX := preload("res://assets/background/100x100.png")

var _colorscheme: GradientTexture1D
var _bg_color := Color(0.09, 0.09, 0.067, 1.0)

var _map_w := 1400.0
var _map_h := 720.0

# 카메라가 보는 실제 영역 (월드 좌표)
const CAM_Y := 360.0
const VIEW_W := 800.0    # 1400 / 1.75
const VIEW_H := 457.0    # 800 / 1.75
const SKY_TOP := 131.0   # CAM_Y - VIEW_H/2
const SKY_BOTTOM := 480.0  # FLOOR_TOP — 하늘과 땅의 경계

var _star_objects: Array[Sprite2D] = []
var _planet_objects: Array[Sprite2D] = []


func _init() -> void:
	name = "SpaceBackground"


func generate(map_width: float, map_height: float) -> void:
	_map_w = map_width
	_map_h = map_height

	for c in get_children():
		c.queue_free()
	_star_objects.clear()
	_planet_objects.clear()

	_build_colorscheme()

	# ── 1) 배경색 ──
	var bg_rect := ColorRect.new()
	bg_rect.offset_right = _map_w
	bg_rect.offset_bottom = _map_h
	bg_rect.color = _bg_color
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_rect.z_index = -10
	add_child(bg_rect)

	# ── 셰이더 공통 파라미터 ──
	var aspect := Vector2(_map_w / _map_h, 1.0)
	var pix := maxf(_map_w, _map_h)

	# ── 2) StarStuff (별먼지) ──
	var dust := _make_shader_rect(STARSTUFF_SHADER)
	dust.material.set_shader_parameter("seed", randf_range(1.0, 10.0))
	dust.material.set_shader_parameter("pixels", pix)
	dust.material.set_shader_parameter("size", 10.0)
	dust.material.set_shader_parameter("OCTAVES", 6)
	dust.material.set_shader_parameter("uv_correct", aspect)
	dust.material.set_shader_parameter("colorscheme", _colorscheme)
	dust.z_index = -9
	add_child(dust)

	# ── 3) 작은 별 ──
	_spawn_small_stars()

	# ── 4) Nebulae (성운) ──
	var neb := _make_shader_rect(NEBULAE_SHADER)
	neb.material.set_shader_parameter("seed", randf_range(1.0, 10.0))
	neb.material.set_shader_parameter("pixels", pix)
	neb.material.set_shader_parameter("size", 5.0)
	neb.material.set_shader_parameter("OCTAVES", 4)
	neb.material.set_shader_parameter("uv_correct", aspect)
	neb.material.set_shader_parameter("colorscheme", _colorscheme)
	neb.material.set_shader_parameter("background_color", _bg_color)
	neb.material.set_shader_parameter("should_tile", true)
	neb.z_index = -8
	add_child(neb)

	# ── 5) 큰 별 (하늘 영역에만 배치) ──
	_spawn_big_stars()

	# ── 6) 행성 (뷰포트 단위로 분배) ──
	_spawn_planets()


func _build_colorscheme() -> void:
	_colorscheme = GradientTexture1D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.143, 0.286, 0.429, 0.571, 0.714, 0.857, 1.0])
	grad.colors = PackedColorArray([
		Color(0.125, 0.133, 0.082, 1),
		Color(0.227, 0.157, 0.008, 1),
		Color(0.588, 0.235, 0.235, 1),
		Color(0.792, 0.353, 0.180, 1),
		Color(1.000, 0.471, 0.192, 1),
		Color(0.953, 0.600, 0.286, 1),
		Color(0.922, 0.761, 0.459, 1),
		Color(0.875, 0.843, 0.522, 1),
	])
	_colorscheme.gradient = grad


func _make_shader_rect(shader: Shader) -> ColorRect:
	var rect := ColorRect.new()
	rect.offset_right = _map_w
	rect.offset_bottom = _map_h
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	return rect


## ── 작은 별 ─────────────────────────────────────────────────
func _spawn_small_stars() -> void:
	# 하늘 영역에만 배치 (바닥 아래는 안 보임)
	var sky_area := _map_w * (SKY_BOTTOM - SKY_TOP)
	var count := int(sky_area / 8000.0)
	count = clampi(count, 20, 300)

	var container := Node2D.new()
	container.name = "SmallStars"
	container.z_index = -9
	add_child(container)

	for i in count:
		var star := Sprite2D.new()
		star.texture = STAR_TEX
		star.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		star.hframes = 16
		star.frame = randi() % 16
		# 하늘 영역 안에서만 배치
		star.position = Vector2(
			randf_range(0, _map_w),
			randf_range(SKY_TOP - 20.0, SKY_BOTTOM)
		)
		var col_val := floorf(randf() * 7.0) / 7.0
		star.modulate = _colorscheme.gradient.sample(col_val)
		star.modulate.a = randf_range(0.4, 1.0)
		var s := randf_range(0.5, 1.0)
		star.scale = Vector2(s, s)
		container.add_child(star)


## ── 큰 별 (십자형 반짝이) ────────────────────────────────────
func _spawn_big_stars() -> void:
	# 뷰포트 1개당 2~4개 정도
	var num_views := _map_w / VIEW_W
	var count := int(num_views * 3.0)
	count = clampi(count, 6, 40)

	for i in count:
		var star := Sprite2D.new()
		star.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var atlas := AtlasTexture.new()
		atlas.atlas = STAR_SPECIAL_TEX
		atlas.region = Rect2((randi() % 5) * 25, 0, 25, 25)
		star.texture = atlas

		var mat := ShaderMaterial.new()
		mat.shader = BIGSTAR_SHADER
		mat.set_shader_parameter("colorscheme", _colorscheme)
		star.material = mat

		star.position = Vector2(
			randf_range(20, _map_w - 20),
			randf_range(SKY_TOP, SKY_BOTTOM - 40.0)
		)
		star.z_index = -7
		add_child(star)
		_star_objects.append(star)


## ── 행성 배치 ────────────────────────────────────────────────
## 맵을 뷰포트 단위 구간으로 나누고, 각 구간에 확률적으로 행성 배치.
## 메인 행성 1개는 반드시 스폰룸(중앙) 근처에 배치.
func _spawn_planets() -> void:
	# 스폰룸 중심 X (game.gd의 ROOMS_CFG 기준: 0~3번방 폭 합 + 4번방 폭/2)
	# 1000 + 800 + 1400 + 1000 = 4200, +500 = 4700
	var spawn_center_x := 4700.0
	if spawn_center_x > _map_w:
		spawn_center_x = _map_w * 0.5

	# 하늘 영역의 중심 Y (카메라가 보는 영역의 세로 중심)
	var sky_center_y := (SKY_TOP + SKY_BOTTOM) * 0.5  # ≈ 305
	var sky_height := SKY_BOTTOM - SKY_TOP             # ≈ 350

	# ── 메인 행성: 화면의 약 35~50%를 차지하는 큰 행성 ──
	var main_diameter := sky_height * randf_range(0.35, 0.50)  # 120~175px
	var main_scale := main_diameter / 100.0
	# pixels 파라미터: 셰이더 내부 해상도. 너무 낮으면 도트가 커지고, 너무 높으면 노이즈가 미세해짐.
	# 참고 이미지처럼 픽셀아트 느낌이면서도 부드러운 수준 = 60~100 정도가 적당
	var main_planet := _create_planet_sprite(main_scale, 80)
	main_planet.position = Vector2(
		spawn_center_x + randf_range(-VIEW_W * 0.3, VIEW_W * 0.3),
		sky_center_y + randf_range(-40.0, 40.0)
	)
	main_planet.z_index = -7
	add_child(main_planet)
	_planet_objects.append(main_planet)

	# ── 서브 행성들: 맵 곳곳에 작은 행성/위성 배치 ──
	# 뷰포트 구간을 나눠서 확률적으로 배치
	var segment_w := VIEW_W * 1.2  # 뷰포트보다 살짝 넓은 구간
	var num_segments := int(_map_w / segment_w)

	for seg_i in num_segments:
		var seg_center_x := segment_w * (float(seg_i) + 0.5)

		# 메인 행성이 이 구간에 있으면 스킵
		if absf(seg_center_x - main_planet.position.x) < VIEW_W * 0.5:
			continue

		# 60% 확률로 이 구간에 작은 행성 배치
		if randf() > 0.6:
			continue

		var sub_diameter := sky_height * randf_range(0.12, 0.25)  # 42~87px
		var sub_scale := sub_diameter / 100.0
		var sub_planet := _create_planet_sprite(sub_scale, 60)
		sub_planet.position = Vector2(
			seg_center_x + randf_range(-segment_w * 0.3, segment_w * 0.3),
			randf_range(SKY_TOP + 30.0, SKY_BOTTOM - sub_diameter * 0.5 - 20.0)
		)
		sub_planet.z_index = -7
		add_child(sub_planet)
		_planet_objects.append(sub_planet)


func _create_planet_sprite(s: float, pixel_detail: int) -> Sprite2D:
	var planet := Sprite2D.new()
	planet.texture = PLANET_TEX
	planet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var mat := ShaderMaterial.new()
	mat.shader = PLANET_SHADER
	mat.set_shader_parameter("seed", randf_range(1.0, 10.0))
	mat.set_shader_parameter("light_origin", Vector2(randf_range(0.2, 0.45), randf_range(0.2, 0.45)))
	mat.set_shader_parameter("pixels", pixel_detail)
	mat.set_shader_parameter("size", randf_range(4.0, 7.0))
	mat.set_shader_parameter("OCTAVES", 4)
	mat.set_shader_parameter("colorscheme", _colorscheme)
	planet.material = mat
	planet.scale = Vector2(s, s)
	return planet
