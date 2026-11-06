extends SceneTree
## Глубокая вода мира: Рэй заходит в реку и озеро своим ходом. На мелководье жив, на глубине тонет — обычная смерть,
## возрождение и кучка гелиосов на сухом месте; с бессмертием мастер-меню не тонет.
## Запуск: powershell -File Tools/godot_run.ps1 test Tools/godot/tests/world_deep_water_test.gd

const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/world_deep_water.png"
## Берег и середина реки в стороне от Главного моста (Godot x, z).
const BANK := Vector2(100.0, -131.0)
const RIVER_MID := Vector2(112.0, -134.5)
## Берег и глубина рукава озера у моста к воротам Рубежа, рядом с мостом.
const LAKE_BANK := Vector2(-440.0, -418.0)
const LAKE_MID := Vector2(-440.0, -446.0)
var fails := 0
var ps: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func place(player: Node3D, at: Vector2) -> void:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 120, at.y), Vector3(at.x, -60, at.y))
	q.collision_mask = 1
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	player.global_position = (hit.position if hit else Vector3(at.x, 10, at.y)) + Vector3(0, 0.3, 0)
	for i in 30:
		await physics_frame


## Идёт к цели, пока не дойдёт, не умрёт или не кончится время. Возвращает, дошёл ли.
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


func _run() -> void:
	ps = root.get_node("PlayerState")
	ps.reset()
	change_scene_to_file("res://scenes/levels/world.tscn")
	for i in 120:
		await process_frame
	var scene := current_scene
	root.get_node("TimeOfDay").set_hour(11.0)
	var player := scene.get_node("Player") as CharacterBody3D
	# Без типа DeepWater: тест компилируется до автозагрузок, а скрипт узла ссылается на PlayerState.
	var deep: Node = scene.find_child("DeepWater", true, false)
	check(deep != null, "узел глубокой воды в мире")
	if deep == null:
		print("дети мира: ", scene.get_children().map(func(n): return n.name), " скрипт корня: ", scene.get_script())
		quit(1)
		return

	# Данные воды: река и озеро есть, суша — нет.
	check(not is_nan(deep.surface_at(RIVER_MID)), "середина реки — вода")
	check(not is_nan(deep.surface_at(LAKE_MID)), "рукав озера — вода")
	check(is_nan(deep.surface_at(Vector2(0.0, 0.0))), "площадь Брода — не вода")
	check(is_nan(deep.surface_at(BANK)), "берег реки — не вода")

	# Бессмертие мастер-меню: не тонет.
	ps.god_mode = true
	await place(player, BANK)
	await walk(player, RIVER_MID, 9.0)
	for i in 60:
		await physics_frame
	check(ps.deaths == 0 and ps.hp > 0.0, "с бессмертием Рэй не тонет (смертей %d)" % ps.deaths)
	ps.god_mode = false

	# Река: сверху видно, как Рэй входит; деньги, чтобы проверить кучку.
	ps.helios = 100
	ps.run_helios = 100
	await place(player, BANK)
	var dry := player.global_position
	var y_start := dry.y
	await walk(player, RIVER_MID, 9.0)
	for i in 40:
		await physics_frame
	check(ps.deaths == 1, "в реке Рэй утонул (смертей %d, стоит %s)" % [ps.deaths, player.global_position])
	check(ps.death_marks.size() == 1, "отметка смерти одна")
	if ps.death_marks.size() == 1:
		var mark: Vector3 = ps.death_marks[0]["pos"]
		var s: float = deep.surface_at(Vector2(mark.x, mark.z))
		check(is_nan(s) or mark.y > s - 0.11, "кучка гелиосов на сухом месте, не на дне (%.1f, %.1f, высота %.2f; старт %.2f)" % [mark.x, mark.z, mark.y, y_start])
	for i in 150:
		await physics_frame
	check(ps.hp > 0.0, "Рэй возродился")
	var after := player.global_position
	check(Vector2(after.x, after.z).distance_to(RIVER_MID) > 3.0 and is_nan(deep.surface_at(Vector2(after.x, after.z))), "после возрождения Рэй не в воде (%.1f, %.1f)" % [after.x, after.z])

	# Мелководье: вошёл на 2 м от кромки и стоит, не тонет.
	var deaths := int(ps.deaths)
	await place(player, BANK)
	var dir := (RIVER_MID - BANK).normalized()
	var edge := BANK
	for i in 120:
		edge += dir * 0.25
		if not is_nan(deep.surface_at(edge)):
			break
	# Заходит шагами, пока вода не станет заметной (но ещё не глубокой), и стоит там полторы секунды.
	var here := player.global_position
	var wet := -1.0
	for step in 40:
		await walk(player, edge + dir * (0.5 + step * 0.25), 1.0)
		here = player.global_position
		var s_now: float = deep.surface_at(Vector2(here.x, here.z))
		wet = s_now - here.y if not is_nan(s_now) else -1.0
		if wet > 0.3 or ps.deaths != deaths:
			break
	check(wet > 0.3 and wet < 1.0, "Рэй зашёл в воду по пояс (глубина %.2f)" % wet)
	for i in 90:
		await physics_frame
	check(ps.deaths == deaths, "на мелководье Рэй жив (смертей %d)" % ps.deaths)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT)

	# Озеро: рукав у ворот Рубежа.
	await place(player, LAKE_BANK)
	await walk(player, LAKE_MID, 12.0)
	for i in 40:
		await physics_frame
	check(ps.deaths == deaths + 1, "в озере Рэй утонул (смертей %d)" % ps.deaths)
	for i in 150:
		await physics_frame
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
