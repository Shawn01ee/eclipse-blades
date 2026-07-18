#!/usr/bin/env python3
"""절차 생성 효과음 (AI 도구 생성 — data/asset_ledger.md 참조).
표준 라이브러리만 사용. 16bit/44.1kHz mono WAV를 fx/audio/에 출력."""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
random.seed(20260718)


def env(t, dur, attack=0.004, curve=3.0):
    if t < attack:
        return t / attack
    return max(0.0, 1.0 - ((t - attack) / max(dur - attack, 1e-6))) ** curve


def render(name, dur, fn, gain=0.8):
    n = int(SR * dur)
    frames = bytearray()
    for i in range(n):
        t = i / SR
        v = max(-1.0, min(1.0, fn(t) * gain))
        frames += struct.pack("<h", int(v * 32767))
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print("생성:", name + ".wav")


def noise():
    return random.uniform(-1, 1)


def sine(t, f):
    return math.sin(2 * math.pi * f * t)


# 타격: 노이즈 버스트 + 저음 퉁김
def hit(dur, low, punch):
    def fn(t):
        e = env(t, dur)
        return (noise() * 0.6 + sine(t, low * (1 - t * 2)) * punch) * e
    return fn


render("hit_l", 0.09, hit(0.09, 180, 0.7))
render("hit_m", 0.13, hit(0.13, 140, 0.9))
render("hit_h", 0.20, hit(0.20, 95, 1.1), 0.9)

# 가드: 둔탁한 금속
render("block", 0.11, lambda t: (sine(t, 420) * 0.5 + sine(t, 634) * 0.3 + noise() * 0.25) * env(t, 0.11, curve=4))
# 정밀 방어: 맑은 종
render("parry", 0.30, lambda t: (sine(t, 1180 + 600 * t) * 0.6 + sine(t, 2360) * 0.25) * env(t, 0.30, curve=2))
# 경합: 거친 금속 마찰
render("clash", 0.22, lambda t: (noise() * 0.5 + sine(t, 820 + 40 * sine(t, 31)) * 0.5) * env(t, 0.22, curve=2.5))
# 헛침: 바람
render("whiff", 0.14, lambda t: noise() * 0.35 * math.sin(math.pi * min(t / 0.14, 1.0)) * (0.4 + 0.6 * sine(t, 60) * 0.5))
# 잡기
render("grab", 0.12, lambda t: (noise() * 0.3 + sine(t, 240) * 0.6) * env(t, 0.12))
# 절명: 큰 북 + 잔향
render("ko", 0.55, lambda t: (sine(t, 70 * (1 - t * 0.5)) * 1.0 + noise() * 0.25 * env(t, 0.1)) * env(t, 0.55, curve=1.8), 0.95)
# 오의: 낮은 울림 + 상승음
render("super", 0.5, lambda t: (sine(t, 90) * 0.6 + sine(t, 300 + 900 * t) * 0.35) * env(t, 0.5, curve=1.5))
# 사맥: 짧은 목탁
render("nerve", 0.09, lambda t: (sine(t, 880) * 0.7 + sine(t, 1760) * 0.2) * env(t, 0.09, curve=5))
# 라운드 시작: 징
render("round", 0.8, lambda t: (sine(t, 220) * 0.5 + sine(t, 331) * 0.3 + sine(t, 442) * 0.15) * env(t, 0.8, curve=1.2))
# UI
render("ui_move", 0.05, lambda t: sine(t, 660) * env(t, 0.05, curve=6), 0.4)
render("ui_ok", 0.10, lambda t: (sine(t, 520) + sine(t, 780) * 0.5) * env(t, 0.10, curve=4), 0.45)

print("완료")
