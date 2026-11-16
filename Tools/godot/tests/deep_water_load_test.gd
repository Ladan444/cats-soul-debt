extends SceneTree
## Q12: загрузка сохранения на глубине не должна давать цепочку смертей и лишних потерь. Первый случай — путь игрока как есть:
## фонарь не зажжён, Рэй тонет, в затемнении закрывается окно, «Продолжить».
## Запуск: powershell -File Tools/godot_run.ps1 htest Tools/godot/tests/deep_water_load_test.gd

const WORLD := "res://scenes/levels/world.tscn"
const ARENA := "res://tests/test_arena.tscn"
## Берег и глубина реки в стороне от Главного моста (Godot x, z).
const BANK := Vector2(100.0, -131.0)
const RIVER_MID := Vector2(112.0, -134.5)
## Настил Главного моста (Godot x, z).
const DECK := Vector2(105.0, -163.7)
## Сколько кадров смотреть после загрузки: до исправления за это время успевали все девять смертей.
const WATCH_FRAMES := 900
## В остальных случаях хватает двух циклов «утонул — возродился».
const SHORT_FRAMES := 300
var fails := 0
var ps: Node
var save: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func ground(player: Node3D, at: Vector2) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 120, at.y), Vector3(at.x, -60, at.y))
	q.collision_mask = 1
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if hit else Vector3(at.x, 10, at.y)


## Идёт к цели, пока не дойдёт, не умрёт или не кончится время.
func walk(player: Node3D, target: Vector2, seconds: float) -> void:
	for f in int(seconds * 60.0):
		var d := target - Vector2(player.global_position.x, player.global_position.z)
		if d.length() < 1.0 or not player.is_alive():
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


func water(scene: Node, pos: Vector3) -> float:
	var s: float = scene.find_child("DeepWater", true, false).surface_at(Vector2(pos.x, pos.z))
	return s - pos.y if not is_nan(s) else -1.0


func read_save() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(save.PATH))
	return d if d is Dictionary else {}


## Загрузка сохранения, в котором Рэй стоит в точке pos; состояние — текущее в PlayerState.
func load_at(pos: Vector3) -> void:
	save.save(WORLD, pos)
	check(save.load_and_continue(), "сохранение загрузилось")
	await frames(90)


