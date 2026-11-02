@tool
extends EditorPlugin
## Ручные правки мира (решение автора 2026-10-29). В сцене scenes/levels/world.tscn у узла Geometry — группы
## «Edit_<id>»: дома и постройки (house:…), пролёты заборов и частокол (fence:…), мелочи (detail:…).
## Двигай и поворачивай их (только по земле и вокруг вертикали), убрать — выключить видимость (глазок).
## Меню Проект → Инструменты → «Мир: сохранить правки» пишет сдвиг от исходного места в Tools/world_overrides.json;
## пересборка мира с правками — powershell -File Tools/rebuild_world.ps1 (Blender → Godot), после неё сцену
## переоткрыть. «Мир: сбросить правки выбранных» — вернуть выбранные группы на исходные места (в файле).

const MENU_SAVE := "Мир: сохранить правки"
const MENU_RESET := "Мир: сбросить правки выбранных"


func _enter_tree() -> void:
	add_tool_menu_item(MENU_SAVE, _save)
	add_tool_menu_item(MENU_RESET, _reset_selected)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_SAVE)
	remove_tool_menu_item(MENU_RESET)


func _path() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../../Tools/world_overrides.json").simplify_path()


func _load() -> Dictionary:
	if not FileAccess.file_exists(_path()):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	return d if d is Dictionary else {}


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t", true))
	f.close()


func _groups() -> Array:
	var root := EditorInterface.get_edited_scene_root()
	var geo := root.get_node_or_null("Geometry") if root else null
	if geo == null:
		push_warning("Правки мира: открой scenes/levels/world.tscn")
		return []
	return geo.find_children("Edit_*", "Node3D", true, false)


func _save() -> void:
	var data := _load()
	var changed := 0
	for e: Node3D in _groups():
		var ex: Dictionary = e.get_meta("extras", {})
		if not ex.has("edit_id"):
			continue
		var id := String(ex["edit_id"])
		# Godot (x, z) → Blender (x, −z); поворот вокруг вертикали совпадает по знаку.
		var dx := e.position.x - float(ex["base_x"])
		var dy := -e.position.z - float(ex["base_y"])
		var rot := rad_to_deg(e.rotation.y)
		var entry := {"dx": snappedf(dx, 0.01), "dy": snappedf(dy, 0.01), "rot": snappedf(rot, 0.1), "hide": not e.visible}
		var was: Dictionary = data.get(id, {})
		if absf(dx) < 0.02 and absf(dy) < 0.02 and absf(rot) < 0.2 and e.visible:
			if data.has(id):
				data.erase(id)
				changed += 1
		elif was != entry:
			data[id] = entry
			changed += 1
	_write(data)
	print("Правки мира: изменено %d, всего правок %d → %s. Пересборка: powershell -File Tools/rebuild_world.ps1"
		% [changed, data.size(), _path()])


func _reset_selected() -> void:
	var data := _load()
	var n := 0
	for node in EditorInterface.get_selection().get_selected_nodes():
		var e := node as Node3D
		while e and not String(e.name).begins_with("Edit_"):
			e = e.get_parent() as Node3D
		if e == null:
			continue
		var ex: Dictionary = e.get_meta("extras", {})
		if ex.has("edit_id") and data.has(String(ex["edit_id"])):
			data.erase(String(ex["edit_id"]))
			n += 1
	_write(data)
	print("Правки мира: сброшено %d (вернутся на место после пересборки)" % n)
