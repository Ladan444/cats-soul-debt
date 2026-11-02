"""Дороги, мосты и места мира → Game/CatsSoulDebt/data/world_routes.json для навигатора (маршрут по дорогам, как в GTA).
Источник — Tools/world_layout.py (ROADS, BRIDGES, POIS). Координаты — метры Godot: x — восток, z = −y (север — вверх по −z).
  python Tools/world_routes.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import world_layout as W  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "Game" / "CatsSoulDebt" / "data" / "world_routes.json"


def g(px, py):
    x, y = W.P(px, py)
    return [round(x, 1), round(-y, 1)]


def main() -> None:
    data = {
        "roads": [{"kind": kind, "points": [g(*p) for p in pts]} for kind, pts in W.ROADS],
        "bridges": [{"name": name, "a": g(*a), "b": g(*b)} for name, a, b in W.BRIDGES],
        "pois": {p[0]: {"name": p[2], "at": g(p[3], p[4])} for p in W.POIS},
        "gate": g(*W.FORTRESS["gate"]),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"дорог {len(data['roads'])}, мостов {len(data['bridges'])}, мест {len(data['pois'])} → {OUT}")


if __name__ == "__main__":
    main()
