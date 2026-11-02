extends SceneTree
## Сюжет Главы 1 не по порядку и выбор в разговоре (ошибки, найденные проверкой кода 2026-10-22):
## 1) вещь найдена раньше, чем шаг её попросил, — шаг закрывается задним числом;
## 2) после выбора «отдать душу» граф произносит ответ (раньше он проскакивал непоказанным);
## 3) сохранение посреди финала — финал запускается снова.
## Запуск: Godot_console --headless --path Game/CatsSoulDebt -s <абсолютный путь к этому файлу>

var errors := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		errors += 1


func _run() -> void:
	var ps := root.get_node("PlayerState")
	var qs := root.get_node("QuestState")
	ps.reset()
	qs.reset()

	print("— Знамя до разговора с графом")
	qs.start("chapter1")
	ps.add_item(load("res://data/items/banner_third_company.tres"), 1)
	qs.notify("item:banner_third_company")   # подобрал на шаге 0 — событие «прошло мимо»
	check(qs.step("chapter1") == 0, "шаг 0 ждёт разговора (шаг %d)" % qs.step("chapter1"))
	qs.notify("talk:velmor")
	check(qs.step("chapter1") == 2, "после разговора шаг «принести знамя» закрыт задним числом (шаг %d)" % qs.step("chapter1"))

	print("— Шкатулка раньше поручения")
	ps.add_item(load("res://data/items/velmor_casket.tres"), 1)
	ps.collect_soul(&"soul_jorg")
	qs.notify("talk:velmor")   # знамя отдано → шаг 3 «душа» уже есть → 4
	check(qs.step("chapter1") == 4, "душа найдена раньше — шаг закрыт (шаг %d)" % qs.step("chapter1"))
	qs.notify("talk:velmor")   # → 5 «шкатулка» уже есть → 6
	check(qs.step("chapter1") == 6, "шкатулка найдена раньше — шаг закрыт (шаг %d)" % qs.step("chapter1"))

	print("— Сохранение и загрузка")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(qs.to_dict()))
	qs.reset()
	qs.from_dict(saved)
	check(qs.step("chapter1") == 6, "шаг восстановлен из сохранения (шаг %d)" % qs.step("chapter1"))

	print("— Ответ графа после выбора")
	ps.reset()
	qs.reset()
	qs.start("chapter1")
	for i in 4:
		qs.complete_step("chapter1")
	ps.collect_soul(&"soul_jorg")
	change_scene_to_file("res://scenes/levels/tavern.tscn")
	for i in 30:
		await process_frame
	var box: Node = current_scene.get_node("DialogueBox")
	var velmor: Node = current_scene.get_node("Velmor")
	var seen: Array[String] = []
	box.connect("chosen", func(_i): pass)
	velmor.talk()
	for i in 80:
		await create_timer(0.05).timeout
		if box.is_active():
			var t: String = box.get("_text").text
			if seen.is_empty() or seen[-1] != t:
				seen.append(t)
			if not box.get("_options").is_empty():
				box.call("_choose", 0)
			else:
				box.advance()
	var thanked := seen.any(func(t): return t.begins_with("Спасибо, Рэй"))
	check(thanked, "после «Отдать» граф благодарит (реплик показано: %d)" % seen.size())
	check(qs.step("chapter1") == 5, "граф дал поручение «шкатулка» (шаг %d)" % qs.step("chapter1"))

	ps.reset()
	qs.reset()
	print("=== ОШИБОК: %d ===" % errors)
	quit(errors)
