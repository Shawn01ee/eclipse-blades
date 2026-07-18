#!/usr/bin/env python3
"""캐릭터 시트에서 액션 포즈를 잘라 배경(화지)을 제거해
인게임 스프라이트(art/sprites/<id>.png, 투명 배경)로 저장.
방법: 가장자리에서 플러드필 — '따뜻한 화지색'만 지운다 (먹 외곽선에서 멈춤)."""
import os
import sys
from collections import deque
from PIL import Image

BASE = os.path.join(os.path.dirname(__file__), "..", "..", "art")


def is_paper(px):
    r, g, b = px[0], px[1], px[2]
    # 화지: 따뜻하고(적>청) 채도 낮은 밝은 톤. 먹 선/의상은 차갑거나 어두움.
    return (r - b) >= 28 and r >= 105 and g >= 85


def cut(src, out, roi_x_ratio=0.44, feather=1):
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    rw = int(w * roi_x_ratio)
    im = im.crop((0, 0, rw, h))
    px = im.load()
    removed = [[False] * rw for _ in range(h)]
    q = deque()
    for x in range(rw):
        for y in (0, h - 1):
            if is_paper(px[x, y]) and not removed[y][x]:
                removed[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, rw - 1):
            if is_paper(px[x, y]) and not removed[y][x]:
                removed[y][x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < rw and 0 <= ny < h and not removed[ny][nx] and is_paper(px[nx, ny]):
                removed[ny][nx] = True
                q.append((nx, ny))
    # 제거 + 경계 페더링
    for y in range(h):
        for x in range(rw):
            if removed[y][x]:
                r, g, b, _ = px[x, y]
                px[x, y] = (r, g, b, 0)
    if feather:
        for y in range(1, h - 1):
            for x in range(1, rw - 1):
                if px[x, y][3] == 255:
                    n_clear = sum(1 for nx, ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)) if px[nx, ny][3] == 0)
                    if n_clear >= 2:
                        r, g, b, _ = px[x, y]
                        px[x, y] = (r, g, b, 140)
    bbox = im.getbbox()
    im = im.crop(bbox)
    os.makedirs(os.path.join(BASE, "sprites"), exist_ok=True)
    im.save(out)
    print("저장:", out, im.size)


cut(os.path.join(BASE, "portraits", "arin.png"), os.path.join(BASE, "sprites", "arin.png"), 0.44)
cut(os.path.join(BASE, "portraits", "daeru.png"), os.path.join(BASE, "sprites", "daeru.png"), 0.44)
cut(os.path.join(BASE, "portraits", "han.png"), os.path.join(BASE, "sprites", "han.png"), 0.46)
cut(os.path.join(BASE, "portraits", "myo.png"), os.path.join(BASE, "sprites", "myo.png"), 0.46)
print("완료")
