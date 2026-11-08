#!/usr/bin/env python3
"""Generate GoodEnoughCraft's audio procedurally — no external samples.

Outputs 44.1 kHz 16-bit mono WAVs into assets/audio/:
  dig.wav, place.wav, break.wav, step.wav, splash.wav, ui_click.wav
  music_ambient.wav — a calm ~72 s ambient loop (original composition:
  slow chord pads + a sparse pentatonic melody, in the spirit of ambient
  sandbox music without copying any existing work).

Regenerate with: python3 tools/make_audio.py
"""
import math
import random
import struct
import wave

SR = 44100


def save_wav(path, samples):
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    print("wrote", path, f"{len(samples) / SR:.2f}s")


def noise_burst(rng, seconds, lowpass_alpha, gain=0.8, decay=6.0):
    n = int(SR * seconds)
    out = []
    lp = 0.0
    for i in range(n):
        white = rng.uniform(-1.0, 1.0)
        lp += lowpass_alpha * (white - lp)
        env = math.exp(-decay * i / n)
        out.append(lp * env * gain)
    return out


def tone_blip(freq_a, freq_b, seconds, gain=0.5, curve=8.0):
    n = int(SR * seconds)
    out = []
    for i in range(n):
        t = i / SR
        frac = i / n
        freq = freq_a + (freq_b - freq_a) * frac
        env = math.exp(-curve * frac)
        out.append(math.sin(2 * math.pi * freq * t) * env * gain)
    return out


def make_sfx():
    rng = random.Random("gec-audio")
    save_wav("assets/audio/dig.wav",
             noise_burst(rng, 0.13, 0.25, gain=0.7, decay=5.0))
    save_wav("assets/audio/break.wav",
             noise_burst(rng, 0.28, 0.35, gain=0.9, decay=4.0))
    place = tone_blip(190, 120, 0.09, gain=0.55, curve=7.0)
    nb = noise_burst(rng, 0.05, 0.5, gain=0.25, decay=8.0)
    place = [a + b for a, b in zip(place, nb + [0.0] * (len(place) - len(nb)))]
    save_wav("assets/audio/place.wav", place)
    save_wav("assets/audio/step.wav",
             noise_burst(rng, 0.055, 0.18, gain=0.32, decay=7.0))
    # Splash: noise with a falling band emphasis (falling sine sweep mix).
    n = int(SR * 0.45)
    splash = []
    lp = 0.0
    for i in range(n):
        frac = i / n
        white = rng.uniform(-1.0, 1.0)
        lp += (0.10 + 0.25 * frac) * (white - lp)
        sweep = math.sin(2 * math.pi * (700 - 400 * frac) * (i / SR)) * 0.12
        splash.append((lp * 0.8 + sweep) * math.sin(math.pi * frac) ** 1.5)
    save_wav("assets/audio/splash.wav", splash)
    save_wav("assets/audio/ui_click.wav",
             tone_blip(880, 660, 0.05, gain=0.30, curve=9.0))


# ------------------------------------------------------------------ music

def freq(note):
    """MIDI note number -> Hz."""
    return 440.0 * 2 ** ((note - 69) / 12.0)


def pad_chord(notes, seconds, gain=0.16):
    """Soft pad: fundamental + octave + fifth partials, slow envelope."""
    n = int(SR * seconds)
    out = [0.0] * n
    for note in notes:
        f = freq(note)
        for i in range(n):
            t = i / SR
            env = math.sin(math.pi * i / n) ** 1.5
            v = (math.sin(2 * math.pi * f * t)
                 + 0.4 * math.sin(2 * math.pi * f * 2 * t)
                 + 0.18 * math.sin(2 * math.pi * f * 3 * t))
            out[i] += v * env * gain / len(notes)
    return out


def melody_note(note, seconds, gain=0.11):
    """A single gentle piano-ish tone (decaying harmonics)."""
    n = int(SR * seconds)
    f = freq(note)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-1.4 * t)
        v = (math.sin(2 * math.pi * f * t)
             + 0.5 * math.exp(-3.0 * t) * math.sin(2 * math.pi * f * 2 * t)
             + 0.2 * math.exp(-5.0 * t) * math.sin(2 * math.pi * f * 3 * t))
        out.append(v * env * gain)
    return out


def make_music():
    # Chord loop: Am(add9) - Fmaj7 - Cmaj7 - G(add9), 9 s each, twice = 72 s.
    chords = [
        [45, 52, 57, 59],   # A2 E3 A3 B3
        [41, 48, 53, 57],   # F2 C3 F3 A3
        [36, 48, 52, 55],   # C2 C3 E3 G3
        [43, 50, 55, 57],   # G2 D3 G3 A3
    ]
    chord_seconds = 9.0
    total_seconds = chord_seconds * len(chords) * 2
    track = [0.0] * int(SR * total_seconds)
    for rep in range(2):
        for ci, chord in enumerate(chords):
            start = int((rep * len(chords) + ci) * chord_seconds * SR)
            pad = pad_chord(chord, chord_seconds + 1.5)
            for i, v in enumerate(pad):
                if start + i < len(track):
                    track[start + i] += v
    # Sparse pentatonic melody (A minor pentatonic), one note every ~3 s
    # at pseudo-random but deterministic spots, skipping some beats.
    rng = random.Random("gec-melody")
    scale = [69, 72, 76, 79, 81, 84]  # A4 C5 E5 G5 A5 C6
    beat = 3.0
    t = 2.0
    while t < total_seconds - 4.0:
        if rng.random() < 0.72:
            note = melody_note(rng.choice(scale), 3.5)
            start = int(t * SR)
            for i, v in enumerate(note):
                if start + i < len(track):
                    track[start + i] += v
        t += beat * rng.choice([1, 1, 1, 2])
    # Gentle overall fade at the very ends for a clean loop seam.
    fade = int(SR * 1.2)
    for i in range(fade):
        track[i] *= i / fade
        track[-1 - i] *= i / fade
    save_wav("assets/audio/music_ambient.wav", track)


if __name__ == "__main__":
    make_sfx()
    make_music()
