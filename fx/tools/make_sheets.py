#!/usr/bin/env python3
"""단일 캐릭터 스프라이트(art/sprites/<id>.png)에서 프레임 애니메이션 시트를 굽는다.
방법: 발(하단 중앙)을 고정한 채 스쿼시/스트레치/시어(무기 스윙)/기울기/바운스를
아핀 변형으로 프레임마다 적용 → art/sheets/<id>_<anim>.png (가로 스트립) + <id>.json.

애니메이션당 프레임은 순수 절차 변형이므로 추가 원화 없이 손맛을 낸다.
공격 행은 발동→활성→후딜 3구간을 코일(움츠림)→베기(뻗음+전방 시어)→회복으로 표현."""
import json
import math
import os
from PIL import Image

BASE = os.path.join(os.path.dirname(__file__), "..", "..", "art")
SPRITES = os.path.join(BASE, "sprites")
OUT = os.path.join(BASE, "sheets")

TARGET_H = 360          # 스프라이트 목표 높이(px)
PAD_X = 120             # 시어 오버플로 여유(좌우)
PAD_TOP = 40


def mat_mul(A, B):
    return [
        A[0] * B[0] + A[1] * B[2], A[0] * B[1] + A[1] * B[3],
        A[2] * B[0] + A[3] * B[2], A[2] * B[1] + A[3] * B[3],
    ]


def mat_inv(A):
    det = A[0] * A[3] - A[1] * A[2]
    return [A[3] / det, -A[1] / det, -A[2] / det, A[0] / det]


def deform(img, anchor, scale_x, scale_y, shear_x, shear_y, rot_deg, tx, ty):
    """anchor(하단 중앙) 고정 아핀 변형. Image.transform은 역매핑을 요구."""
    r = math.radians(rot_deg)
    R = [math.cos(r), -math.sin(r), math.sin(r), math.cos(r)]
    SH = [1.0, shear_x, shear_y, 1.0]
    SC = [scale_x, 0.0, 0.0, scale_y]
    A = mat_mul(R, mat_mul(SH, SC))          # forward linear
    Ai = mat_inv(A)
    ax, ay = anchor
    # input = Ai*(out - anchor - t) + anchor
    c = ax - (Ai[0] * (ax + tx) + Ai[1] * (ay + ty))
    f = ay - (Ai[2] * (ax + tx) + Ai[3] * (ay + ty))
    return img.transform(img.size, Image.AFFINE,
                         (Ai[0], Ai[1], c, Ai[2], Ai[3], f), resample=Image.BICUBIC)


def ease(t):
    return t * t * (3 - 2 * t)


def frame_params(anim, i, n):
    """(sx, sy, shear_x, rot, tx, ty) 반환. 발 고정 기준."""
    p = i / max(n - 1, 1)
    if anim == "idle":
        breathe = math.sin(p * math.tau)
        return (1.0 - 0.012 * breathe, 1.0 + 0.02 * breathe, 0.0, 0.0, 0.0, -2.0 * (breathe * 0.5 + 0.5))
    if anim == "walk":
        ph = p * math.tau
        bob = abs(math.sin(ph))
        return (1.0 + 0.02 * math.cos(ph), 1.0 - 0.03 * bob, 0.04 * math.sin(ph), 0.0,
                6.0 * math.sin(ph), -6.0 * bob)
    if anim == "attack":
        # 0-0.18 코일 / 0.18-0.5 베기 / 0.5-1 회복
        if p < 0.20:
            k = ease(p / 0.20)
            return (1.0 + 0.06 * k, 1.0 - 0.05 * k, -0.16 * k, 4.0 * k, -10.0 * k, 3.0 * k)
        elif p < 0.52:
            k = ease((p - 0.20) / 0.32)
            return (1.0 + 0.06 - 0.14 * k, 1.0 - 0.05 + 0.14 * k, -0.16 + 0.52 * k, 4.0 - 16.0 * k,
                    -10.0 + 34.0 * k, 3.0 - 8.0 * k)
        else:
            k = ease((p - 0.52) / 0.48)
            return (1.06 - 0.14 + 0.08 * k, 1.09 - 0.08 * (1 - (1 - k)), 0.36 - 0.36 * k,
                    -12.0 + 12.0 * k, 24.0 - 24.0 * k, -5.0 + 5.0 * k)
    if anim == "hit":
        k = ease(p)
        vib = math.sin(p * 22) * (1 - k) * 4
        return (1.0 - 0.04 * (1 - k), 1.0 - 0.02 * (1 - k), 0.20 * (1 - k), 6.0 * (1 - k), 12.0 * (1 - k) + vib, 2.0 * (1 - k))
    if anim == "guard":
        k = ease(p)
        return (1.0 + 0.03 * k, 1.0 - 0.03 * k, 0.10 * k, 3.0 * k, 6.0 * k, 1.0 * k)
    if anim == "ko":
        k = ease(p)
        return (1.0 + 0.1 * k, 1.0 - 0.15 * k, 0.0, -78.0 * k, -30.0 * k, 10.0 * k)
    return (1.0, 1.0, 0.0, 0.0, 0.0, 0.0)


ANIMS = {
    "idle": (6, 7, True),
    "walk": (6, 12, True),
    "attack": (8, 30, False),
    "hit": (4, 24, False),
    "guard": (2, 16, True),
    "ko": (5, 14, False),
}


def build(char_id):
    src = os.path.join(SPRITES, char_id + ".png")
    if not os.path.exists(src):
        print("건너뜀(원본 없음):", char_id)
        return
    im = Image.open(src).convert("RGBA")
    bbox = im.getbbox()
    im = im.crop(bbox)
    scale = TARGET_H / im.height
    im = im.resize((max(1, round(im.width * scale)), TARGET_H), Image.LANCZOS)
    cw = im.width + PAD_X * 2
    ch = im.height + PAD_TOP + 20
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    canvas.alpha_composite(im, (PAD_X, PAD_TOP))
    anchor = (cw / 2.0, PAD_TOP + im.height)      # 발 = 하단 중앙

    os.makedirs(OUT, exist_ok=True)
    meta = {"cell_w": cw, "cell_h": ch, "foot_y": PAD_TOP + im.height, "anims": {}}
    for anim, (nf, fps, loop) in ANIMS.items():
        strip = Image.new("RGBA", (cw * nf, ch), (0, 0, 0, 0))
        for i in range(nf):
            sx, sy, shx, rot, tx, ty = frame_params(anim, i, nf)
            fr = deform(canvas, anchor, sx, sy, shx, 0.0, rot, tx, ty)
            strip.paste(fr, (cw * i, 0), fr)
        strip.save(os.path.join(OUT, "%s_%s.png" % (char_id, anim)))
        meta["anims"][anim] = {"frames": nf, "fps": fps, "loop": loop}
    with open(os.path.join(OUT, char_id + ".json"), "w") as fp:
        json.dump(meta, fp, indent=1)
    print("시트 생성:", char_id, "cell", cw, "x", ch)


for cid in ["arin", "daeru", "han", "myo"]:
    build(cid)
print("완료")
