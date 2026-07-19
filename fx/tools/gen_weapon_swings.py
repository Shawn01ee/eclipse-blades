#!/usr/bin/env python3
"""캐릭터 무기별 휘두름 효과음 생성.

외부 샘플 없이 16bit/44.1kHz mono WAV를 만든다. 공격 등급 차이는 게임에서
피치·게인으로 조절하고, 여기서는 무기 재질과 움직임의 고유한 질감만 만든다.
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")


def sine(t, freq):
    return math.sin(math.tau * freq * t)


def bell(t, start, freq, decay):
    x = t - start
    if x < 0:
        return 0.0
    return (sine(x, freq) + 0.38 * sine(x, freq * 1.91)) * math.exp(-x * decay)


def swell(t, dur, center=0.43, width=0.27):
    x = t / dur
    edge = min(x / 0.035, 1.0) * min((1.0 - x) / 0.05, 1.0)
    return math.exp(-((x - center) / width) ** 2) * max(0.0, edge)


def filtered_noise(seed, fast=0.22, slow=0.035):
    rng = random.Random(seed)
    state = {"fast": 0.0, "slow": 0.0, "low": 0.0}

    def sample():
        raw = rng.uniform(-1.0, 1.0)
        state["fast"] += (raw - state["fast"]) * fast
        state["slow"] += (raw - state["slow"]) * slow
        state["low"] += (raw - state["low"]) * 0.018
        return state["fast"] - state["slow"], state["low"]

    return sample


def arin_voice():
    noise = filtered_noise(4101, 0.34, 0.055)
    dur = 0.23

    def voice(t):
        band, _low = noise()
        x = t / dur
        blade = sine(t, 2650.0 - 1250.0 * x) * math.exp(-t * 13.0)
        return band * swell(t, dur, 0.40, 0.24) * 1.55 + blade * 0.16

    return dur, voice


def daeru_voice():
    noise = filtered_noise(4202, 0.11, 0.018)
    dur = 0.36

    def voice(t):
        band, low = noise()
        x = t / dur
        weight = sine(t, 92.0 - 34.0 * x) * math.exp(-t * 6.5)
        shaft = sine(t, 360.0 - 120.0 * x) * math.exp(-t * 10.0)
        return (low * 3.3 + band * 0.52) * swell(t, dur, 0.49, 0.34) + weight * 0.40 + shaft * 0.10

    return dur, voice


def han_voice():
    noise_a = filtered_noise(4303, 0.30, 0.05)
    noise_b = filtered_noise(4304, 0.26, 0.045)
    dur = 0.29

    def pulse(t, at, width):
        return math.exp(-((t - at) / width) ** 2)

    def voice(t):
        band_a, _ = noise_a()
        band_b, _ = noise_b()
        first = band_a * pulse(t, 0.082, 0.055)
        second = band_b * pulse(t, 0.158, 0.064)
        glint = bell(t, 0.038, 1870.0, 24.0) + bell(t, 0.112, 2240.0, 27.0)
        return (first + second) * 1.25 + glint * 0.075

    return dur, voice


def myo_voice():
    noise = filtered_noise(4405, 0.24, 0.042)
    dur = 0.39

    def voice(t):
        band, _low = noise()
        chain = 0.0
        for k, freq in enumerate((1420.0, 1860.0, 1610.0, 2310.0)):
            chain += bell(t, 0.032 + k * 0.052, freq, 31.0) * (0.20 - k * 0.025)
        hook = sine(t, 760.0 - 280.0 * t / dur) * math.exp(-t * 12.0)
        return band * swell(t, dur, 0.55, 0.38) * 1.05 + chain + hook * 0.10

    return dur, voice


def mujin_voice():
    noise = filtered_noise(4506, 0.09, 0.014)
    dur = 0.48

    def voice(t):
        band, low = noise()
        x = t / dur
        wave = sine(t, 118.0 - 36.0 * x) * math.sin(math.pi * x) ** 0.7
        undertow = sine(t, 58.0) * math.exp(-t * 4.8)
        return (low * 3.7 + band * 0.45) * swell(t, dur, 0.51, 0.42) + wave * 0.32 + undertow * 0.16

    return dur, voice


def jiko_voice():
    """짧게 세 번 갈라지는 단도성 장검 풍압."""
    noise_a = filtered_noise(4607, 0.30, 0.050)
    noise_b = filtered_noise(4608, 0.25, 0.040)
    dur = 0.34

    def pulse(t, at, width):
        return math.exp(-((t - at) / width) ** 2)

    def voice(t):
        band_a, _ = noise_a()
        band_b, low = noise_b()
        cuts = (
            band_a * pulse(t, 0.062, 0.043)
            + band_b * pulse(t, 0.132, 0.052)
            + (band_a - band_b) * pulse(t, 0.218, 0.066)
        )
        bite = bell(t, 0.046, 1540.0, 27.0) + bell(t, 0.184, 2020.0, 30.0)
        return cuts * 1.18 + bite * 0.075 + low * swell(t, dur, 0.62, 0.30) * 0.72

    return dur, voice


def write(name, duration, voice):
    samples = [voice(i / SR) for i in range(int(duration * SR))]
    peak = max((abs(v) for v in samples), default=1.0) or 1.0
    scale = 0.88 / peak
    frames = bytearray().join(
        struct.pack("<h", int(max(-1.0, min(1.0, v * scale)) * 32767)) for v in samples
    )
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SR)
        wav.writeframes(frames)
    print(f"{name}.wav 생성 ({duration:.2f}초)")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for sound_name, factory in (
        ("swing_arin", arin_voice),
        ("swing_daeru", daeru_voice),
        ("swing_han", han_voice),
        ("swing_myo", myo_voice),
        ("swing_mujin", mujin_voice),
        ("swing_jiko", jiko_voice),
    ):
        dur, fn = factory()
        write(sound_name, dur, fn)
