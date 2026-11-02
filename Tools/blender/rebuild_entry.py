"""Запуск сборки мира без окна (Tools/rebuild_world.ps1): blender -b --python <этот файл> [-- nomap].
Собирает мир с ручными правками (Tools/world_overrides.json), пишет glb для Godot и вид сверху для миникарты."""
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
ns = {"__name__": "__main__", "BUILD_EXPORT": True, "MAP_TOP": "nomap" not in sys.argv}
exec(open(os.path.join(here, "build_world.py"), encoding="utf-8").read(), ns)
print("REBUILD_OK", ns.get("result_info"))
