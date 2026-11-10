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


# ------------------------------------------------- per-material SFX
# Fire build issue #15: Minecraft gives every material family its own
# hit / break / place sounds. Families: earth, sand, stone, wood,
# plant, glass (see Blocks.MATERIAL_FAMILIES).

FAMILY_PARAMS = {
    #          hit_lp  hit_s   place_f  break_lp  break_s
    "earth": (0.22, 0.10, 150, 0.20, 0.26),
    "sand":  (0.50, 0.09, 300, 0.45, 0.22),
    "stone": (0.12, 0.08, 210, 0.14, 0.30),
    "wood":  (0.30, 0.09, 130, 0.28, 0.24),
    "plant": (0.35, 0.08, 240, 0.33, 0.20),
    "glass": (0.80, 0.07, 700, 0.70, 0.32),
}


def make_family_sfx():
    for family, (hit_lp, hit_s, place_f, break_lp, break_s) in \
            FAMILY_PARAMS.items():
        rng = random.Random("gec-" + family)
        save_wav(f"assets/audio/hit_{family}.wav",
                 noise_burst(rng, hit_s, hit_lp, gain=0.65, decay=6.0))
        brk = noise_burst(rng, break_s, break_lp, gain=0.9, decay=4.5)
        if family == "glass":
            # A bright shimmer over the crunch: descending sine pings.
            for k, f0 in enumerate((1560, 1180, 880)):
                ping = tone_blip(f0, f0 * 0.8, 0.10, gain=0.22, curve=10.0)
                off = int(0.03 * k * SR)
                for i, v in enumerate(ping):
                    if off + i < len(brk):
                        brk[off + i] += v
        save_wav(f"assets/audio/break_{family}.wav", brk)
        place = tone_blip(place_f, place_f * 0.62, 0.09, gain=0.5, curve=7.0)
        nb = noise_burst(rng, 0.05, 0.5, gain=0.22, decay=8.0)
        place = [a + b for a, b in
                 zip(place, nb + [0.0] * (len(place) - len(nb)))]
        save_wav(f"assets/audio/place_{family}.wav", place)
    # Pickup "pop" for the decorative item-drop effect (issue #15).
    save_wav("assets/audio/pop.wav", tone_blip(480, 920, 0.07, gain=0.4,
                                               curve=6.0))


def compose_track(chords, chord_seconds, scale, seed, melody_gain=0.11,
                  density=0.72, beat=3.0):
    """Pad chords + sparse pentatonic melody, loop-faded at the seams."""
    total_seconds = chord_seconds * len(chords) * 2
    track = [0.0] * int(SR * total_seconds)
    for rep in range(2):
        for ci, chord in enumerate(chords):
            start = int((rep * len(chords) + ci) * chord_seconds * SR)
            pad = pad_chord(chord, chord_seconds + 1.5)
            for i, v in enumerate(pad):
                if start + i < len(track):
                    track[start + i] += v
    rng = random.Random(seed)
    t = 2.0
    while t < total_seconds - 4.0:
        if rng.random() < density:
            note = melody_note(rng.choice(scale), 3.5, gain=melody_gain)
            start = int(t * SR)
            for i, v in enumerate(note):
                if start + i < len(track):
                    track[start + i] += v
        t += beat * rng.choice([1, 1, 1, 2])
    fade = int(SR * 1.2)
    for i in range(fade):
        track[i] *= i / fade
        track[-1 - i] *= i / fade
    return track


def make_music_variants():
    # Deep Pines (issue #14): darker and slower — low minor pads, a
    # sparse low melody, longer chords.
    pines = compose_track(
        [[33, 45, 52, 57],   # A1 A2 E3 A3
         [40, 47, 52, 55],   # E2 B2 E3 G3
         [41, 48, 53, 57],   # F2 C3 F3 A3
         [38, 45, 50, 53]],  # D2 A2 D3 F3
        11.0, [57, 60, 64, 67, 69], "gec-pines",
        melody_gain=0.10, density=0.55, beat=3.6)
    save_wav("assets/audio/music_pines.wav", pines)
    # Open Shore (issue #14): brighter major key, lighter melody.
    shore = compose_track(
        [[36, 48, 52, 55],   # C2 C3 E3 G3
         [43, 50, 55, 59],   # G2 D3 G3 B3
         [45, 52, 57, 60],   # A2 E3 A3 C4
         [41, 48, 53, 57]],  # F2 C3 F3 A3
        8.0, [72, 76, 79, 81, 84, 88], "gec-shore",
        melody_gain=0.12, density=0.8, beat=2.6)
    save_wav("assets/audio/music_shore.wav", shore)


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
    make_family_sfx()
    make_music()
    make_music_variants()
