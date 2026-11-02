extends SceneTree
## Лагеря врагов мира (scripts/levels/world_camps.gd): появляются, когда Рэй рядом; виды и число по решению автора
## (квалды 3 у пристани, кобольды 4 в ущелье и 3 на лесной тропе одной стаей, голем у шахты, мини-босс у штольни);
## враги стоят на земле и через 2 с не провалились. Скриншоты — Арт/Скриншоты/world_camp_<id>.png.
## Запуск: powershell -File Tools/godot_run.ps1 test Tools/godot/tests/world_camps_test.gd

const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/world_camp_%s.png"
const EXPECT := {"pier_kvalds": ["kvald.gd", 3], "gorge_kobolds": ["kobold.gd", 4], "forest_kobolds": ["kobold.gd", 3],
	"mine_golem": ["mine_golem.gd", 1], "adit_boss": ["mine_golem.gd", 1]}
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _run() -> void:
	root.get_node("PlayerState").reset()
	change_scene_to_file("res://scenes/levels/world.tscn")
	for i in 120:
		await process_frame
	var scene := current_scene
	root.get_node("TimeOfDay").set_hour(11.0)
	root.get_node("Cheats").show_hint = false
	var camps := scene.get_node("Camps")
	var player := scene.get_node("Player") as Node3D
	var cam := scene.get_node("Camera3D") as Camera3D
	for id in EXPECT:
		var at: Vector2 = camps.CAMPS[id]["at"]
		# Рэй — в 40 м южнее (лагерь появляется ближе 70 м, засада кобольдов — ближе 6 м — не срабатывает).
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.global_position = Vector3(at.x, 200, at.y + 40.0)
		for i in 10:
			await process_frame
		var enemies := camps.get_children().filter(func(n): return String(n.name).begins_with("Camp_%s_" % id))
		var ok_kind := enemies.all(func(n): return n.get_script().resource_path.ends_with(EXPECT[id][0]))
		check(enemies.size() == EXPECT[id][1] and ok_kind, "%s: врагов %d (%s)" % [id, enemies.size(), EXPECT[id][0]])
		var y0 := {}
		for n in enemies:
			y0[n] = (n as Node3D).global_position.y
		for i in 120:
			await physics_frame
		var fell := enemies.filter(func(n): return (n as Node3D).global_position.y < y0[n] - 1.5)
		check(fell.is_empty(), "%s: на земле, не провалились" % id)
		# Рядом (1 м) нет чужих тел — враг не застрял в скале, доме или дереве.
		var stuck := []
		var space := (player as Node3D).get_world_3d().direct_space_state
		for n in enemies:
			var q := PhysicsShapeQueryParameters3D.new()
			var sh := SphereShape3D.new()
			sh.radius = 1.0
			q.shape = sh
			q.transform = Transform3D(Basis(), (n as Node3D).global_position + Vector3(0, 1.2, 0))
			q.exclude = [n.get_rid(), player.get_rid()]
			for hit in space.intersect_shape(q, 8):
				var c := hit.collider as Node
				if c and String(c.name) != "TerrainBody" and not c.is_in_group("enemies") and not String(c.name).begins_with("Camp_"):
					stuck.append("%s в %s" % [n.name, c.name])
		check(stuck.is_empty(), "%s: не застряли %s" % [id, str(stuck.slice(0, 3))])
		if id.ends_with("kobolds"):
			var packs := {}
			for n in enemies:
				packs[n.get("pack_id")] = true
			check(packs.size() == 1, "%s: одна стая %s" % [id, str(packs.keys())])
		if id == "adit_boss":
			check(enemies.size() == 1 and enemies[0].get("boss") == true, "у штольни — мини-босс")
		var c := Vector3(at.x, y0[enemies[0]] if not enemies.is_empty() else 0.0, at.y)
		cam.process_mode = Node.PROCESS_MODE_DISABLED
		cam.look_at_from_position(c + Vector3(6, 16, 18), c + Vector3(0, 1, 0))
		for i in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT % id)
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
