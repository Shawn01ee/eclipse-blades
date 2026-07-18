#!/usr/bin/env python3
"""일본풍 BGM 절차 생성 (AI 도구 생성 — data/asset_ledger.md 참조).
히라조시 음계(A B C E F) 고토 + 샤쿠하치 + 타이코 + 효시기. 60BPM 8마디 루프.
표준 라이브러리만 사용, fx/audio/bgm.wav 출력."""
import math
import os
import random
import struct
import wave

SR = 44100
BPM = 60.0
BEAT = 60.0 / BPM
BARS = 8
DUR = BARS * 4 * BEAT          # 32박 = 32초
N = int(SR * DUR)
random.seed(11)

buf = [0.0] * N


def add(start_s, dur_s, fn):
    i0 = int(start_s * SR)
    n = int(dur_s * SR)
    for i in range(n):
        j = i0 + i
        if 0 <= j < N:
            buf[j] += fn(i / SR)


def sine(t, f):
    return math.sin(2 * math.pi * f * t)


# --- 고토 뜯기: 배음 감쇠 + 짧은 어택 노이즈 ---
def koto(beat, freq, amp=0.5, decay=2.6):
    def fn(t):
        e = math.exp(-t * decay) * min(t / 0.004, 1.0)
        v = (sine(t, freq) * 1.0 + sine(t, freq * 2) * 0.4 * math.exp(-t * 5)
             + sine(t, freq * 3) * 0.18 * math.exp(-t * 8)
             + sine(t, freq * 4.02) * 0.08 * math.exp(-t * 11))
        pluck = random.uniform(-1, 1) * 0.25 * math.exp(-t * 90)
        return (v + pluck) * e * amp
    add(beat * BEAT, 3.0, fn)


# --- 장식음(스리테) 딸린 고토 ---
def koto_grace(beat, freq, grace_freq, amp=0.5):
    koto(beat - 0.07 / BEAT, grace_freq, amp * 0.35, decay=9)
    koto(beat, freq, amp)


# --- 샤쿠하치: 느린 어택 + 커지는 비브라토 + 숨소리 ---
def shaku(beat, freq, beats, amp=0.30):
    dur = beats * BEAT
    def fn(t):
        x = t / dur
        env = math.sin(math.pi * min(x, 1.0)) ** 0.7
        vib = 1.0 + 0.012 * math.sin(2 * math.pi * 5.2 * t) * min(t / 1.2, 1.0)
        breath = random.uniform(-1, 1) * 0.05 * env
        return (sine(t, freq * vib) * 0.9 + sine(t, freq * 2 * vib) * 0.12 + breath) * env * amp
    add(beat * BEAT, dur, fn)


# --- 타이코 ---
def taiko(beat, amp=0.8):
    def fn(t):
        f = 105 * math.exp(-t * 9) + 48
        e = math.exp(-t * 5.5) * min(t / 0.003, 1.0)
        return (sine(t, f) * 1.0 + random.uniform(-1, 1) * 0.22 * math.exp(-t * 40)) * e * amp
    add(beat * BEAT, 1.2, fn)


# --- 효시기(딱따기) ---
def clack(beat, amp=0.35):
    def fn(t):
        e = math.exp(-t * 220)
        return (sine(t, 2450) * 0.7 + sine(t, 3620) * 0.4 + random.uniform(-1, 1) * 0.3) * e * amp
    add(beat * BEAT, 0.06, fn)


# --- 저역 드론 (긴장감) ---
def drone():
    def fn(t):
        lfo = 0.6 + 0.4 * math.sin(2 * math.pi * t / 16.0)
        return (sine(t, 55) * 0.6 + sine(t, 110) * 0.25) * 0.10 * lfo
    add(0, DUR, fn)


# ================= 작곡 (히라조시: A B C E F) =================
A3, B3, C4, E4, F4 = 220.0, 246.94, 261.63, 329.63, 349.23
A4, B4, C5, E5, F5 = 440.0, 493.88, 523.25, 659.26, 698.46

drone()

# 타이코: 마디 머리 + 4/8마디 겹북
for bar in range(BARS):
    taiko(bar * 4, 0.75 if bar % 2 == 0 else 0.55)
    if bar in (3, 7):
        taiko(bar * 4 + 2.5, 0.4)
        taiko(bar * 4 + 3.0, 0.55)

# 효시기: 구절 끝
clack(15.5)
clack(31.5)
clack(31.75, 0.25)

# 고토 선율
koto_grace(0.0, A4, B4)
koto(1.5, C5, 0.45)
koto(3.0, B4, 0.4)
koto(5.0, A4, 0.42)
koto(6.5, E4, 0.4)
koto_grace(8.5, F4, E4, 0.42)
koto(9.0, E4, 0.3, decay=5)
koto(11.0, C4, 0.4)
koto(13.0, B3, 0.42)
koto_grace(16.0, E5, F5, 0.5)
koto(17.5, C5, 0.44)
koto(19.0, B4, 0.4)
koto(21.0, A4, 0.42)
koto(22.5, F4, 0.4)
koto(24.5, E4, 0.34)
koto(25.0, F4, 0.3, decay=5)
koto(26.0, E4, 0.34)
koto(27.0, C4, 0.4)
koto(29.0, A3, 0.5, decay=1.6)

# 샤쿠하치 롱톤
shaku(4.0, E5, 2.5, 0.22)
shaku(12.5, B4, 2.5, 0.20)
shaku(20.0, A4, 3.0, 0.24)

# ================= 출력 =================
peak = max(abs(v) for v in buf)
gain = 0.85 / peak if peak > 0 else 1.0
out = os.path.join(os.path.dirname(__file__), "..", "audio", "bgm.wav")
frames = bytearray()
for v in buf:
    frames += struct.pack("<h", int(max(-1.0, min(1.0, v * gain)) * 32767))
with wave.open(out, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(bytes(frames))
print("bgm.wav 생성 (%.1f초, 피크 정규화 %.2f)" % (DUR, gain))
