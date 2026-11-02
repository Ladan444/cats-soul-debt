"""Склеивает картинки этажей (schema_F1..F4.png) и легенду в один лист Арт/Blender/rubezh_schema.png.
Запуск после build_schema.py: python Tools/blender/compose_schema.py
"""
from pathlib import Path

from PIL import Image

DIR = Path(__file__).resolve().parent.parent.parent / "Арт" / "Blender"
CELL = 1200

floors = [Image.open(DIR / f"schema_F{i}.png").convert("RGB").resize((CELL, CELL), Image.LANCZOS) for i in range(1, 5)]
legend = Image.open(DIR / "schema_legend.png").convert("RGB")
legend = legend.resize((int(legend.width * CELL * 2 / legend.height), CELL * 2), Image.LANCZOS)
sheet = Image.new("RGB", (CELL * 2 + legend.width, CELL * 2), (4, 4, 6))
for i, im in enumerate(floors):
    sheet.paste(im, ((i % 2) * CELL, (i // 2) * CELL))
sheet.paste(legend, (CELL * 2, 0))
sheet.save(DIR / "rubezh_schema.png")
print(DIR / "rubezh_schema.png", sheet.size)
