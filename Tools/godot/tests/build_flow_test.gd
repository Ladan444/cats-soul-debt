extends SceneTree
## Сквозной тест играбельной сборки (в окне: миникарта рисуется только с рендером):
## новая игра → Ивовый Брод у таверны → миникарта есть → переход по лестнице в Рубеж → миникарта снята
## по коллизиям → задание продвинулось → назад в Брод через ворота → мастер-меню (O): бессмертие,
## скорость ×2, сквозь стены, метки, телепорт. Скриншоты — Арт/Скриншоты/build_*.png.
## Запуск: Godot_console --resolution 1280x720 --path Game/CatsSoulDebt -s <абсолютный путь>

const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/"
var errors := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		errors += 1


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")


func wait_scene(file: String, timeout := 8.0) -> bool:
	var t := 0.0
	while t < timeout:
		await process_frame
		t += 1.0 / 60.0
		if current_scene and current_scene.scene_file_path.ends_with(file):
			await create_timer(1.0).timeout
			return true
	return false


func _run() -> void:
	var save := root.get_node("SaveGame")
	var cheats := root.get_node("Cheats")
	var quests := root.get_node("QuestState")
	var ps := root.get_node("PlayerState")
	# 1. Новая игра — таверна, выход в Брод.
	save.new_game(1, load("res://scripts/ui/main_menu.gd").GAME_SCENE)
	check(await wait_scene("tavern.tscn"), "новая игра начинается в таверне")
	check(quests.active.has("chapter1"), "задание Главы 1 начато")
	var player: Node3D = current_scene.get_node("Player")
	player.global_position = current_scene.get_node("ExitToVillage").global_position + Vector3(0, 1.0, 0)
	check(await wait_scene("world.tscn"), "дверь таверны ведёт в Брод (мир)")
	player = current_scene.get_node("Player")
	check(player.global_position.distance_to(current_scene.get_node("Geometry/door-tavern").global_position) < 3.0,
		"Рэй у двери таверны")
	var mm := current_scene.get_node_or_null("HUD/UIScaler/HUD/Minimap")
	check(mm != null and mm.get("_tex") != null, "миникарта долины загружена")
	await create_timer(1.0).timeout
	await shot("build_village")
	# 2. Переход через ворота крепости в Рубеж.
	var exit: Node3D = current_scene.get_node("ExitToRubezh")
	player.global_position = exit.global_position + Vector3(0, 1.0, 0)
	check(await wait_scene("rubezh_f1.tscn"), "ворота крепости ведут в Рубеж")
	player = current_scene.get_node("Player")
	await create_timer(1.5).timeout
	mm = current_scene.get_node_or_null("HUD/UIScaler/HUD/Minimap")
	check(mm != null and mm.get("_tex") != null, "миникарта Рубежа снята по коллизиям")
	check(current_scene.get_node_or_null("Props") != null, "в Рубеже стоят детали KayKit")
	await shot("build_rubezh")
	# 3. Мастер-меню.
	var ev := InputEventAction.new()
	ev.action = "debug_menu"
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(0.3).timeout
	check(paused, "O открывает мастер-меню и ставит игру на паузу")
	await shot("build_cheats")
	cheats.set_god(true)
	var hp: float = ps.hp
	ps.damage(30.0, player.global_position)
	check(ps.hp == hp, "бессмертие: урон не проходит")
	cheats.set_god(false)
	cheats.set_speed(2.0)
	check(is_equal_approx(Engine.time_scale, 2.0), "скорость ×2")
	cheats.set_speed(1.0)
	cheats.set_noclip(true)
	check(player.collision_mask == 0, "сквозь стены: столкновения выключены")
	cheats.set_noclip(false)
	check(player.collision_mask != 0, "сквозь стены выключено")
	quests.complete_step("chapter1")
	check(quests.step("chapter1") == 1, "«Завершить шаг» двигает задание")
	quests.reset_quest("chapter1")
	check(quests.step("chapter1") == 0, "«Сбросить» возвращает задание к началу")
	cheats.toggle()
	check(not paused, "повторное O закрывает меню")
	# 4. Назад в Брод через ворота.
	var back: Node3D = current_scene.get_node_or_null("ExitToVillage")
	check(back != null, "в Рубеже есть выход в Брод")
	if back:
		player.global_position = back.global_position + Vector3(0, 1.0, 0)
		check(await wait_scene("world.tscn"), "ворота Рубежа ведут в долину (мир)")
	# 5. Телепорт из меню.
	cheats.teleport("res://scenes/levels/crossroads.tscn")
	check(await wait_scene("crossroads.tscn"), "телепорт на Перепутье")
	cheats.teleport("res://scenes/ui/main_menu.tscn")
	check(await wait_scene("main_menu.tscn"), "телепорт в главное меню")
	print("=== ОШИБОК: %d ===" % errors)
	quit(errors)
