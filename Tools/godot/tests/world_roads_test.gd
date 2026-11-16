extends SceneTree
## Дороги свободны: силуэт Рэя (капсула как в player.tscn) проходит по всей ширине каждой дороги, тропы и улицы
## и ни во что не упирается. Линии — assets/levels/world_roads.json (пишет Tools/blender/build_world.py).
## Природа не должна касаться ленты нигде. Постройки могут только сужать проезд у краёв (арка, столбы ворот),
## а на последних метрах линии — стоять поперёк: так улица приходит к двери, а тропа к постаменту.
## Мосты проверяет world_bridges_test.gd, здесь они пропускаются вместе с участками над водой.
## Запуск: powershell -File Tools/godot_run.ps1 test Tools/godot/tests/world_roads_test.gd

const ROADS_FILE := "res://assets/levels/world_roads.json"
const STEP := 0.75
const RADIUS := 0.35
const HEIGHT := 1.1
const LIFT := 0.3
## Конец линии, где постройка не считается препятствием (м) и доля ширины, где она уже мешает пройти.
const LINE_END := 4.0
const MIDDLE := 0.55
## Места, где стояли камни, ива, жаровни и вагонетка (x, y в Blender): здесь Рэй идёт пешком, клавишами.
const WALK_SPOTS := [Vector2(-310, 399), Vector2(-306, 410), Vector2(-100.8, 424.5), Vector2(-570, 255), Vector2(-133, -78),
	Vector2(-152, -88), Vector2(98.4, 96.6), Vector2(-426, 411), Vector2(-555, 498), Vector2(336, 620), Vector2(305, 640)]
const WALK_POINTS := 4
## Жители стоят у своих дверей, мосты проверяет свой тест.
const IGNORED := ["Bridge", "Villagers/"]
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func terrain_y(space: PhysicsDirectSpaceState3D, at: Vector2, terrain: Array[RID]) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 200, at.y), Vector3(at.x, -60, at.y))
	q.collision_mask = 1
	var skip: Array[RID] = []
	for i in 12:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return null
		if hit.collider.get_rid() in terrain:
			return hit.position.y
		skip.append(hit.rid)
		q.exclude = skip
	return null


## Подпись препятствия: для общего тела природы — положение формы, для остальных — имя узла.
func describe(hit: Dictionary) -> Array:
	var body: Node = hit.collider
	var label := String(body.name)
	var pos := (body as Node3D).global_position
	if body.get_parent() and label == "Collision":
		var owner_id: int = body.shape_find_owner(hit.shape)
		var cs := body.shape_owner_get_owner(owner_id) as Node3D
		return ["Природа", cs.global_position]
	# Тело коллизии — служебный узел: подпись по родителю, у правок автора — и группа Edit_<id>.
	if body.get_parent() and (label.ends_with("_col") or label.begins_with("@")):
		label = String(body.get_parent().name)
		var up := body.get_parent().get_parent()
		if up and String(up.name) != "Geometry":
			label = String(up.name) + "/" + label
	return [label, pos]


func walk(player: CharacterBody3D, target: Vector2, seconds: float) -> bool:
	var ok := false
	var stuck := 0
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
		stuck = stuck + 1 if player.global_position.distance_to(last) < 0.02 else 0
		if stuck > 60:
			break
		last = player.global_position
	for a in ["move_right", "move_left", "move_down", "move_up"]:
		Input.action_release(a)
	return ok


## Кусок ближайшей линии вокруг места: пешком от начала до конца. Возвращает пустую строку или где застрял.
func walk_spot(player: CharacterBody3D, spot: Vector2, lines: Array, space: PhysicsDirectSpaceState3D, terrain: Array[RID]) -> String:
	var best_line: Array = []
	var best_k := 0
	var best_d := INF
	for line in lines:
		var pts: Array = line["pts"]
		for k in pts.size():
			var d := spot.distance_to(Vector2(pts[k][0], pts[k][1]))
			if d < best_d:
				best_d = d
				best_line = pts
				best_k = k
	var route: Array[Vector2] = []
	for k in range(maxi(best_k - WALK_POINTS, 0), mini(best_k + WALK_POINTS + 1, best_line.size())):
		route.append(Vector2(best_line[k][0], -float(best_line[k][1])))
	var y: Variant = terrain_y(space, route[0], terrain)
	player.global_position = Vector3(route[0].x, float(y) + 0.3, route[0].y)
	for i in 20:
		await physics_frame
	for k in range(1, route.size()):
		var ok: bool = await walk(player, route[k], route[k - 1].distance_to(route[k]) / 3.5 * 2.0 + 3.0)
		if not ok:
			return "застрял у (%.1f, %.1f), шёл к (%.1f, %.1f)" % [player.global_position.x, -player.global_position.z, route[k].x, -route[k].y]
	return ""


