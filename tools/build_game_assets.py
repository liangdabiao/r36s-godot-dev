from __future__ import annotations

import math
import random
import struct
import wave
from array import array
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPRITES = ROOT / "assets" / "sprites"
AUDIO = ROOT / "assets" / "audio"
FRAME_SIZE = 48
CELL_SIZE = 460

SHEETS = [
    ("Character0_Idle.png", "player_idle.png", 8),
    ("Character0_Run_Sword.png", "player_run.png", 4),
    ("Character0_SwordAttack_Sword.png", "player_attack.png", 6),
    ("Character0_Damage.png", "player_hurt.png", 2),
    ("Character0_Die.png", "player_die.png", 6),
]


def build_sprite_sheets() -> None:
    SPRITES.mkdir(parents=True, exist_ok=True)
    for source_name, output_name, columns in SHEETS:
        source = ROOT / "character" / "sprites" / source_name
        with Image.open(source) as image:
            image = image.convert("RGBA")
            output = Image.new("RGBA", (columns * FRAME_SIZE * 3, FRAME_SIZE))
            for row in range(3):
                for column in range(columns):
                    left = column * CELL_SIZE
                    top = row * CELL_SIZE
                    frame = image.crop((left, top, left + CELL_SIZE, top + CELL_SIZE))
                    frame = frame.resize((FRAME_SIZE, FRAME_SIZE), Image.LANCZOS)
                    output.alpha_composite(frame, ((row * columns + column) * FRAME_SIZE, 0))
            output.save(SPRITES / output_name, optimize=True)
            print(f"sprite: {output_name} ({output.width}x{output.height})")


def envelope(length: int, attack: float = 0.01, release: float = 0.15) -> array:
    values = array("h")
    attack_samples = max(1, int(length * attack))
    release_samples = max(1, int(length * release))
    for index in range(length):
        gain = 1.0
        if index < attack_samples:
            gain = index / attack_samples
        elif index >= length - release_samples:
            gain = (length - index) / release_samples
        values.append(int(max(0.0, min(1.0, gain)) * 32767))
    return values


def write_sound(name: str, duration: float, sample_at) -> None:
    sample_rate = 22050
    length = int(duration * sample_rate)
    shape = envelope(length)
    samples = array("h")
    for index in range(length):
        time = index / sample_rate
        value = max(-1.0, min(1.0, sample_at(time, duration))) * 0.55
        samples.append(int(value * shape[index]))
    with wave.open(str(AUDIO / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(samples.tobytes())
    print(f"audio: {name} ({duration:.2f}s)")


def build_audio() -> None:
    AUDIO.mkdir(parents=True, exist_ok=True)
    rng = random.Random(36)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(22050)]

    write_sound("swing.wav", 0.14, lambda t, d: noise[int(t * 22050) % len(noise)] * (1.0 - t / d))
    write_sound("hit.wav", 0.10, lambda t, d: math.sin(2 * math.pi * (120 - 300 * t) * t) + noise[int(t * 22050) % len(noise)] * 0.45)
    write_sound("hurt.wav", 0.22, lambda t, d: math.sin(2 * math.pi * (190 - 520 * t) * t) * 0.7)
    write_sound("dash.wav", 0.16, lambda t, d: noise[int(t * 22050) % len(noise)] * (1.0 - t / d) * 0.65)
    write_sound("pickup.wav", 0.18, lambda t, d: math.sin(2 * math.pi * (740 if t < 0.08 else 980) * t))
    write_sound("special.wav", 0.42, lambda t, d: math.sin(2 * math.pi * (180 + 900 * t) * t) * (1.0 - t / d))
    write_sound("wave.wav", 0.55, lambda t, d: sum(math.sin(2 * math.pi * freq * t) for freq in (392, 523, 659)) / 3)
    write_sound(
        "win.wav",
        0.95,
        lambda t, d: sum(math.sin(2 * math.pi * freq * t) for freq in (523, 659, 784, 1046)) / 4,
    )
    write_sound(
        "lose.wav",
        0.70,
        lambda t, d: sum(math.sin(2 * math.pi * freq * t) for freq in (392, 330, 262, 196)) / 4,
    )


if __name__ == "__main__":
    build_sprite_sheets()
    build_audio()
