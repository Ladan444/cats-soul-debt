extends SceneTree
## Наполнение мира: подлесок и мелочи из nature_extras.glb есть в расстановке и показываются участками вокруг Рэя,
## узлов не копится; дорога свободна, 12 особых мест на месте и их можно двигать, в пруд родника можно зайти и не утонуть.
## Запуск: powershell -File Tools/godot_run.ps1 test Tools/godot/tests/world_extras_test.gd

const NATURE_FILE := "res://assets/levels/world_nature.json"
const EXTRAS_INFO := "res://assets/models/nature/pack_extras.json"
## Спуск в пруд родника и его середина (Godot x, z).
const SPRING_EDGE := Vector2(212.0, -209.0)
const SPRING_MID := Vector2(212.0, -216.0)
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func walk(player: Node3D, target: Vector2, seconds: float) -> bool:
	var ok := false
	for f in int(seconds * 60.0):
		var d := target - Vector2(player.global_position.x, player.global_position.z)
		if d.length() < 1.0:
			ok = true
			break
		if not player.is_alive():
			break
		var dir := d.normalized()
		for a in [["move_right", dir.x], ["move_left", -dir.x], ["move_down", dir.y], ["move_up", -dir.y]]:
			if a[1] > 0.0:
				Input.action_press(a[0], a[1])
			else:
				Input.action_release(a[0])
		await physics_frame
	for a in ["move_right", "move_left", "move_down", "move_up"]:
		Input.action_release(a)
	return ok


func place(player: Node3D, at: Vector2) -> void:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 120, at.y), Vector3(at.x, -60, at.y))
	q.collision_mask = 1
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	player.global_position = (hit.position if hit else Vector3(at.x, 10, at.y)) + Vector3(0, 0.3, 0)
	for i in 20:
		await physics_frame


func _run() -> void:
	var ps := root.get_node("PlayerState")
	ps.reset()
	change_scene_to_file("res://scenes/levels/world.tscn")
	for i in 120:
		await process_frame
	var scene := current_scene
	var player: Node3D = scene.get_node("Player")
	var nature := scene.find_child("Nature", true, false)
	check(nature != null, "узел растительности в мире")

	# Каждая модель из расстановки есть в библиотеке, новые группы подключились.
	var placed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NATURE_FILE))
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXTRAS_INFO))["models"]
	var missing := []
	var extras_count := 0
	for model in placed:
		if not nature.meshes.has(model):
			missing.append(model)
		if String(model).begins_with("Dt_") or String(model).begins_with("Pr_"):
			extras_count += placed[model].size() / 5
	check(missing.is_empty(), "все модели расстановки есть в библиотеке %s" % str(missing))
	check(extras_count > 100000, "мелочей в мире: %d" % extras_count)
	var unused := []
	for model in info:
		if not placed.has(model):
			unused.append(model)
	print("   моделей в паке дополнений: %d, не использованы: %s" % [info.size(), str(unused)])

	# Особые места стоят, их можно двигать, в них есть вода.
	for id in ["spring", "falls", "giant", "ruin", "stones", "outcrop_w", "outcrop_s", "marsh", "arch", "oak", "camp", "piers"]:
		var g := scene.find_child("Edit_detail_vignette_" + id, true, false)
		check(g != null, "особое место %s — группа правки" % id)
	check(scene.find_child("Poi_water__detail_vignette_spring", true, false) != null, "вода родника")

	# Мелочи показываются только вокруг Рэя: далеко — другой набор, узлов не больше прежнего.
	var live_near: int = nature._stream_live.size()
	check(live_near > 0, "участков мелочей вокруг Рэя: %d" % live_near)
	var keys_before: Array = nature._stream_live.keys()
	await place(player, Vector2(500.0, -500.0))
	for i in 120:
		await process_frame
	var kept := 0
	for key in keys_before:
		if nature._stream_live.has(key):
			kept += 1
	check(kept == 0 and nature._stream_live.size() <= 60, "после перехода старые участки убраны (осталось %d, всего %d)" % [kept, nature._stream_live.size()])

	# Дорога к мосту не перегорожена.
	var routes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/levels/world_bridges.json"))
	var main: Dictionary = routes[0]
	var pts: Array[Vector2] = []
	for p in main["a"]:
		pts.append(Vector2(p[0], p[1]))
	var ok := true
	await place(player, pts[0])
	for k in range(1, pts.size()):
		ok = ok and await walk(player, pts[k], pts[k - 1].distance_to(pts[k]) / 3.5 * 2.0 + 3.0)
	check(ok, "дорога к Главному мосту свободна")

	# Пруд родника мелкий: зайти можно, не тонет.
	await place(player, SPRING_EDGE)
	await walk(player, SPRING_MID, 6.0)
	for i in 90:
		await physics_frame
	check(ps.deaths == 0 and player.is_alive(), "в пруду родника Рэй не тонет (смертей %d)" % ps.deaths)
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
