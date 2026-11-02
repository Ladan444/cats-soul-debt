"""Карты журнала (JournalMap, UI_SPEC раздел 4) из планировок — один источник правды с уровнями.

  Каменный Рубеж, этаж 1 — Tools/blender/rubezh_layout.py: залы, коридоры связей (как в build_greybox),
                            фонари душ, двери, круг печати; заметки Рэя — NOTES ниже.
  (Ивовый Брод — в мире: на M там карта мира с быстрыми перемещениями; старый Брод убран 2026-10-29.)
  Таверна                 — зал и комната Рэя (размеры из Tools/blender/build_tavern.py).

Комната: {"id", "name", "world": Rect2(x, z, ширина, глубина) в осях Godot (Blender y → −z), "note",
"hinted", "hint_note" (подпись намеченного места в списке), "features"}; проходы — "passage": true (рисуются без номера и в список не идут).
Запуск: python Tools/journal_maps.py → Game/CatsSoulDebt/data/maps/<id>.tres
"""
import os
import sys
import types

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Game", "CatsSoulDebt", "data", "maps")
BLENDER = os.path.join(ROOT, "Tools", "blender")
CORRIDOR_W = 3.0   # как в build_greybox.py

# build_schema.py импортирует bpy/bmesh ради отрисовки схемы; маршруты route/bounds от них не зависят.
for _m in ("bpy", "bmesh"):
    sys.modules.setdefault(_m, types.ModuleType(_m))
schema = {"__name__": "schema"}
exec(open(os.path.join(BLENDER, "build_schema.py"), encoding="utf-8").read(), schema)


def load_layout(name):
    ns = {}
    exec(open(os.path.join(BLENDER, name), encoding="utf-8").read(), ns)
    return ns


# Заметки Рэя о залах Рубежа (видны, когда зал исследован). Тон — сухой, без раскрытия сюжета наперёд.
NOTES = {
    "gate": "Ворота открыты настежь. Раньше здесь спрашивали пароль — теперь только ветер.",
    "guard": "Журнал караула раскрыт, последняя строка пустая.",
    "yard": "Здесь нас гоняли строем. Фонарь у стены ещё держит тепло.",
    "stairs_up": "Наверх — потом.",
    "barracks": "Наша рота. Койки ровными рядами, будто все вот-вот вернутся.",
    "armory": "Половина мечей сломана о что-то, чего здесь уже нет.",
    "mess": "Столы опрокинуты к двери — её держали до последнего.",
    "cellar": "Бочки целы, а свод того и гляди рухнет.",
    "treasury": "Шкатулку графа не открыть. И медальон — её медальон.",
    "crypt": "Свечи здесь кто-то зажигал — недавно.",
    "ossuary": "Кости уложены аккуратно, как на смотре.",
    "niche": "Чей-то последний пост.",
    "chapel": "Засов изнутри — кто-то запирался от своих?",
    "flooded": "Лодки на привязи, а вода стоит выше, чем должна.",
    "bridge": "Снизу тянет холодом и фиолетовым светом.",
    "great": "Круг из чёрного камня. Граф сказал ждать здесь.",
}
CORRIDOR_NOTES = {"dr": "Вода по щиколотку, и в ней кто-то ходит.",
                  "nw": "Узкие ходы — тесно даже для кота.",
                  "e": "Имена на урнах стёрты."}
# Что Рэй знает заранее (граф объяснил дорогу): намечено карандашом с начала.
HINTED_RUBEZH = {"gate", "yard", "bridge", "great"}


def rect(x, y, w, d):
    """Прямоугольник по центру в осях Blender (x, y) → Rect2 в осях Godot (x, z = −y)."""
    return (x - w / 2, -y - d / 2, w, d)


def passages(floor):
    """Коридоры связей — прямоугольники по отрезкам маршрута (как пол коридоров в build_greybox)."""
    rooms = {r[0]: r for r in floor["rooms"]}
    out = []
    for a, b, kind, label in floor["links"]:
        path = schema["route"](rooms[a], rooms[b])
        for i, ((x0, y0), (x1, y1)) in enumerate(zip(path, path[1:])):
            w, d = abs(x1 - x0) + CORRIDOR_W, abs(y1 - y0) + CORRIDOR_W
            out.append({"id": "link:%s-%s:%d" % (a, b, i), "name": "", "passage": True,
                        "world": rect((x0 + x1) / 2, (y0 + y1) / 2, w, d), "note": "", "hinted": False, "features": []})
    return out


