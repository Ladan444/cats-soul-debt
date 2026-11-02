extends SceneTree
## Тест Перепутья: девятая смерть → сцена Перепутья → беседа Стража (Enter листает) → пробуждение
## в Ивовом Броде у таверны: отметки обнулены, здоровье полное, фонари горят; второй визит — другая беседа.
## Запуск: Godot_console --headless --path Game/CatsSoulDebt -s <абсолютный путь к этому файлу>

var fails: Array[String] = []
var ps: Node


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func wait(s: float) -> void:
	await create_timer(s).timeout


## Ждать сцену по имени корня (Брод грузится дольше тестовой карты).
func wait_scene(scene_name: String, timeout := 10.0) -> void:
	var t := 0.0
	while t < timeout and not (current_scene and current_scene.name == scene_name):
		await wait(0.1)
		t += 0.1
	await wait(0.8)


func accept() -> void:
	for p in [true, false]:
		var e := InputEventAction.new()
		e.action = &"ui_accept"
		e.pressed = p
		root.push_input(e)


## Девятая смерть на тестовой карте; ждём Перепутья.
func die_ninth_time() -> void:
	var player: Node3D = current_scene.get_node("Player")
	ps.deaths = ps.MAX_DEATHS - 1
	ps.damage(100000, player.global_position)
	await wait(2.6)


## Подойти к Стражу и пролистать беседу. Возвращает первую реплику.
func talk() -> String:
	await wait(1.4)  # Рэй приходит в себя
	var player: CharacterBody3D = current_scene.get_node("Player")
	var guardian: Node3D = current_scene.get_node("Guardian")
	player.global_position = guardian.global_position + Vector3(0, 0, 1.8)
	await wait(0.2)
	var box: Node = current_scene.get_node("DialogueBox")  # без типа: в -s класс компилируется до автозагрузок
	ok(box.is_active(), "Страж заговорил, когда Рэй подошёл")
	ok(player.input_locked, "во время беседы Рэй стоит")
	var first: String = box.get("_text").text
	var presses := 0
	while box.is_active() and presses < 30:
		accept()
		presses += 1
		await wait(0.05)
	ok(not box.is_active(), "беседа пролистана (%d нажатий)" % presses)
	return first


func _run() -> void:
	ps = root.get_node("PlayerState")
	ps.reset()
	change_scene_to_file("res://tests/test_arena.tscn")
	await wait(0.6)
	current_scene.get_node("Combat/SoulLanternRubezh").light_up()

	print("— Первый визит")
	await die_ninth_time()
	ok(current_scene.name == "Crossroads", "после 9-й смерти — Перепутье (сцена %s)" % current_scene.name)
	var first := await talk()
	print("  первая реплика: ", first)
	ok(first.begins_with("Девять раз"), "беседа первого визита")
	await wait_scene("Tavern")
	ok(current_scene.name == "Tavern", "проснулся в таверне (сцена %s)" % current_scene.name)
	var player: Node3D = current_scene.get_node("Player")
	var start: Node3D = current_scene.get_node("Geometry/spawn-start")
	ok(player.global_position.distance_to(start.global_position) < 2.0, "у кровати: %s" % player.global_position)
	ok(ps.deaths == 0 and ps.death_marks.is_empty(), "новый спуск: отметок %d" % ps.deaths)
	ok(ps.hp == ps.max_hp, "здоровье полное")
	ok(ps.crossroads_visits == 1, "визитов на Перепутье: %d" % ps.crossroads_visits)
	ok(ps.lit_lanterns.size() == 1, "фонарь Рубежа горит и в новом спуске")

	print("— Второй визит")
	# В таверне смерти нет (хаб, без DeathCycle) — снова спускаемся в боевую локацию.
	change_scene_to_file("res://tests/test_arena.tscn")
	await wait(0.6)
	await die_ninth_time()
	ok(current_scene.name == "Crossroads", "снова Перепутье")
	first = await talk()
	ok(first.begins_with("Опять ты"), "вторая беседа другая: «%s»" % first.left(30))
	await wait_scene("Tavern")
	ok(current_scene.name == "Tavern" and ps.crossroads_visits == 2, "снова таверна, визитов %d" % ps.crossroads_visits)

	print("— Сохранение счётчика визитов")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ps.to_dict()))
	ps.reset()
	ps.from_dict(saved)
	ok(ps.crossroads_visits == 2 and ps.chapter == 1, "визиты и глава сохраняются")

	print("\n=== ОШИБОК: %d ===" % fails.size())
	for f in fails:
		print("FAIL ", f)
	ps.reset()
	quit(1 if fails.size() > 0 else 0)
