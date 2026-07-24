#!/usr/bin/env python3
"""번들 UI 폰트 서브셋 생성.
원본 Noto Sans KR(가변) → wght=400 인스턴스 → 필요한 유니코드 범위로 서브셋.
전체 한글 음절을 포함해 이후 한글 UI를 추가해도 tofu가 나지 않게 한다.
사용: python3 fx/tools/build_font.py /tmp/NotoSansKR-full.ttf"""
import sys
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/NotoSansKR-full.ttf"
OUT = "fonts/NotoSansKR-Game.ttf"

RANGES = [
    (0x20, 0x7E),        # ASCII
    (0xA0, 0xFF),        # 라틴 보충 (× ÷ 및 악센트)
    (0x2013, 0x2014),    # –—
    (0x2018, 0x201F),    # ' ' " "
    (0x2022, 0x2022), (0x2026, 0x2026),   # • …
    (0x2190, 0x21FF),    # 화살표 전체 (← ↑ → ↓ ↘ ↙ 등)
    (0x25A0, 0x25FF),    # ◀ ▶ ▲ ▼ 등 기하 도형
    (0x2713, 0x2713), (0x2717, 0x2717),   # ✓ ✗
    (0x3000, 0x303F),    # CJK 문장부호
    (0x3130, 0x318F),    # 한글 자모 호환
    (0x1100, 0x11FF),    # 한글 자모
    (0xAC00, 0xD7A3),    # 한글 음절 전체
    (0xFF00, 0xFFEF),    # 전각 영숫자·부호
]

font = TTFont(SRC)
if "fvar" in font:
    instantiateVariableFont(font, {"wght": 400}, inplace=True)

unicodes = []
for a, b in RANGES:
    unicodes.extend(range(a, b + 1))

opts = subset.Options()
opts.name_IDs = ["*"]
opts.name_legacy = True
opts.recalc_bounds = True
opts.drop_tables = []
opts.notdef_outline = True
opts.glyph_names = False
sub = subset.Subsetter(options=opts)
sub.populate(unicodes=unicodes)
sub.subset(font)
font.save(OUT)

f2 = TTFont(OUT)
print("저장:", OUT)
print("글리프 수:", len(f2.getGlyphOrder()), "| cmap 엔트리:", len(f2.getBestCmap()))
import os
print("파일 크기: %.2f MB" % (os.path.getsize(OUT) / 1048576.0))
