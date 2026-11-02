extends SceneTree
## Группы ручной правки мира (Geometry/Edit_<id>, плагин addons/world_edits): у каждой есть id и исходное место,
## без правок узел стоит на исходном месте; дома, заборы и мелочи — отдельные группы с мешами внутри; меши в группах
## одеты (материалы шейдеров), колесо мельницы найдено в группе.
## Запуск: powershell -File Tools/godot_run.ps1 htest Tools/godot/tests/world_edits_test.gd

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _run() -> void:
	change_scene_to_file("res://scenes/levels/world.tscn")
	for i in 30:
		await process_frame
	var geo := current_scene.get_node("Geometry")
	var groups := geo.find_children("Edit_*", "Node3D", true, false)
	check(groups.size() > 80, "групп правки: %d" % groups.size())
	var kinds := {}
	var bad := []
	var overrides := {}
	var path := ProjectSettings.globalize_path("res://").path_join("../../Tools/world_overrides.json").simplify_path()
	if FileAccess.file_exists(path):
		overrides = JSON.parse_string(FileAccess.get_file_as_string(path))
	for e: Node3D in groups:
		var ex: Dictionary = e.get_meta("extras", {})
		if not ex.has("edit_id"):
			bad.append(String(e.name))
			continue
		var id := String(ex["edit_id"])
		kinds[id.get_slice(":", 0)] = true
		if not overrides.has(id):
			var d := Vector2(e.position.x - float(ex["base_x"]), -e.position.z - float(ex["base_y"]))
			if d.length() > 0.05:
				bad.append("%s сдвинут на %.2f без правки" % [id, d.length()])
	check(bad.is_empty(), "у всех групп id и исходное место %s" % str(bad.slice(0, 5)))
	check(kinds.has("house") and kinds.has("fence") and kinds.has("detail"), "виды групп: %s" % str(kinds.keys()))
	var smithy := geo.get_node_or_null("Edit_house_smithy")
	check(smithy != null and smithy.find_children("Houses__*", "MeshInstance3D", true, false).size() == 1,
		"кузница — группа с домом из модулей")
	var dressed := 0
	var plain := 0
	for m: MeshInstance3D in geo.find_children("*__*", "MeshInstance3D", true, false):
		if m.material_override or (m.mesh and m.mesh.get_surface_count() > 0 and m.get_surface_override_material(0)):
			dressed += 1
		else:
			plain += 1
	print("   мешей в группах: одеты %d, по материалам glb %d" % [dressed, plain])
	check(dressed > 100, "меши групп одеты шейдерами мира")
	check(geo.find_child("MillWheel*", true, false) != null, "колесо мельницы в группе")
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
