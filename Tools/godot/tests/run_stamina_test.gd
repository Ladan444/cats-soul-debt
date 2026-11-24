extends SceneTree
## Запас бега (player.gd): 6 с бега с полного запаса, пауза 0,6 с, восстановление 3 с;
## после полного выдоха бег возвращается, когда запас дошёл до 25 %.
## Логика чистая, без физики и ввода: зовём _update_run_fuel напрямую.
## Запуск: powershell -File Tools/godot_run.ps1 htest Tools/godot/tests/run_stamina_test.gd

var fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func frames(p, count: int, sprinting: bool) -> void:
	for i in count:
		p._update_run_fuel(1.0 / 60.0, sprinting)


func _run() -> void:
	var p = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(p)
	await process_frame
	ok(p.run_fuel == 1.0 and not p.winded, "на старте запас полный")

	# Бег: 5,9 с — ещё есть силы; 6,1 с — выдохся.
	frames(p, 354, true)
	ok(p.run_fuel > 0.0 and not p.winded, "через 5,9 с бега запас ещё есть")
	frames(p, 12, true)
	ok(p.run_fuel <= 0.0 and p.winded, "через 6,1 с бега Рэй выдохся")

	# Пауза 0,5 с — восстановление ещё не началось.
	frames(p, 30, false)
	ok(p.run_fuel <= 0.0, "пауза 0,5 с: запас ещё не пошёл")
	# Ещё 0,5 с — ~17 % запаса, но бег ещё закрыт (нужно 25 %).
	frames(p, 30, false)
	ok(p.run_fuel > 0.0 and p.run_fuel < 0.25 and p.winded, "восстановление идёт, бег ещё закрыт")
	# Ещё 0,4 с — перешли порог 25 %.
	frames(p, 24, false)
	ok(p.run_fuel >= 0.25 and not p.winded, "на 25 % запаса бег снова доступен")
	# Полное восстановление — 3 с от нуля (с 25 % — примерно 2,3 с).
	frames(p, 150, false)
	ok(p.run_fuel >= 0.99, "после восстановления запас полный (сейчас %.2f)" % p.run_fuel)

	# Бег на ходу не тратит запас в воздухе и во время удара — это решает _physics_process;
	# здесь проверяем только саму арифметику: без бега запас не падает.
	var before: float = p.run_fuel
	frames(p, 60, false)
	ok(is_equal_approx(p.run_fuel, before), "без бега запас не тратится")

	print("=== ОШИБОК: %d ===" % fails.size())
	quit(1 if fails.size() > 0 else 0)