func _run() -> void:
	root.get_node("PlayerState").reset()
	change_scene_to_file("res://scenes/levels/world.tscn")
	for i in 120:
		await process_frame
	var scene := current_scene
	var player := scene.get_node("Player") as CharacterBody3D
	var space := player.get_world_3d().direct_space_state
	var water_node := scene.get_node_or_null("DeepWater")
	var terrain: Array[RID] = []
	for n in scene.find_children("TerrainBody", "StaticBody3D", true, false):
		terrain.append(n.get_rid())
	check(terrain.size() > 0, "тела рельефа найдены: %d" % terrain.size())
	var lines = JSON.parse_string(FileAccess.get_file_as_string(ROADS_FILE))
	check(lines is Array and lines.size() > 20, "линий дорог: %d" % (lines.size() if lines is Array else 0))
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = 1
	var blocked := {}      # препятствие → [вид дороги, касаний, точка первого касания]
	var narrowed := {}     # то же для построек у самого края ленты
	var ends := {}         # постройки на последних метрах линий: не ошибка, но видно в логе
	var samples := 0
	var skipped := 0
	for line in lines:
		var half: float = line["half"]
		var lanes := int(ceil(2.0 * (half - RADIUS) / 0.8))
		var pts: Array = line["pts"]
		var total := 0.0
		for k in range(pts.size() - 1):
			total += Vector2(pts[k][0], pts[k][1]).distance_to(Vector2(pts[k + 1][0], pts[k + 1][1]))
		var walked := 0.0
		for k in range(pts.size() - 1):
			var a := Vector2(pts[k][0], -float(pts[k][1]))
			var b := Vector2(pts[k + 1][0], -float(pts[k + 1][1]))
			var seg := a.distance_to(b)
			var n := maxi(1, int(seg / STEP))
			var across := (b - a).normalized().orthogonal()
			for t in n:
				var along := walked + seg * t / n
				var near_end: bool = along < LINE_END or total - along < LINE_END
				var c := a.lerp(b, float(t) / n)
				for s in lanes + 1:
					var off := lerpf(-(half - RADIUS), half - RADIUS, float(s) / lanes)
					var at := c + across * off
					var y: Variant = terrain_y(space, at, terrain)
					if y == null:
						continue
					if water_node and water_node.surface_at(at) > float(y):
						skipped += 1
						continue
					samples += 1
					q.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, float(y) + LIFT + HEIGHT * 0.5, at.y))
					for hit in space.intersect_shape(q, 16):
						if hit.collider.get_rid() in terrain or not hit.collider is StaticBody3D:
							continue
						var info := describe(hit)
						if IGNORED.any(func(prefix: String) -> bool: return String(info[0]).begins_with(prefix)):
							continue
						var nature: bool = info[0] == "Природа"
						if not nature and near_end:
							ends[info[0]] = ends.get(info[0], 0) + 1
							continue
						# Природа — у каждого экземпляра своё положение; меши лежат в нуле, поэтому для них — ячейка касания.
						var p: Vector3 = info[1]
						var spot := Vector2(p.x, -p.z) if nature else (Vector2(at.x, -at.y) / 12.0).round() * 12.0
						var key := "%s (%.0f, %.0f)" % [info[0], spot.x, spot.y]
						var table: Dictionary = blocked if nature or absf(off) < half * MIDDLE else narrowed
						var rec: Array = table.get_or_add(key, [line["kind"], 0, Vector2(at.x, -at.y)])
						rec[1] += 1
			walked += seg
	print("проверено точек: %d, над водой пропущено: %d" % [samples, skipped])
	print("у концов линий: ", ends)
	for key in narrowed:
		print("   сужает край: %s — %s, касаний %d, точка %s" % [key, narrowed[key][0], narrowed[key][1], narrowed[key][2]])
	for key in blocked:
		print("   на дороге: %s — %s, касаний %d, точка %s" % [key, blocked[key][0], blocked[key][1], blocked[key][2]])
	check(blocked.is_empty(), "на дорогах нет препятствий (найдено %d, края сужают %d)" % [blocked.size(), narrowed.size()])
	root.get_node("PlayerState").god_mode = true
	for spot in WALK_SPOTS:
		var res: String = await walk_spot(player, spot, lines, space, terrain)
		check(res.is_empty(), "пешком через (%.0f, %.0f): %s" % [spot.x, spot.y, "прошёл" if res.is_empty() else res])
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
