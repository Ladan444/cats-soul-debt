"""Звуки боя и окружения из скачанных наборов OpenGameArt → assets/audio/sfx/oga/ (моно 16 бит, пик −1 дБ).

Имена в игре — ключи PICK; в scripts/core/audio.gd (SFX) они пишутся как «oga/<имя>.wav». Все выбранные — CC0
(авторы — в assets/audio/SOURCES.md). Исходники — Арт/Ассеты/Audio/OpenGameArt/heroic-fantasy-sounds/ (вне бэкапа).

  python Tools/sfx_pick.py
"""

import wave
import zipfile
from pathlib import Path

import miniaudio
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Арт" / "Ассеты" / "Audio" / "OpenGameArt" / "heroic-fantasy-sounds"
OUT = ROOT / "Game" / "CatsSoulDebt" / "assets" / "audio" / "sfx" / "oga"
RATE = 44100
PEAK = 10 ** (-1 / 20)

SWISHES = "swishes-sound-pack/swishes.zip"
RPG = "rpg-sound-pack/rpg_sound_pack.zip"
TINY = "fantasy-sound-effects-tinysized-sfx/tinysized.zip"

# имя в игре → (архив, имя файла внутри — по окончанию пути)
PICK = {
    **{f"swish_{n}": (SWISHES, f"swish-{n}.wav") for n in (1, 3, 4, 5, 6, 7, 8, 9)},
    **{f"swing_{n}": (RPG, f"{n}.wav") for n in ("swing", "swing2", "swing3")},
    **{f"clash_{n}": (TINY, f"sword-clash-0{n}.wav") for n in (1, 3, 4, 5)},
    **{f"giant_{n}": (RPG, f"giant{n}.wav") for n in (1, 2, 3, 4, 5)},
    **{f"monster_{n}": (RPG, f"mnstr{n}.wav") for n in (1, 2, 3, 5, 7, 9, 10, 12, 13, 14)},
    **{f"drip_{n}": (TINY, f"water-drop-0{n}.wav") for n in (1, 2, 3)},
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    archives: dict[str, zipfile.ZipFile] = {}
    for name, (archive, inner) in PICK.items():
        z = archives.setdefault(archive, zipfile.ZipFile(SRC / archive))
        member = next(n for n in z.namelist() if n.endswith("/" + inner) or n == inner)
        snd = miniaudio.decode(z.read(member), output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1,
                               sample_rate=RATE)
        x = np.frombuffer(snd.samples, dtype=np.float32).copy()
        x *= PEAK / max(float(np.abs(x).max()), 1e-6)
        with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes((x * 32767).astype("<i2").tobytes())
    print("готово:", len(PICK), "звуков →", OUT)


if __name__ == "__main__":
    main()
