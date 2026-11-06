extends SceneTree
## Места мира (scenes/levels/world.tscn): водяная мельница Ганса — колесо крутится, у двери и на мостках
## над омутом Рэй стоит на земле/настиле; хижина Клауса у реки — Рэй у двери, мостки в реку.
## Скриншоты — Арт/Скриншоты/world_place_<место>.png.
## Запуск (в окне): powershell -File Tools/godot_run.ps1 test Tools/godot/tests/world_places_test.gd

const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/world_place_%s.png"
## Предложенные места жителей (Godot x, z): запись «at» в village_quests.gd меняет чат сюжета.
const LARP_AT := Vector2(52.6, 13.6)
const AGATA_AT := Vector2(345.0, 5.2)
const AGATA_WATER := -3.31
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


## Поставить Рэя на поверхность под точкой (луч сверху) и подождать, пока камера и трава догонят.
func put(scene: Node, at: Vector3, from_height := 30.0) -> float:
	var player: Node3D = scene.get_node("Player")
	var space := (player as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, from_height, 0), at - Vector3(0, 30, 0))
	q.exclude = [player.get_rid()] if player is CollisionObject3D else []
	var hit := space.intersect_ray(q)
	var y: float = hit.position.y if hit else at.y
	player.global_position = Vector3(at.x, y + 0.3, at.z)
	(scene.get_node("Camera3D") as Node3D).global_position = player.global_position + Vector3(0, 9, 11)
	for i in 60:
		await physics_frame
	return y


## Высота земли под точкой: луч не считает жителя, если он там уже стоит (его тело выше земли на рост).
func ground_y(scene: Node, at: Vector3) -> float:
	var space := (scene.get_node("Player") as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 30, 0), at - Vector3(0, 30, 0))
	var skip: Array[RID] = []
	for i in 6:
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return at.y
		if String((hit.collider as Node).name) == "TerrainBody":
			return hit.position.y
		skip.append(hit.rid)
	return at.y


## Обзорный кадр: камера отведена (offset от цели), потом возвращается к Рэю.
func overview(scene: Node, key: String, target: Vector3, offset: Vector3) -> void:
	var cam := scene.get_node("Camera3D") as Camera3D
	cam.process_mode = Node.PROCESS_MODE_DISABLED
	cam.look_at_from_position(target + offset, target)
	for i in 10:
		await process_frame
	await shot(key)
	cam.process_mode = Node.PROCESS_MODE_INHERIT


## Дойти до точки своим ходом (как игрок): клавиши движения, без телепорта. Возвращает, дошёл ли.
func walk(player: Node3D, target: Vector3, seconds: float, near := 0.7) -> bool:
	var ok := false
	var frames := int(seconds * 60.0)
	for f in frames:
		var d := Vector2(target.x - player.global_position.x, target.z - player.global_position.z)
		if d.length() < near:
			ok = true
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


## С камеры игры до головы персонажа ничего не загораживает (лучом по постройкам).
func seen_from_camera(player: CharacterBody3D, cam: Camera3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, player.global_position + Vector3(0, 1.0, 0))
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		print("   луч с камеры упёрся в ", (hit.collider as Node).name)
	return hit.is_empty()


## Алхимический Уголок Ларпа: группа правки, коллизия; место Ларпа у двери и место Агаты у ветхого мостика
## (берег у настила: под него не встать — просвет на суше 0,9 м) — на земле, доступны пешком, видны с камеры.
func _alchemy_and_agata(scene: Node, geo: Node) -> void:
	var player := scene.get_node("Player") as CharacterBody3D
	var cam := scene.get_node("Camera3D") as Camera3D
	var e := geo.get_node_or_null("Edit_house_alchemy") as Node3D
	check(e != null, "Алхимический Уголок в мире")
	if e == null:
		return
	check(String(e.get_meta("extras", {}).get("edit_id", "")) == "house:alchemy", "Уголок — группа правки house:alchemy")
	check((e.get_node("Houses__house_alchemy") as MeshInstance3D).get_surface_override_material(0) != null, "дом одет материалами набора")
	check((e.get_node("Detail_bottles__house_alchemy") as MeshInstance3D).material_override != null, "склянки одеты шейдером мира")
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(e.global_position + Vector3(0, 8, 0), e.global_position - Vector3(0, 2, 0))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	check(not hit.is_empty() and String((hit.collider as Node).name).begins_with("Houses__house_alchemy"), "в дом не зайти (коллизия)")
	var larp := Vector3(LARP_AT.x, 0, LARP_AT.y)
	var y := await put(scene, Vector3(50.0, 0, 21.0))
	check(absf(player.global_position.y - y) < 1.0, "Рэй на дороге у Уголка (y %.1f)" % y)
	var reached := await walk(player, larp, 8.0, 1.3)      # 1,3 м: на месте уже стоит сам Ларп
	check(reached, "Рэй дошёл с дороги до места Ларпа (%.1f, %.1f)" % [LARP_AT.x, LARP_AT.y])
	for i in 60:
		await physics_frame
	check(seen_from_camera(player, cam), "место Ларпа видно с камеры")
	await shot("alchemy_game")
	await overview(scene, "alchemy", e.global_position + Vector3(0, 1.6, 2.0), Vector3(-5, 9, 16))
	# Агата: берег вплотную к настилу ветхого мостика, со стороны камеры.
	var agata := Vector3(AGATA_AT.x, 0, AGATA_AT.y)
	y = ground_y(scene, agata)
	check(y < -1.3, "место Агаты на берегу, под уровнем настила (y %.2f)" % y)
	await put(scene, agata + Vector3(0, 0, 1.2))
	check(y > AGATA_WATER + 0.2, "место Агаты сухое (%.2f над водой)" % (y - AGATA_WATER))
	for i in 180:
		await physics_frame
	check(seen_from_camera(player, cam), "место Агаты видно с камеры")
	await shot("agata_game")
	await overview(scene, "agata", agata + Vector3(0, 0.5, -1.0), Vector3(-3, 9, 14))
	await put(scene, Vector3(352.0, 0, -1.0))
	reached = await walk(player, agata, 12.0, 1.3)         # на месте уже стоит сама Агата
	check(reached, "Рэй спустился к месту Агаты пешком (стоит в %.1f, %.1f)" % [player.global_position.x, player.global_position.z])


