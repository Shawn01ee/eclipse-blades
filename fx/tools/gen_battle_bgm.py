#!/usr/bin/env python3
"""일식검담 전투/위기 BGM 절차 생성기.

외부 샘플 없이 타이코, 저역 북, 샤미센형 현, 금속 타격을 합성한다.
두 트랙은 132 BPM / 16마디 길이와 악구 위치가 같아 재생 위치를 유지한 채
전환할 수 있다. 출력: battle_bgm.wav, battle_danger.wav.
"""
import math
import os
import random
import struct
import wave

SR = 44100
BPM = 132.0
BEAT = 60.0 / BPM
BARS = 16
DURATION = BARS * 4 * BEAT
SAMPLES = int(SR * DURATION)
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "audio")


def render(danger=False):
    rng = random.Random(7301 if danger else 7300)
    buf = [0.0] * SAMPLES

    def add(beat, beats, voice):
        start = int(beat * BEAT * SR)
        count = min(int(beats * BEAT * SR), SAMPLES - start)
        for i in range(max(0, count)):
            buf[start + i] += voice(i / SR)

    def tone(t, freq):
        return math.sin(math.tau * freq * t)

    def taiko(beat, amp=0.72, high=False):
        def voice(t):
            env = math.exp(-t * (8.5 if high else 5.0)) * min(t / 0.0025, 1.0)
            freq = (155 if high else 58) + (115 if high else 72) * math.exp(-t * 15)
            skin = rng.uniform(-1, 1) * math.exp(-t * 42) * 0.20
            return (tone(t, freq) + 0.22 * tone(t, freq * 1.97) + skin) * env * amp
        add(beat, 1.4, voice)

    def metal(beat, amp=0.22):
        def voice(t):
            env = math.exp(-t * 34)
            return (tone(t, 1780) + 0.55 * tone(t, 2635) + rng.uniform(-1, 1) * 0.28) * env * amp
        add(beat, 0.28, voice)

    def shamisen(beat, freq, amp=0.28, length=0.72):
        def voice(t):
            env = math.exp(-t * 7.8) * min(t / 0.002, 1.0)
            buzz = 0.16 * tone(t, freq * 2.01) + 0.08 * tone(t, freq * 3.98)
            pick = rng.uniform(-1, 1) * math.exp(-t * 90) * 0.22
            return (tone(t, freq) + buzz + pick) * env * amp
        add(beat, length, voice)

    def horn(beat, freq, beats=1.7, amp=0.18):
        duration = beats * BEAT
        def voice(t):
            x = min(t / duration, 1.0)
            env = math.sin(math.pi * x) ** 0.65
            vibrato = 1.0 + 0.006 * math.sin(math.tau * 5.4 * t)
            return (tone(t, freq * vibrato) + 0.25 * tone(t, freq * 2 * vibrato)) * env * amp
        add(beat, beats, voice)

    # 저역 심박: 모든 박을 붙잡되 마디 첫 박을 강하게 만든다.
    for beat in range(BARS * 4):
        taiko(beat, 0.82 if beat % 4 == 0 else (0.48 if beat % 2 == 0 else 0.28))
        if danger and beat % 2 == 1:
            taiko(beat + 0.5, 0.24, True)

    # 전투 호흡을 만드는 엇박 북과 금속 박자.
    for bar in range(BARS):
        base = bar * 4
        taiko(base + 1.5, 0.34, True)
        taiko(base + 3.0, 0.46, bar % 2 == 1)
        for off in (0.5, 1.5, 2.5, 3.5):
            metal(base + off, 0.16 if not danger else 0.23)
        if danger or bar in (3, 7, 11, 15):
            taiko(base + 2.75, 0.30, True)
            taiko(base + 3.25, 0.34, True)

    # A 중심 오음음계. 짧은 반복을 2마디마다 뒤집어 검격의 공방처럼 만든다.
    scale = [220.00, 261.63, 293.66, 329.63, 392.00, 440.00]
    patterns = [
        [0, 2, 1, 3, 2, 4, 3, 1],
        [0, 1, 3, 4, 2, 3, 1, 0],
        [2, 4, 3, 5, 4, 2, 3, 1],
        [0, 3, 2, 4, 3, 1, 2, 0],
    ]
    for bar in range(BARS):
        pattern = patterns[(bar // 2) % len(patterns)]
        for step, note in enumerate(pattern):
            beat = bar * 4 + step * 0.5
            accent = 1.18 if step in (0, 4) else 1.0
            shamisen(beat, scale[note], 0.24 * accent if not danger else 0.27 * accent)
            if danger and step % 2 == 1:
                shamisen(beat + 0.25, scale[min(note + 1, 5)] * 2, 0.095, 0.34)

    # 4마디마다 호각 같은 상승 신호, 마지막 구절은 루프 첫 박으로 밀어 넣는다.
    for phrase in range(4):
        base = phrase * 16
        horn(base + 6, scale[3], 1.6, 0.15 if not danger else 0.19)
        horn(base + 14, scale[4], 1.35, 0.17 if not danger else 0.22)
        if danger:
            horn(base + 15, scale[5], 0.8, 0.13)

    # 끝점 클릭을 막는 짧은 페이드. 길이가 같은 두 곡의 전환 박자는 유지된다.
    fade = int(SR * 0.025)
    for i in range(fade):
        buf[i] *= i / fade
        buf[-1 - i] *= i / fade

    peak = max(abs(v) for v in buf) or 1.0
    gain = 0.88 / peak
    return bytearray().join(struct.pack("<h", int(max(-1.0, min(1.0, v * gain)) * 32767)) for v in buf)


def write(name, frames):
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SR)
        wav.writeframes(frames)
    print(f"{name} 생성 ({DURATION:.2f}초, {BPM:.0f} BPM)")


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    write("battle_bgm.wav", render(False))
    write("battle_danger.wav", render(True))
