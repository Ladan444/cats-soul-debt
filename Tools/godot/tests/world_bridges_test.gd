extends SceneTree
## Мосты мира: Рэй идёт каждый мост пешком в обе стороны — по дороге ~30 м, на настил, через реку, ~30 м по дороге
## за мостом; клавишами, без телепорта. На настиле не должен оказаться у воды. Маршруты — assets/levels/world_bridges.json
## (пишет Tools/blender/build_world.py). Запуск: powershell -File Tools/godot_run.ps1 test Tools/godot/tests/world_bridges_test.gd

const BRIDGES_FILE := "res://assets/levels/world_bridges.json"
const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/world_bridge_%d.png"
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func walk(player: CharacterBody3D, target: Vector2, seconds: float, track: Array) -> bool:
	var ok := false
	var stuck_t := 0
	var last := player.global_position
	for f in int(seconds * 60.0):
		var d := target - Vector2(player.global_position.x, player.global_position.z)
		if d.length() < 1.0:
			ok = true
			break
		var dir := d.normalized()
		for a in [["move_right", dir.x], ["move_left", -dir.x], ["move_down", dir.y], ["move_up", -dir.y]]:
			if a[1] > 0.0:
				Input.action_press(a[0], a[1])
			else:
				Input.action_release(a[0])
		await physics_frame
		track.append(player.global_position.y)
		if player.global_position.distance_to(last) < 0.02:
			stuck_t += 1
			if stuck_t > 60:
				break
		else:
			stuck_t = 0
		last = player.global_position
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


func vecs(arr: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in arr:
		out.append(Vector2(p[0], p[1]))
	return out


## Идёт по точкам; deck_from..deck_to — участок настила (индексы точек). Возвращает [дошёл, минимум высоты на настиле].
func route(player: CharacterBody3D, pts: Array[Vector2], deck_from: int, deck_to: int) -> Array:
	await place(player, pts[0])
	var deck_min := INF
	for k in range(1, pts.size()):
		var track := []
		var ok: bool = await walk(player, pts[k], pts[k - 1].distance_to(pts[k]) / 3.5 * 2.0 + 3.0, track)
		if k > deck_from and k <= deck_to:
			for y in track:
				deck_min = minf(deck_min, y)
		if not ok:
			print("   застрял: Рэй (%.1f, %.1f, высота %.1f), шёл к точке %d (%.1f, %.1f)" % [player.global_position.x,
				player.global_position.z, player.global_position.y, k, pts[k].x, pts[k].y])
			return [false, deck_min]
	return [true, deck_min]


func _run() -> void:
	root.get_node("PlayerState").reset()
	change_scene_to_file("res://scenes/levels/world.tscn")
	for i in 120:
		await process_frame
	var scene := current_scene
	root.get_node("TimeOfDay").set_hour(11.0)
	var player := scene.get_node("Player") as CharacterBody3D
	var data = JSON.parse_string(FileAccess.get_file_as_string(BRIDGES_FILE))
	check(data is Array and data.size() == 4, "мостов в данных: %d" % (data.size() if data is Array else 0))
	var n := 0
	for b in data:
		n += 1
		var a := vecs(b["a"])
		var deck := vecs(b["deck"])
		var pts: Array[Vector2] = []
		pts.append_array(a)
		pts.append_array(deck)
		pts.append_array(vecs(b["b"]))
		var first := a.size()               # индекс начала настила
		var last := first + 1               # конец настила
		var res: Array = await route(player, pts, first, last)
		check(res[0], "%s, туда: пройден пешком" % b["name"])
		if res[0]:
			check(res[1] > float(b["water"]) + 0.2, "%s, туда: над водой (ниже всего %.2f, вода %.2f)" % [b["name"], res[1], b["water"]])
		pts.reverse()
		res = await route(player, pts, pts.size() - 1 - last, pts.size() - 1 - first)
		check(res[0], "%s, обратно: пройден пешком" % b["name"])
		if res[0]:
			check(res[1] > float(b["water"]) + 0.2, "%s, обратно: над водой (ниже всего %.2f, вода %.2f)" % [b["name"], res[1], b["water"]])
		# Снимок игровой камерой с середины настила.
		var mid := (deck[0] + deck[1]) / 2.0
		# С настила в воду не шагнуть: перила и в обе стороны держат (у ветхого — невидимая стенка в проломе).
		var across := (deck[1] - deck[0]).normalized().orthogonal()
		for side in [1.0, -1.0]:
			await place(player, mid)
			var y0 := player.global_position.y
			await walk(player, mid + across * side * 6.0, 2.5, [])
			var off := absf((Vector2(player.global_position.x, player.global_position.z) - mid).dot(across))
			check(off < 3.5 and player.global_position.y > y0 - 0.5, "%s: с настила вбок не сойти (ушёл на %.1f м, высота %.2f → %.2f)" % [b["name"], off, y0, player.global_position.y])
		await place(player, mid)
		for i in 60:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png(OUT % n)
	check(root.get_node("PlayerState").deaths == 0, "на мостах Рэй ни разу не утонул (смертей %d)" % root.get_node("PlayerState").deaths)
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