func _run() -> void:
	change_scene_to_file("res://scenes/levels/world.tscn")
	for i in 120:
		await process_frame
	var scene := current_scene
	root.get_node("TimeOfDay").set_hour(11.0)
	var player: Node3D = scene.get_node("Player")
	var geo := scene.get_node("Geometry")
	# Мельница.
	var wheel := geo.find_child("MillWheel*", true, false) as Node3D
	check(wheel != null, "колесо мельницы в мире")
	var door_mill := geo.get_node_or_null("door-mill") as Node3D
	check(door_mill != null, "дверь мельницы (door-mill)")
	if wheel and door_mill:
		var b0 := wheel.basis
		for i in 30:
			await process_frame
		check(not wheel.basis.is_equal_approx(b0), "колесо крутится")
		var y := await put(scene, door_mill.global_position + Vector3(-1.5, 0, 0))
		check(absf(player.global_position.y - y) < 1.0 and player.global_position.y > -10.0,
			"Рэй у двери мельницы (y %.1f)" % player.global_position.y)
		await shot("mill")
		# Мостки над омутом: южнее дома, ближе к колесу.
		var deck := wheel.global_position + Vector3(-1.5, 0, 6.6)
		y = await put(scene, deck)
		check(y > wheel.global_position.y - 2.0, "мостки над омутом держат Рэя (y %.1f, ось %.1f)" % [y, wheel.global_position.y])
		await shot("mill_deck")
		# Обзор: камера дальше обычного (юго-восток, с реки) — колесо, лоток и шлюз.
		var cam := scene.get_node("Camera3D") as Camera3D
		cam.process_mode = Node.PROCESS_MODE_DISABLED
		cam.look_at_from_position(wheel.global_position + Vector3(14, 12, 20), wheel.global_position + Vector3(-3, 1, 0))
		for i in 10:
			await process_frame
		await shot("mill_wheel")
		cam.process_mode = Node.PROCESS_MODE_INHERIT
	# Хижина Клауса.
	var door_h := geo.get_node_or_null("door-hermit") as Node3D
	check(door_h != null, "дверь хижины (door-hermit)")
	if door_h:
		# В стороне от двери: у самой двери стоит Клаус (житель со своей коллизией).
		var y := await put(scene, door_h.global_position + Vector3(-3.5, 0, 2.5))
		check(absf(y - door_h.global_position.y) < 0.8, "Рэй у хижины (y %.1f / пол %.1f)" % [y, door_h.global_position.y])
		await shot("hermit")
		await overview(scene, "hermit_view", door_h.global_position + Vector3(-1.5, 1.5, -1.5), Vector3(-9, 9, 15))
	# Кузница Хорста: открытый зал, Рэй у наковальни.
	var door_s := geo.get_node_or_null("door-smithy") as Node3D
	check(door_s != null, "кузница Хорста (door-smithy)")
	if door_s:
		var y := await put(scene, door_s.global_position + Vector3(0, 0, -2.0), 1.5)     # луч — из-под крыши
		check(y < door_s.global_position.y + 0.6, "Рэй в открытом зале кузницы (y %.1f / %.1f)" % [y, door_s.global_position.y])
		await overview(scene, "smithy_view", door_s.global_position + Vector3(-1.0, 2.0, -3.0), Vector3(9, 10, 16))
	await _alchemy_and_agata(scene, geo)
	# Росток каменной ивы у святилища (Глава 1): подобрать — в сумке, отмечен «подобрано».
	var ps = root.get_node("PlayerState")
	var sprout_item := ContentDB.item(&"stone_willow_sprout")
	ps.taken.erase("world:stone_willow_sprout:ch1")
	var sprout := scene.get_node_or_null("Story_stone_willow_sprout") as Node3D
	check(sprout != null, "росток каменной ивы у святилища")
	if sprout:
		await put(scene, sprout.global_position + Vector3(0, 0, 1.2))
		var scam := scene.get_node("Camera3D") as Camera3D
		scam.process_mode = Node.PROCESS_MODE_DISABLED
		scam.look_at_from_position(sprout.global_position + Vector3(5, 8, 15), sprout.global_position + Vector3(-0.8, 2.8, -2.0))
		for i in 10:
			await process_frame
		await shot("shrine_sprout")
		scam.process_mode = Node.PROCESS_MODE_INHERIT
		var before: int = ps.count_of(sprout_item)
		sprout.call("interact")
		for i in 5:
			await process_frame
		check(ps.count_of(sprout_item) == before + 1, "росток в сумке (%d)" % ps.count_of(sprout_item))
		check(ps.is_taken("world:stone_willow_sprout:ch1"), "росток отмечен подобранным")
		ps.remove_item(sprout_item, 1)
		ps.taken.erase("world:stone_willow_sprout:ch1")
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