func _run() -> void:
	ps = root.get_node("PlayerState")
	save = root.get_node("SaveGame")
	ps.reset()
	change_scene_to_file(WORLD)
	await frames(120)
	var player: Node3D = current_scene.get_node("Player")
	check(player.global_position.distance_to(player.scene_start) < 1.0, "новая игра — в начале локации")

	# 1. Путь игрока: без фонаря утонул, в затемнении закрыл окно.
	ps.helios = 100
	ps.run_helios = 100
	player.global_position = ground(player, BANK) + Vector3(0, 0.3, 0)
	await frames(30)
	await walk(player, RIVER_MID, 9.0)
	await frames(30)
	check(ps.deaths == 1, "Рэй утонул (смертей %d)" % ps.deaths)
	var drowned_at: Vector3 = player.global_position
	var helios_after: int = ps.helios
	var marks_after: int = ps.death_marks.size()
	# То же уведомление, что приходит при закрытии окна: сохранение пишет PauseMenu.
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var d := read_save()
	check(not d.is_empty(), "при закрытии окна записано сохранение")
	var saved: Array = d.get("position", [])
	check(saved.size() == 3 and water(current_scene, Vector3(saved[0], saved[1], saved[2])) >= 1.0, "в нём Рэй на глубине (%s, в затемнении: %s)" % [saved, not player.is_alive()])
	check(int(d.get("player", {}).get("deaths", -1)) == 1, "и смерть уже засчитана")
	# «Продолжить».
	check(save.load_and_continue(), "«Продолжить» загружает сохранение")
	for f in WATCH_FRAMES / 30:
		await frames(30)
		if current_scene == null or current_scene.scene_file_path != WORLD:
			break
	var scene_now: String = current_scene.scene_file_path if current_scene else "—"
	print("   итог: сцена %s, смертей %d, гелиосов %d (были %d), отметок %d" % [scene_now, ps.deaths, ps.helios, helios_after, ps.death_marks.size()])
	check(scene_now == WORLD, "после загрузки Рэй в мире, не на Перепутье (%s)" % scene_now)
	check(ps.deaths == 1, "новых смертей нет (смертей %d)" % ps.deaths)
	check(ps.helios == helios_after, "гелиосы не потеряны снова (%d, было %d)" % [ps.helios, helios_after])
	check(ps.death_marks.size() == marks_after, "новых отметок смерти нет (%d)" % ps.death_marks.size())
	if scene_now != WORLD:
		print("ИТОГ: ошибок %d" % fails)
		quit(fails)
		return
	player = current_scene.get_node("Player")
	check(player.is_alive(), "Рэй жив и управляем")
	check(player.global_position.distance_to(player.scene_start) < 1.5, "без фонаря — в начале локации (%s)" % player.global_position)
	check(water(current_scene, player.global_position) < 0.0, "и не в воде")
	var piles := get_nodes_in_group("helios_pickups").filter(func(n): return n.mark_index == 0)
	check(piles.size() == 1, "кучка гелиосов на месте")
	check(save.has_save(), "сохранение не потеряно")
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	saved = read_save().get("position", [])
	check(saved.size() == 3 and water(current_scene, Vector3(saved[0], saved[1], saved[2])) < 1.0, "следующее сохранение уже не на глубине")

	# 2. После такой загрузки Рэй снова утонул: одна смерть, возрождение на суше, цепочки нет.
	player.global_position = ground(player, BANK) + Vector3(0, 0.3, 0)
	await frames(30)
	await walk(player, RIVER_MID, 9.0)
	await frames(SHORT_FRAMES)
	check(ps.deaths == 2, "снова утонул — ровно одна новая смерть (смертей %d)" % ps.deaths)
	player = current_scene.get_node("Player")
	check(player.is_alive() and water(current_scene, player.global_position) < 0.0, "и возродился на суше (%s)" % player.global_position)

	# 3. Старое сохранение: Рэй жив на глубине, смерти в сохранении нет. Ничего не теряет.
	ps.reset()
	ps.helios = 50
	ps.run_helios = 50
	await load_at(drowned_at)
	await frames(SHORT_FRAMES)
	player = current_scene.get_node("Player")
	check(ps.deaths == 0 and ps.helios == 50, "загрузка на глубине без смерти: потерь нет (смертей %d, гелиосов %d)" % [ps.deaths, ps.helios])
	check(player.global_position.distance_to(player.scene_start) < 1.5, "и Рэй в начале локации")

	# 4. Позиция в воздухе над глубиной (мост с тех пор перестроен): упал бы и утонул.
	ps.reset()
	await load_at(drowned_at + Vector3(0, 8, 0))
	await frames(SHORT_FRAMES)
	player = current_scene.get_node("Player")
	check(ps.deaths == 0 and player.global_position.distance_to(player.scene_start) < 1.5, "в воздухе над глубиной: то же (смертей %d)" % ps.deaths)

	# 5. Фонарь в этой локации: Рэй у фонаря.
	ps.reset()
	ps.light_lantern(WORLD + ":SoulLantern_00")
	await load_at(drowned_at)
	await frames(SHORT_FRAMES)
	player = current_scene.get_node("Player")
	var lantern: Node3D = current_scene.get_node("Lanterns/SoulLantern_00")
	var to_lantern: float = player.global_position.distance_to(lantern.respawn_point())
	check(ps.deaths == 0 and to_lantern < 1.5, "с фонарём — у фонаря (%.1f м, смертей %d)" % [to_lantern, ps.deaths])

	# 6. Фонарь в другой локации: переход к нему, как при обычной смерти.
	ps.reset()
	ps.light_lantern(ARENA + ":SoulLanternLake")
	save.save(WORLD, drowned_at)
	check(save.load_and_continue(), "сохранение загрузилось")
	await frames(240)
	scene_now = current_scene.scene_file_path if current_scene else "—"
	check(ps.deaths == 0 and scene_now == ARENA, "фонарь в другой локации — переход к нему (%s, смертей %d)" % [scene_now, ps.deaths])
	if scene_now == ARENA:
		lantern = current_scene.get_node("Combat/SoulLanternLake")
		to_lantern = current_scene.get_node("Player").global_position.distance_to(lantern.respawn_point())
		check(to_lantern < 1.5, "Рэй у того фонаря (%.1f м)" % to_lantern)

	# 7. Обычные сохранения остаются на месте: берег, настил над водой, мелководье.
	ps.reset()
	change_scene_to_file(WORLD)
	await frames(120)
	player = current_scene.get_node("Player")
	var deck_pos := ground(player, DECK) + Vector3(0, 0.3, 0)
	check(water(current_scene, deck_pos) < 0.0 and not is_nan(current_scene.find_child("DeepWater", true, false).surface_at(DECK)), "точка настила над водой")
	var bank_pos := ground(player, BANK) + Vector3(0, 0.3, 0)
	player.global_position = bank_pos
	await frames(30)
	var wet := -1.0
	var shallow_pos := bank_pos
	for step in 40:
		var target: Vector2 = BANK + (RIVER_MID - BANK).normalized() * (step * 0.5 + 0.5)
		await walk(player, target, 1.0)
		wet = water(current_scene, player.global_position)
		if wet > 0.3 or not player.is_alive():
			break
		shallow_pos = player.global_position
	shallow_pos = player.global_position
	check(wet > 0.3 and wet < 1.0 and player.is_alive(), "точка на мелководье (глубина %.2f)" % wet)
	for item in [["берег", bank_pos], ["настил моста", deck_pos], ["мелководье", shallow_pos]]:
		ps.reset()
		await load_at(item[1])
		await frames(120)
		player = current_scene.get_node("Player")
		var moved: float = Vector2(player.global_position.x - item[1].x, player.global_position.z - item[1].z).length()
		check(moved < 1.5 and ps.deaths == 0, "сохранение на месте «%s»: Рэй там же (сдвиг %.1f м, смертей %d)" % [item[0], moved, ps.deaths])
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
