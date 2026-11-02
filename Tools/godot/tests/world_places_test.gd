extends SceneTree
## Места мира (scenes/levels/world.tscn): водяная мельница Ганса — колесо крутится, у двери и на мостках
## над омутом Рэй стоит на земле/настиле; хижина Клауса у реки — Рэй у двери, мостки в реку.
## Скриншоты — Арт/Скриншоты/world_place_<место>.png.
## Запуск (в окне): powershell -File Tools/godot_run.ps1 test Tools/godot/tests/world_places_test.gd

const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/world_place_%s.png"
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


## Обзорный кадр: камера отведена (offset от цели), потом возвращается к Рэю.
func overview(scene: Node, key: String, target: Vector3, offset: Vector3) -> void:
	var cam := scene.get_node("Camera3D") as Camera3D
	cam.process_mode = Node.PROCESS_MODE_DISABLED
	cam.look_at_from_position(target + offset, target)
	for i in 10:
		await process_frame
	await shot(key)
	cam.process_mode = Node.PROCESS_MODE_INHERIT


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
