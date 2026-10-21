"""Makes the app's sounds: python3 tools/sounds.py (writes Slam/Sounds/*.wav)."""
import math
import struct
import wave
from pathlib import Path

RATE = 44100


def tone(freq, start, decay, partials, length, shimmer=0.0):
    """A bell-like note: a sine plus overtones, fast attack, exponential decay; shimmer makes overtones die first."""
    out = [0.0] * int(length * RATE)
    for i in range(int(start * RATE), len(out)):
        t = i / RATE - start
        env = min(1.0, t / 0.004) * math.exp(-t / decay)
        out[i] = env * sum(a * math.exp(-t * m * shimmer) * math.sin(2 * math.pi * freq * m * t) for m, a in partials)
    return out


def write(name, notes, length, peak):
    mix = [0.0] * int(length * RATE)
    for n in notes:
        for i, v in enumerate(tone(*n[:4], length, *n[4:])):
            mix[i] += v
    top = max(abs(v) for v in mix) or 1
    fade = int(0.03 * RATE)
    frames = b"".join(
        struct.pack("<h", int(v / top * peak * min(1, (len(mix) - i) / fade) * 32767)) for i, v in enumerate(mix)
    )
    path = Path(__file__).resolve().parent.parent / "Slam" / "Sounds" / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


soft = [(1, 1.0), (2, 0.18), (3.01, 0.05)]
bell = [(1, 1.0), (2, 0.3), (2.76, 0.18), (5.4, 0.06)]
# Set ticked: one short, quiet ding.
write("set", [(1318.5, 0.0, 0.09, soft)], 0.4, 0.28)
# New record: a quick rising arpeggio.
write("record", [(1046.5, 0.0, 0.12, soft), (1318.5, 0.07, 0.12, soft), (1568.0, 0.14, 0.2, soft)], 0.8, 0.32)
# Rest over: one lower bell that rings on, unlike the short high dings above.
write("rest", [(880.0, 0.0, 0.55, bell, 0.8)], 1.6, 0.7)
