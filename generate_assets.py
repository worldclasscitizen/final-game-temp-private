#!/usr/bin/env python3
"""
Death Stronger 에셋 — Nidhogg 1 스타일
- 단색 (약간 형광 느낌의 쨍한 색)
- 모래알 노이즈: 색 자체는 하나인데, 픽셀마다 미세한 밝기 변동
- Nidhogg식 프로포션: 각진 머리, 얇은 팔다리, 미니멀 스틱맨
- 외곽선/그림자/명암 전혀 없음
"""

from PIL import Image
import random
import os

OUT = "/sessions/wonderful-exciting-maxwell/mnt/final-game/death-stronger/assets/sprites"
os.makedirs(OUT, exist_ok=True)

# ═══════════════════════════════════════════════════════════════
# 팔레트 — 쨍한 단색 (형광 느낌)
# ═══════════════════════════════════════════════════════════════
# P1: 밝은 형광 오렌지-옐로우 (Nidhogg 오렌지 플레이어 느낌)
P1_COLOR = (235, 190, 60)
# P2: 쨍한 형광 핑크-코랄
P2_COLOR = (220, 95, 85)
# 무기: 밝은 은백색
WEAPON_COLOR = (200, 200, 210)
# 총알: 밝은 백색-옐로우
BULLET_COLOR = (255, 245, 200)
# 바닥: 따뜻한 모래색
FLOOR_COLOR = (120, 100, 75)
FLOOR_LIGHT = (140, 118, 88)
# 구조물: 약간 더 어두운 모래
STRUCT_COLOR = (95, 82, 62)
STRUCT_LIGHT = (108, 94, 72)


def grain(color, intensity=8):
    """모래알 노이즈 — 단색 기반으로 밝기만 미세 변동"""
    r, g, b = color
    d = random.randint(-intensity, intensity)
    return (
        max(0, min(255, r + d)),
        max(0, min(255, g + d)),
        max(0, min(255, b + d)),
        255
    )


def put(img, x, y, color, intensity=8):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), grain(color, intensity))


def fill_shape(img, shape_rows, color, intensity=8):
    """shape_rows: list of strings, '#' = pixel, else transparent"""
    for y, row in enumerate(shape_rows):
        for x, ch in enumerate(row):
            if ch == '#':
                put(img, x, y, color, intensity)


# ═══════════════════════════════════════════════════════════════
# Nidhogg 1 캐릭터 파트 — 단색, 각진, 미니멀
# ═══════════════════════════════════════════════════════════════

def make_head(color, prefix):
    """Nidhogg식 머리: 작은 직사각형, 약간 세로로 긺. 5x6"""
    w, h = 5, 6
    img = Image.new("RGBA", (w, h), (0,0,0,0))
    shape = [
        "#####",
        "#####",
        "#####",
        "#####",
        "#####",
        ".###.",  # 턱 부분 살짝 좁게
    ]
    fill_shape(img, shape, color)
    img.save(f"{OUT}/{prefix}_head.png")
    return w, h


def make_neck(color, prefix):
    """목: 2x2, 매우 가늘게"""
    w, h = 2, 2
    img = Image.new("RGBA", (w, h), (0,0,0,0))
    shape = [
        "##",
        "##",
    ]
    fill_shape(img, shape, color)
    img.save(f"{OUT}/{prefix}_neck.png")
    return w, h


def make_torso(color, prefix):
    """몸통: Nidhogg식 좁고 직선적. 6x12"""
    w, h = 6, 12
    img = Image.new("RGBA", (w, h), (0,0,0,0))
    shape = [
        ".####.",  # 어깨
        "######",
        "######",
        "######",
        ".####.",  # 약간 좁아짐
        ".####.",
        ".####.",
        ".####.",
        "..##..",  # 허리
        "..##..",
        ".####.",  # 골반
        ".####.",
    ]
    fill_shape(img, shape, color)
    img.save(f"{OUT}/{prefix}_torso.png")
    return w, h


