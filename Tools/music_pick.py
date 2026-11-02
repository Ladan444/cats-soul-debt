"""Музыка из скачанных наборов OpenGameArt → assets/audio/music/ + замер громкости.

Копирует выбранные дорожки (TRACKS; из zip — распаковкой одного файла), меряет громкость (RMS громкой половины
дорожки, дБ полной шкалы) и печатает поправку `gain` до общей цели TARGET — её вписать в TRACKS в scripts/core/audio.gd,
чтобы тихие и громкие дорожки звучали ровно. Без громкостей в коде: решение — за автором на слух (мастер-меню «Музыка»).

  python Tools/music_pick.py            # копировать и замерить
  python Tools/music_pick.py --measure  # только замерить уже скопированное
"""

import io
import json
import sys
import zipfile
from pathlib import Path

import miniaudio
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Арт" / "Ассеты" / "Audio" / "OpenGameArt" / "dnd-rpg-fantasy-music"
OUT = ROOT / "Game" / "CatsSoulDebt" / "assets" / "audio" / "music"
TARGET = -20.0

# имя в игре: (папка набора, файл или «архив.zip:файл в архиве»)
TRACKS = {
    "death_is_just_another_path.ogg": ("death-is-just-another-path", "Death Is Just Another Path.ogg"),
    "sylvan_waltz.mp3": ("sylvan-waltz-standard-looped-version", "Otto Halmén - Sylvan Waltz_1.mp3"),
    "peaceful_place.ogg": ("peaceful-place", "Peaceful Place.ogg"),
    "winds_of_stories.ogg": ("winds-of-stories", "Winds Of Stories.ogg"),
    "secret_within_the_woods.ogg": ("rpg-the-secret-within-the-woods", "RPG - The Secret Within The Silent Woods.ogg"),
    "beyond_the_stars.ogg": ("beyond-the-stars-ambient", "Beyond_the_Stars_Ambient_.ogg"),
    "spirit_waltz.ogg": ("spirit-waltz", "Spirit Waltz_0.ogg"),
    "trading_for_memories.mp3": ("trading-it-for-the-memories", "Trading.mp3"),
    "dark_descent.mp3": ("dark-descent", "Dark Descent_0.mp3"),
    "cave_theme.ogg": ("cave-theme", "cave themeb4.ogg"),
    "town_in_ruins.ogg": ("town-in-ruins-loop", "n3535n5n335n35nj.ogg"),
    "midnight_creeping.mp3": ("midnight-creeping-rpg-orchestral-essentials-stealth-music",
                              "midnight_creeping_mp3.zip:Midnight Creeping MP3.mp3"),
    "dark_forest.mp3": ("dark-forest-theme", "GameMusic_ForestTheme_24_0.mp3"),
    "regular_battle.mp3": ("a-regular-battle", "regular battle.mp3"),
    "battle_theme_a.mp3": ("battle-theme-a", "battleThemeA.mp3"),
    "small_loss.ogg": ("small-loss-2", "Small Loss_2.ogg"),
    "vampires_piano.mp3": ("vampires-piano", "vampires_piano_6.mp3"),
    "lurid_delusion.mp3": ("lurid-delusion", "Lurid Delusion_0.mp3"),
}


def copy(name: str, folder: str, file: str) -> None:
    dst = OUT / name
    if dst.exists():
        return
    if ":" in file:
        archive, inner = file.split(":", 1)
        with zipfile.ZipFile(SRC / folder / archive) as z:
            dst.write_bytes(z.read(inner))
    else:
        dst.write_bytes((SRC / folder / file).read_bytes())


def measure(path: Path) -> dict:
    snd = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1, sample_rate=22050)
    x = np.frombuffer(snd.samples, dtype=np.float32)
    win = 22050 // 2
    blocks = x[: len(x) // win * win].reshape(-1, win)
    rms = np.sqrt((blocks ** 2).mean(axis=1) + 1e-12)
    loud = np.sort(rms)[len(rms) // 2:]        # громкая половина: тихие вступления не занижают оценку
    level = 20 * np.log10(loud.mean())
    active = np.nonzero(rms > 10 ** (-50 / 20))[0]
    return {"sec": round(len(x) / 22050, 1), "rms_db": round(float(level), 1), "gain": round(TARGET - float(level), 1),
            "peak_db": round(float(20 * np.log10(np.abs(x).max() + 1e-12)), 1),
            "lead_silence": round(float(active[0] * 0.5), 1) if len(active) else 0.0}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    names = sorted(p.name for p in OUT.iterdir() if p.suffix in (".ogg", ".mp3", ".wav"))
    if "--measure" not in sys.argv:
        for name, (folder, file) in TRACKS.items():
            copy(name, folder, file)
        names = sorted(set(names) | set(TRACKS))
    table = {}
    for name in names:
        table[name] = measure(OUT / name)
        print(f"{name:34s} {table[name]}")
    (ROOT / "Арт" / "Ассеты" / "Audio" / "music_levels.json").write_text(json.dumps(table, ensure_ascii=False, indent=1),
                                                                         encoding="utf-8")


if __name__ == "__main__":
    main()
