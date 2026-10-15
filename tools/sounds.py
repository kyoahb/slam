"""Makes the app's sounds: python3 tools/sounds.py (writes Slam/Sounds/*.wav)."""
import math
import struct
import wave
from pathlib import Path

RATE = 44100


def tone(freq, start, decay, partials, length):
    """A bell-like note: a sine plus overtones, fast attack, exponential decay."""
    out = [0.0] * int(length * RATE)
    for i in range(int(start * RATE), len(out)):
        t = i / RATE - start
        env = min(1.0, t / 0.004) * math.exp(-t / decay)
        out[i] = env * sum(a * math.sin(2 * math.pi * freq * m * t) for m, a in partials)
    return out


def beep(freq, start, dur, partials, length):
    """An electronic beep: steady while it lasts, with 5 ms ramps so it does not click."""
    out = [0.0] * int(length * RATE)
    n, ramp = int(dur * RATE), int(0.005 * RATE)
    for k in range(n):
        i = int(start * RATE) + k
        if i >= len(out):
            break
        t = k / RATE
        out[i] = min(1.0, k / ramp, (n - k) / ramp) * sum(a * math.sin(2 * math.pi * freq * m * t) for m, a in partials)
    return out


def write(name, notes, length, peak, voice=tone):
    mix = [0.0] * int(length * RATE)
    for n in notes:
        for i, v in enumerate(voice(*n, length)):
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
square = [(1, 1.0), (3, 0.33), (5, 0.2), (7, 0.14)]
# Set ticked: one short, quiet ding.
write("set", [(1318.5, 0.0, 0.09, soft)], 0.4, 0.28)
# New record: a quick rising arpeggio.
write("record", [(1046.5, 0.0, 0.12, soft), (1318.5, 0.07, 0.12, soft), (1568.0, 0.14, 0.2, soft)], 0.8, 0.32)
# Rest over: beep-beep-beep twice, loud and nothing like the bells above.
write("rest", [(1174.7, g + b * 0.17, 0.1, square) for g in (0.0, 0.8) for b in range(3)], 1.4, 0.95, voice=beep)