def make_arm(color, prefix):
    """팔: 매우 가늘게 2x12 (Nidhogg 스틱)"""
    w, h = 2, 12
    img = Image.new("RGBA", (w, h), (0,0,0,0))
    shape = [
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
    ]
    fill_shape(img, shape, color)
    img.save(f"{OUT}/{prefix}_arm.png")
    return w, h


def make_leg(color, prefix):
    """다리: 가늘게 2x14"""
    w, h = 2, 14
    img = Image.new("RGBA", (w, h), (0,0,0,0))
    shape = [
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
        "##",
    ]
    fill_shape(img, shape, color)
    img.save(f"{OUT}/{prefix}_leg.png")
    return w, h


def make_weapon():
    """무기: 가느다란 막대 2x18"""
    w, h = 2, 18
    img = Image.new("RGBA", (w, h), (0,0,0,0))
    for y in range(h):
        for x in range(w):
            put(img, x, y, WEAPON_COLOR, 6)
    img.save(f"{OUT}/weapon.png")
    return w, h


def make_bullet():
    """총알: 작은 직사각형 5x3"""
    w, h = 5, 3
    img = Image.new("RGBA", (w, h), (0,0,0,0))
    shape = [
        ".###.",
        "#####",
        ".###.",
    ]
    fill_shape(img, shape, BULLET_COLOR, 6)
    img.save(f"{OUT}/bullet.png")
    return w, h


def make_floor_tile():
    """바닥 타일 16x16 — 단색 모래알"""
    w, h = 16, 16
    img = Image.new("RGBA", (w, h), (0,0,0,0))
    random.seed(42)
    for y in range(h):
        for x in range(w):
            # 위쪽 2줄만 약간 밝게 (표면)
            c = FLOOR_LIGHT if y < 2 else FLOOR_COLOR
            put(img, x, y, c, 10)
    img.save(f"{OUT}/floor_tile.png")
    return w, h


def make_floor_surface():
    """바닥 표면 라인 16x2"""
    w, h = 16, 2
    img = Image.new("RGBA", (w, h), (0,0,0,0))
    random.seed(99)
    for y in range(h):
        for x in range(w):
            put(img, x, y, FLOOR_LIGHT, 12)
    img.save(f"{OUT}/floor_surface.png")
    return w, h


def make_structure_tile():
    """구조물 타일 16x16 — 단색 모래알"""
    w, h = 16, 16
    img = Image.new("RGBA", (w, h), (0,0,0,0))
    random.seed(77)
    for y in range(h):
        for x in range(w):
            # 간단한 벽돌 줄눈
            is_mortar = (y % 4 == 3) or ((x + (8 if (y // 4) % 2 == 1 else 0)) % 16 == 0)
            c = STRUCT_COLOR if is_mortar else STRUCT_LIGHT
            put(img, x, y, c, 8)
    img.save(f"{OUT}/structure_tile.png")
    return w, h


def main():
    random.seed(2026)
    print("=== Nidhogg 스타일 에셋 생성 ===\n")

    print(f"P1 색상: {P1_COLOR} (형광 오렌지-옐로우)")
    print(f"P2 색상: {P2_COLOR} (형광 코랄-핑크)")

    print("\n[P1]")
    for name, fn in [("head", make_head), ("neck", make_neck),
                      ("torso", make_torso), ("arm", make_arm), ("leg", make_leg)]:
        w, h = fn(P1_COLOR, "p1")
        print(f"  {name}: {w}x{h}")

    print("[P2]")
    for name, fn in [("head", make_head), ("neck", make_neck),
                      ("torso", make_torso), ("arm", make_arm), ("leg", make_leg)]:
        fn(P2_COLOR, "p2")
    print("  (P1과 동일 크기)")

    print("[공통]")
    w, h = make_weapon()
    print(f"  weapon: {w}x{h}")
    w, h = make_bullet()
    print(f"  bullet: {w}x{h}")
    w, h = make_floor_tile()
    print(f"  floor_tile: {w}x{h}")
    make_floor_surface()
    w, h = make_structure_tile()
    print(f"  structure_tile: {w}x{h}")

    print(f"\n저장: {OUT}")
    print("완료!")


if __name__ == "__main__":
    main()
