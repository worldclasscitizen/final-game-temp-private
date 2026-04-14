extends Node
## 카드 정의 DB (Autoload: CardDB)
##
## 기본 총알은 약하다. 카드를 통해 조금씩 강화해 나간다.
## 총알은 맞으면 무조건 사망 — 카드는 오직 "총" 의 특성만 바꾼다.
##
## 총알 스탯:
##   speed_mult / size_mult / homing / bounces / pierces
##   thrust_time_add / gravity_scale_add / drag_scale_add
## 총(플레이어) 스탯:
##   extra_shots (산탄 추가 발사 수)
##   cooldown_mult (발사 간격 배수)

const CARDS := {
	"fast": {
		"name": "고속탄",
		"desc": "탄속이 빨라진다",
		"icon": "»",
		"color": Color(1.0, 0.85, 0.3),
		"stack": { "speed_mult_add": 0.35 },
	},
	"big": {
		"name": "대구경",
		"desc": "탄이 커진다",
		"icon": "◆",
		"color": Color(1.0, 0.5, 0.3),
		"stack": { "size_mult_add": 0.5 },
	},
	"homing": {
		"name": "유도탄",
		"desc": "적을 향해 휜다",
		"icon": "◎",
		"color": Color(0.7, 0.4, 1.0),
		"stack": { "homing_add": 1.6, "thrust_time_add": 0.15 },
	},
	"bounce": {
		"name": "반사탄",
		"desc": "벽에 튕긴다",
		"icon": "⇄",
		"color": Color(0.4, 0.9, 0.9),
		"stack": { "bounces_add": 1 },
	},
	"pierce": {
		"name": "관통탄",
		"desc": "벽을 뚫는다",
		"icon": "⊳",
		"color": Color(0.5, 1.0, 0.5),
		"stack": { "pierces_add": 1 },
	},
	"long_range": {
		"name": "장거리탄",
		"desc": "더 멀리 날아간다",
		"icon": "→",
		"color": Color(0.6, 0.95, 0.7),
		"stack": { "thrust_time_add": 0.3, "drag_scale_add": -0.3 },
	},
	"buoyant": {
		"name": "부양탄",
		"desc": "잘 안 떨어진다",
		"icon": "△",
		"color": Color(0.55, 0.8, 1.0),
		"stack": { "gravity_scale_add": -0.45, "drag_scale_add": -0.35 },
	},
	"spread": {
		"name": "산탄",
		"desc": "부채꼴로 퍼진다",
		"icon": "⁂",
		"color": Color(0.95, 0.65, 0.45),
		"stack": { "extra_shots_add": 2 },
	},
	"rapid": {
		"name": "속사",
		"desc": "재장전이 빨라진다",
		"icon": "⊕",
		"color": Color(0.9, 0.35, 0.55),
		"stack": { "reload_mult_add": -0.25 },
	},
	"heavy": {
		"name": "관성탄",
		"desc": "느리지만 직선으로 간다",
		"icon": "■",
		"color": Color(0.6, 0.55, 0.75),
		"stack": { "size_mult_add": 0.25, "speed_mult_add": -0.15, "drag_scale_add": -0.5 },
	},
	"mag_small": {
		"name": "탄창 +1",
		"desc": "총알 한 발 추가",
		"icon": "▪",
		"color": Color(0.85, 0.85, 0.65),
		"stack": { "mag_add": 1 },
	},
	"mag_mid": {
		"name": "탄창 +3",
		"desc": "총알 세 발 추가, 사거리 감소",
		"icon": "▪▪",
		"color": Color(0.85, 0.75, 0.45),
		"stack": { "mag_add": 3, "thrust_time_add": -0.08, "gravity_scale_add": 0.25 },
	},
	"mag_large": {
		"name": "탄창 +5",
		"desc": "총알 다섯 발 추가, 탄속 감소",
		"icon": "▪▪▪",
		"color": Color(0.9, 0.6, 0.3),
		"stack": { "mag_add": 5, "speed_mult_add": -0.2 },
	},
}


func draw_three() -> Array[String]:
	var ids: Array = CARDS.keys()
	var result: Array[String] = []
	for i in range(3):
		result.append(ids.pick_random())
	return result


func get_card(id: String) -> Dictionary:
	return CARDS.get(id, {})


func compute_bullet_stats(card_ids: Array) -> Dictionary:
	var stats := {
		"speed_mult": 1.0,
		"size_mult": 1.0,
		"homing": 0.0,
		"bounces": 0,
		"pierces": 0,
		"thrust_time_add": 0.0,
		"gravity_scale_add": 0.0,
		"drag_scale_add": 0.0,
		"extra_shots": 0,
		"cooldown_mult": 1.0,
		"mag_add": 0,
		"reload_mult": 1.0,
	}
	for id in card_ids:
		var c: Dictionary = CARDS.get(id, {})
		if c.is_empty():
			continue
		var s: Dictionary = c.get("stack", {})
		stats.speed_mult += s.get("speed_mult_add", 0.0)
		stats.size_mult += s.get("size_mult_add", 0.0)
		stats.homing += s.get("homing_add", 0.0)
		stats.bounces += s.get("bounces_add", 0)
		stats.pierces += s.get("pierces_add", 0)
		stats.thrust_time_add += s.get("thrust_time_add", 0.0)
		stats.gravity_scale_add += s.get("gravity_scale_add", 0.0)
		stats.drag_scale_add += s.get("drag_scale_add", 0.0)
		stats.extra_shots += s.get("extra_shots_add", 0)
		stats.cooldown_mult += s.get("cooldown_mult_add", 0.0)
		stats.mag_add += s.get("mag_add", 0)
		stats.reload_mult += s.get("reload_mult_add", 0.0)
	# 최솟값 clamp
	stats.cooldown_mult = maxf(0.15, stats.cooldown_mult)
	stats.speed_mult = maxf(0.3, stats.speed_mult)
	stats.reload_mult = maxf(0.2, stats.reload_mult)
	return stats
