extends SceneTree
## Враги Рубежа замечают Рэя и идут к нему (ошибка 2026-10-22: навигационная сетка на 0,5 м выше пола —
## солдаты переходили в погоню, но дёргались на месте). Рэй (бессмертный) встаёт в 5 м от каждого врага;
## через 3 с враг должен сдвинуться хотя бы на метр.
## Запуск: Godot_console --headless --path Game/CatsSoulDebt -s <абсолютный путь к этому файлу>

var errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps := root.get_node("PlayerState")
	ps.set("god_mode", true)
	change_scene_to_file("res://scenes/levels/rubezh_f1.tscn")
	for i in 60:
		await physics_frame
	var player: CharacterBody3D = current_scene.get_node("Player")
	var enemies := get_nodes_in_group("enemies")
	print("врагов: ", enemies.size())
	for e in enemies:
		var en := e as Node3D
		var start := en.global_position
		player.global_position = _stand_point(en) + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		await create_timer(3.0).timeout
		var moved := en.global_position.distance_to(start)
		# Квалды в строю: задние держат дистанцию броска грязи (COMBAT_SPEC 3а) — им достаточно вступить в бой.
		var holds_range := String(en.get_script().resource_path).ends_with("kvald.gd")
		var good: bool = moved > 1.0 or (holds_range and en.get("state") != "idle")
		print(("OK   " if good else "FAIL ") + "%s идёт к Рэю: сдвинулся на %.1f м (состояние %s)" % [en.name, moved, en.get("state")])
		if not good:
			errors += 1
	await _door_case(player, enemies)
	ps.set("god_mode", false)
	print("=== ОШИБОК: %d ===" % errors)
	quit(errors)


## Враг идёт за Рэем через открытую дверь (2026-10-27: сетка запечена при закрытых дверях, проём
## открывает NavigationLink3D двери). Закрытая дверь — путь в обход (или нет пути), открытая — сквозь проём,
## и солдат, поставленный у двери, переходит на сторону Рэя.
func _door_case(player: CharacterBody3D, enemies: Array) -> void:
	var door := current_scene.find_child("CtlDoor-key-barracks-armory", true, false) as Node3D
	var soldier: Node3D = null
	for e in enemies:
		if String((e as Node).get_script().resource_path).ends_with("drowned_soldier.gd"):
			soldier = e
			break
	if door == null or soldier == null:
		print("FAIL дверь или солдат не найдены")
		errors += 1
		return
	var aabb: AABB = door.get("mesh").get_aabb()
	var across := Vector3(1, 0, 0) if aabb.size.x < aabb.size.z else Vector3(0, 0, 1)
	var a := door.global_position - across * 1.8
	var b := door.global_position + across * 3.0
	var map: RID = door.get_world_3d().navigation_map
	var closed_len := _path_length(map, a, b)
	var good := closed_len > a.distance_to(b) + 5.0
	print(("OK   " if good else "FAIL ") + "закрытая дверь — пути сквозь неё нет (путь %.1f м, напрямую %.1f м)" % [closed_len, a.distance_to(b)])
	if not good:
		errors += 1
	door.call("_set_open", true, false)
	for i in 3:
		await physics_frame
	var open_len := _path_length(map, a, b)
	good = open_len < a.distance_to(b) + 1.5
	print(("OK   " if good else "FAIL ") + "открытая дверь — путь сквозь проём (%.1f м)" % open_len)
	if not good:
		errors += 1
	soldier.global_position = a + Vector3(0, 0.3, 0)
	soldier.set("spawn_position", a)
	soldier.set("velocity", Vector3.ZERO)
	player.global_position = b + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	await create_timer(4.0).timeout
	var side := (soldier.global_position - door.global_position).dot(across)
	good = side > 0.0
	print(("OK   " if good else "FAIL ") + "солдат прошёл за Рэем в открытую дверь (сторона %.1f м, состояние %s)" % [side, soldier.get("state")])
	if not good:
		errors += 1


## Длина пути по сетке; если путь не доходит до цели — бесконечность.
func _path_length(map: RID, from: Vector3, to: Vector3) -> float:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.is_empty():
		return INF
	var end := path[path.size() - 1]
	if Vector2(end.x - to.x, end.z - to.z).length() > 1.0:
		return INF
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## Точка в 5 м от врага на полу (по навигационной сетке): к югу, северу, востоку или западу —
## где сетка действительно есть (рядом бывают пропасти и стены).
func _stand_point(en: Node3D) -> Vector3:
	var map: RID = en.get_world_3d().navigation_map
	for dir in [Vector3(0, 0, 5), Vector3(0, 0, -5), Vector3(5, 0, 0), Vector3(-5, 0, 0)]:
		var want: Vector3 = en.global_position + dir
		var on_mesh := NavigationServer3D.map_get_closest_point(map, want)
		if Vector2(on_mesh.x - want.x, on_mesh.z - want.z).length() < 0.6 and absf(on_mesh.y - want.y) < 1.0:
			return Vector3(want.x, en.global_position.y, want.z)
	return en.global_position + Vector3(0, 0, 5)


