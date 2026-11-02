extends SceneTree
## Мир вокруг Брода (scenes/levels/world.tscn): 7 фонарей душ, миникарта из вида сверху, фонарь зажигается
## и становится точкой возрождения, настил моста над водой держит Рэя, карта мира переносит к зажжённому
## фонарю, день и ночь меняют свет. Скриншоты — в Арт/Скриншоты.
## Запуск (в окне): Godot_console --resolution 1280x720 --path Game/CatsSoulDebt -s <абсолютный путь к файлу>

const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/world_%s.png"
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func shot(key: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT % key)


func _run() -> void:
	var ps = root.get_node("PlayerState")
	ps.lit_lanterns.clear()
	change_scene_to_file("res://scenes/levels/world.tscn")
	for i in 120:
		await process_frame
	var scene := current_scene
	var player: Node3D = scene.get_node("Player")
	var cam: Camera3D = scene.get_node("Camera3D")
	var lanterns := scene.get_node("Lanterns").get_children()
	check(lanterns.size() == 7, "фонарей душ: %d" % lanterns.size())
	check(scene.has_meta("minimap"), "миникарта из вида сверху")
	# Фонарь: подойти, зажечь.
	var lan: Node3D = lanterns[0]
	var spot: Vector3 = lan.call("respawn_point")
	player.global_position = spot + Vector3(0, 0.5, 0)
	cam.global_position = player.global_position + Vector3(0, 9, 11)
	for i in 60:
		await process_frame
	lan.call("light_up")
	check(ps.lit_lanterns.size() == 1, "фонарь зажжён и запомнен")
	for i in 60:
		await process_frame
	await shot("lantern_lit")
	# Мост: луч сверху над серединой главного моста попадает в мост, а не в дно реки.
	var deck := scene.get_node("Geometry/Bridge_cobble") as MeshInstance3D
	# Мостов несколько в одном меше: лучи над вершинами настила, ищем тот, что над водой (рельеф ниже на 1,5 м+).
	var faces: PackedVector3Array = deck.mesh.get_faces()
	var hit := {}
	var space := player.get_world_3d().direct_space_state
	for fi in range(0, faces.size() / 3, maxi(1, faces.size() / 3 / 200)):
		var v := deck.global_transform * ((faces[fi * 3] + faces[fi * 3 + 1] + faces[fi * 3 + 2]) / 3.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(v.x, 300, v.z), Vector3(v.x, -50, v.z))
		var h := space.intersect_ray(q)
		if h and h.collider.get_parent().name == "Bridge_cobble" and h.normal.y > 0.95 and _flat(space, h.position):
			var q2 := PhysicsRayQueryParameters3D.create(h.position - Vector3(0, 0.2, 0), Vector3(v.x, -50, v.z))
			var below := space.intersect_ray(q2)
			if below and h.position.y - below.position.y > 1.5:
				hit = h
				break
	check(not hit.is_empty(), "мост держит над водой: %s" % (hit.collider.get_parent().name if hit else "—"))
	if hit:
		player.global_position = hit.position + Vector3(0, 0.5, 0)
		cam.global_position = player.global_position + Vector3(0, 9, 11)
		for i in 90:
			await process_frame
		check(absf(player.global_position.y - hit.position.y) < 1.0, "Рэй стоит на мосту (y %.1f / %.1f)" % [player.global_position.y, hit.position.y])
		await shot("bridge")
	# Смерть вдали от фонаря → возрождение у него.
	player.global_position = spot + Vector3(40, 3, 40)
	for i in 30:
		await process_frame
	ps.damage(9999, player.global_position)
	for i in 600:
		await process_frame
	var d := Vector2(player.global_position.x - spot.x, player.global_position.z - spot.z).length()
	check(d < 3.0, "возрождение у фонаря (%.1f м)" % d)
	await shot("respawn")
	# Карта мира: открыть, выбрать зажжённый фонарь, перенестись издалека.
	var map := scene.get_node("WorldMap")
	player.global_position = spot + Vector3(-300, 5, 200)
	for i in 30:
		await process_frame
	map.call("open_map")
	for i in 20:
		await process_frame
	check(map.call("is_open") and paused, "карта мира открыта, игра на паузе")
	await shot("world_map")
	map.call("_cycle", 1)
	for i in 10:
		await process_frame
	await shot("world_map_selected")
	# Перенос к фонарю бесплатный: с пустым кошельком работает и ничего не списывает.
	ps.helios = 0
	map.call("_travel", map.get("_selected"))
	for i in 90:
		await process_frame
	var d2 := Vector2(player.global_position.x - spot.x, player.global_position.z - spot.z).length()
	check(not map.call("is_open") and not paused, "карта закрыта после переноса")
	check(d2 < 3.0, "перенос к фонарю (%.1f м)" % d2)
	check(ps.helios == 0, "перенос к фонарю бесплатный (гелиосов %d)" % ps.helios)
	# Перенос в любую точку карты — 100 гелиосов; Рэй появляется на ближайшей точке дороги.
	var W: GDScript = load("res://scripts/ui/waypoints.gd")
	var cost: int = map.get("POINT_TRAVEL_COST")
	map.call("open_map")
	for i in 20:
		await process_frame
	var target := Vector2(250.0, -120.0)   # в поле, не на дороге
	var mpp: float = map.get("map_mpp")
	var origin: Vector2 = map.get("map_origin")
	map.call("_select_point", (target - origin) / mpp)
	for i in 5:
		await process_frame
	check(map.get("_point") != null, "клик по карте выбрал точку")
	ps.helios = cost - 1
	map.call("_refresh_panel")
	var before := player.global_position
	map.call("_go_pressed")
	for i in 20:
		await process_frame
	check(player.global_position.distance_to(before) < 0.5 and map.call("is_open"), "при %d гелиосах перенос в точку не срабатывает" % (cost - 1))
	check((map.get("_go") as Button).disabled, "кнопка неактивна: «%s»" % (map.get("_go") as Button).text)
	ps.helios = cost + 7
	map.call("_refresh_panel")
	check(not (map.get("_go") as Button).disabled, "при %d гелиосах кнопка активна: «%s»" % [cost + 7, (map.get("_go") as Button).text])
	map.call("_go_pressed")
	for i in 90:
		await process_frame
	check(ps.helios == 7, "перенос в точку списал %d гелиосов (осталось %d)" % [cost, ps.helios])
	var off_road: float = W.distance_to_road(Vector2(player.global_position.x, player.global_position.z))
	check(off_road < 2.0, "Рэй стоит на дороге (до ленты %.2f м)" % off_road)
	check(Vector2(player.global_position.x, player.global_position.z).distance_to(target) > 5.0, "и не в выбранной точке в поле — на дороге")
	# Время суток: полдень и полночь меняют солнце.
	var tod = root.get_node("TimeOfDay")
	var sun: DirectionalLight3D = scene.get_node("Sun")
	tod.set_hour(12.0)
	for i in 5:
		await process_frame
	var noon := sun.light_energy
	await shot("noon")
	tod.set_hour(0.0)
	for i in 5:
		await process_frame
	check(sun.light_energy < noon * 0.5, "ночью свет слабее (%.2f / %.2f)" % [sun.light_energy, noon])
	await shot("night")
	tod.set_hour(20.4)
	for i in 5:
		await process_frame
	await shot("dusk")
	tod.set_hour(12.0)
	ps.lit_lanterns.clear()
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)


## Ровный настил: соседние точки (±1 м) — тоже настил на той же высоте (а не верх парапета).
func _flat(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	for o in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var p: Vector3 = at + o
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 50, 0), p - Vector3(0, 50, 0)))
		if h.is_empty() or absf(h.position.y - at.y) > 0.3:
			return false
	return true