def rubezh(floor_id="F1"):
    layout = load_layout("rubezh_layout.py")
    floor = next(f for f in layout["FLOORS"] if f["id"] == floor_id)
    rooms = {r[0]: r for r in floor["rooms"]}
    features = {rid: [] for rid in rooms}

    def owner(x, y):
        for rid, _, rx, ry, w, d, z, tags in floor["rooms"]:
            if abs(x - rx) <= w / 2 and abs(y - ry) <= d / 2:
                return rid
        return None

    for kind, x, y, label in floor["marks"]:
        if kind == "lantern" and owner(x, y):
            features[owner(x, y)].append({"type": "lantern", "pos": (x, -y)})
    for a, b, kind, label in floor["links"]:
        if kind in ("open", "stairs"):
            continue
        path = schema["route"](rooms[a], rooms[b])
        dx, dy = schema["door_point"](path, rooms[b])
        features[b].append({"type": "door", "pos": (dx, -dy)})
    if "great" in rooms:
        features["great"].append({"type": "seal", "pos": (rooms["great"][2], -rooms["great"][3])})

    out = []
    for rid, title, x, y, w, d, z, tags in floor["rooms"]:
        corridor = "corridor" in tags
        name = title.replace("\n", " ").replace("- ", "").strip()
        if corridor:
            prefix = next((p for p in CORRIDOR_NOTES if rid.startswith(p)), "")
            note = CORRIDOR_NOTES.get(prefix, "")
            name = name or "проход"
        else:
            note = NOTES.get(rid, "")
        out.append({"id": rid, "name": name, "world": rect(x, y, w, d), "note": note,
                    "hinted": rid in HINTED_RUBEZH, "hint_note": "граф объяснил дорогу, сам ещё не был.",
                    "features": features[rid], "passage": corridor and not title})
    return "rubezh_" + floor_id.lower(), "Каменный Рубеж — " + floor["title"].split("—")[-1].strip(), out + passages(floor)


def tavern():
    # Зал 14 × 10 м (стены по x = ±7, y = ±5), комната Рэя — за перегородкой x = 3, y = 0 (build_tavern.py).
    return "tavern", "Таверна «Красная черепица»", [
        {"id": "ray_room", "name": "Моя комната", "world": rect(5, 2.5, 4, 5),
         "note": "Кровать, сундук и свеча. Граф не берёт с меня платы.", "hinted": True, "features": []},
        {"id": "hall", "name": "Общий зал", "world": rect(0, 0, 14, 10),
         "note": "Стойка графа у северной стены, камин у западной.", "hinted": True,
         "features": [{"type": "fire", "pos": (-6.1, 0.0)}, {"type": "door", "pos": (-1.0, 5.0)}]},
    ]


# --- Запись .tres -----------------------------------------------------------------------------

def gd_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(round(float(v), 3)).rstrip("0").rstrip(".") if float(v) != int(v) else str(int(v))
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, tuple) and len(v) == 4:
        return "Rect2(%s)" % ", ".join(gd_value(c) for c in v)
    if isinstance(v, tuple) and len(v) == 2:
        return "Vector2(%s)" % ", ".join(gd_value(c) for c in v)
    if isinstance(v, list):
        return "[" + ", ".join(gd_value(c) for c in v) + "]"
    if isinstance(v, dict):
        return "{\n" + ",\n".join('"%s": %s' % (k, gd_value(val)) for k, val in v.items()) + "\n}"
    raise TypeError(v)


def write(map_id, title, rooms):
    text = ('[gd_resource type="Resource" script_class="JournalMap" format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/data/journal_map.gd" id="1_map"]\n\n'
            '[resource]\nscript = ExtResource("1_map")\n'
            'id = &"%s"\ntitle = %s\nrooms = Array[Dictionary](%s)\n' % (map_id, gd_value(title), gd_value(rooms)))
    path = os.path.join(OUT, map_id + ".tres")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    named = sum(1 for r in rooms if not r.get("passage"))
    print("сохранено: %s — мест %d, проходов %d" % (path, named, len(rooms) - named))


if __name__ == "__main__":
    for builder in (rubezh, tavern):
        write(*builder())
