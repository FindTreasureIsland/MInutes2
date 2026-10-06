"""Synthesize an original watery bubble-pop with short liquid resonances."""
import math
import random
import struct
import wave
from pathlib import Path

rate = 44100
rng = random.Random(27)
samples = [0.0] * int(rate * 0.62)
# A rounded initial plop followed by quieter liquid bubbles, without a sharp click.
for onset, gain, pitch in [(0, 0.70, 520), (0.045, 0.42, 820), (0.115, 0.30, 670),
                           (0.205, 0.21, 1120), (0.30, 0.13, 920), (0.405, 0.07, 1380)]:
    phase = 0.0
    filtered_noise = 0.0
    for i in range(int(rate * 0.16)):
        t = i / rate
        # Brief rising resonances resemble contracting water bubbles.
        frequency = pitch * (1 + 0.20 * (1 - math.exp(-t * 65)))
        phase += 2 * math.pi * frequency / rate
        envelope = (1 - math.exp(-t * 1100)) * math.exp(-t * 65)
        filtered_noise = 0.84 * filtered_noise + 0.16 * rng.uniform(-1, 1)
        liquid = math.sin(phase) + 0.22 * math.sin(phase * 1.97)
        splash = filtered_noise * math.exp(-t * 38) * (1 - math.exp(-t * 600))
        index = int(onset * rate) + i
        samples[index] += gain * (liquid * envelope + splash * 0.35)
# Gentle low-frequency water body under the initial burst.
for i in range(int(rate * 0.11)):
    t = i / rate
    samples[i] += 0.17 * math.sin(2 * math.pi * 155 * t) * (1 - math.exp(-t * 700)) * math.exp(-t * 55)
peak = max(abs(value) for value in samples)
path = Path(__file__).resolve().parent.parent / 'Resources/BubblePop.wav'
with wave.open(str(path), 'wb') as audio:
    audio.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
    audio.writeframes(b''.join(struct.pack('<h', int(value / peak * 0.86 * 32767)) for value in samples))
