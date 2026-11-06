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


ROOF_SIZES = {4: (4, 6, 8), 6: (4, 6, 8, 10, 12, 14), 8: (8, 10, 12, 14)}   # как в Tools/blender/build_world.py
MARGIN = 2.0   # запас вокруг дома: навес крыши, крыльцо


def buildings():
    """Контуры домов деревни (4 угла, метры Godot) — маршрут обходит их. Размеры и правки автора — как в build_world.village_plan."""
    import math
    ovr_path = Path(__file__).resolve().parent / "world_overrides.json"
    ovr = json.loads(ovr_path.read_text(encoding="utf-8")) if ovr_path.exists() else {}
    out = []
    for rid, _name, x, y, w, d, kind in W.VILLAGE:
        if kind not in ("building", "shed", "watermill"):
            continue
        o = ovr.get("house:" + rid, {})
        if o.get("hide"):
            continue
        bx, by = W.P(x, y)
        cx, cy = bx + float(o.get("dx", 0.0)), by + float(o.get("dy", 0.0))
        along_y = d >= w
        span = min((4, 6, 8), key=lambda sp: abs(sp - (w if along_y else d)))
        length = min(ROOF_SIZES[span], key=lambda ln: abs(ln - (d if along_y else w)))
        ww, dd = (span, length) if along_y else (length, span)
        hw, hd = ww / 2 + MARGIN, dd / 2 + MARGIN
        a = math.radians(float(o.get("rot", 0.0)))
        c, sn = math.cos(a), math.sin(a)
        pts = []
        for ux, uy in ((-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)):
            px, py = cx + ux * c - uy * sn, cy + ux * sn + uy * c
            pts.append([round(px, 1), round(-py, 1)])
        out.append({"id": rid, "poly": pts})
    return out


def main() -> None:
    data = {
        "roads": [{"kind": kind, "points": [g(*p) for p in pts]} for kind, pts in W.ROADS],
        "bridges": [{"name": name, "a": g(*a), "b": g(*b)} for name, a, b in W.BRIDGES],
        "pois": {p[0]: {"name": p[2], "at": g(p[3], p[4])} for p in W.POIS},
        "gate": g(*W.FORTRESS["gate"]),
        "buildings": buildings(),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"дорог {len(data['roads'])}, мостов {len(data['bridges'])}, мест {len(data['pois'])} → {OUT}")


if __name__ == "__main__":
    main()
