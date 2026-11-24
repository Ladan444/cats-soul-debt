extends SceneTree
## Проверка арены баланса M01: сцена собирается, манекен считает урон и возрождается,
## пульт меняет HP/урон/неуязвимость, руна доводит до смертельного удара без реальной смерти.
## Запуск: powershell -File Tools/godot_run.ps1 htest Tools/godot/tests/combat_gym_test.gd

var fails: Array[String] = []
var ps: Node
var scene: Node
var player: CharacterBody3D
var dummy
var striker
var panel


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func slider(id: String) -> HSlider:
	var s := panel.find_child(id, true, false) as HSlider
	ok(s != null, "ползунок " + id)
	return s


func _run() -> void:
	ps = root.get_node("PlayerState")
	ps.reset()
	change_scene_to_file("res://tests/combat_gym.tscn")
	await wait(0.6)
	scene = current_scene
	ok(scene != null and scene.name == "CombatGym", "арена загрузилась")
	if scene == null:
		_finish()
		return
	player = scene.get_node("Player")
	dummy = scene.get_node("Dummy")
	striker = scene.get_node("Striker")
	panel = scene.get_node("UI/UIScaler/Panel")
	ok(player != null and dummy != null and striker != null and panel != null, "узлы арены на месте")
	ok(scene.get_node_or_null("DeathCycle") == null, "на арене нет цикла смерти")

	print("— Стартовые цифры")
	ok(is_equal_approx(ps.max_hp, 100.0), "HP Рэя 100 при стартовом наборе")
	ok(is_equal_approx(ps.defense, 2.0), "защита плаща 2")
	ok(is_equal_approx(ps.damage_bonus, 10.0), "урон меча 10")
	ok(is_equal_approx(dummy.max_hp, 50.0), "HP манекена 50")
	ok(is_equal_approx(player.hurt_invulnerability, 0.7), "неуязвимость 0,7 с")
	ok(dummy.is_in_group("gym_dummy") and not dummy.is_in_group("enemies"), "манекен не в общем списке врагов")

	print("— Манекен считает урон")
	dummy.reset_dummy()
	var hp0: float = dummy.hp
	for dmg in [10.0, 10.0, 18.0]:
		dummy.take_hit({"damage": dmg, "dir": Vector3.RIGHT, "knockback": 0.0})
	ok(is_equal_approx(hp0 - dummy.hp, 38.0), "три удара комбо: 38 урона")
	ok(dummy.hits == 3, "манекен насчитал 3 попадания")
	await process_frame
	await process_frame
	ok(panel.dps_value() > 0.0, "DPS считается по попаданиям: %.1f" % panel.dps_value())
	ok(panel.burst_value() > 0.0, "пик считается: %.1f" % panel.burst_value())

	print("— Манекен умирает и возвращается")
	dummy.take_hit({"damage": 20.0, "dir": Vector3.RIGHT, "knockback": 0.0})
	ok(dummy.dead, "манекен убит")
	ok("Убит:" in String(panel.get("_ttk_label").text), "время добивания записано: " + String(panel.get("_ttk_label").text))
	await wait(1.2)
	ok(not dummy.dead and is_equal_approx(dummy.hp, 50.0), "манекен вернулся с полным HP")
	ok(dummy.hits == 0, "счётчик попаданий сброшен")

	print("— Пульт меняет цифры")
	var hp_slider := slider("PlayerHPSlider")
	hp_slider.value = 200.0
	await process_frame
	ok(is_equal_approx(ps.max_hp, 200.0) and is_equal_approx(ps.hp, 200.0), "HP Рэя 200")
	var dmg_slider := slider("PlayerDamageSlider")
	dmg_slider.value = 25.0
	await process_frame
	ok(is_equal_approx(ps.damage_bonus, 25.0), "урон Рэя 25")
	var inv_slider := slider("InvulnSlider")
	inv_slider.value = 1.2
	await process_frame
	ok(is_equal_approx(player.hurt_invulnerability, 1.2), "неуязвимость 1,2 с")
	var dummy_slider := slider("DummyHPSlider")
	dummy_slider.value = 120.0
	await process_frame
	ok(is_equal_approx(dummy.max_hp, 120.0) and is_equal_approx(dummy.hp, 120.0), "HP манекена 120")
	var enemy_slider := slider("EnemyDamageSlider")
	enemy_slider.value = 30.0
	await process_frame
	ok(is_equal_approx(striker.damage, 30.0), "урон врага 30")
	var interval_slider := slider("IntervalSlider")
	interval_slider.value = 0.5
	await process_frame
	ok(is_equal_approx(striker.interval, 0.5), "интервал 0,5 с")

	print("— Смертельный удар не убивает по-настоящему")
	hp_slider.value = 100.0
	await process_frame
	striker.auto = false
	striker.reset_run()
	for i in 4:
		player.set("_invulnerable", 0.0)
		striker.strike()
		await physics_frame
	ok(striker.hits == 4, "руна насчитала 4 удара")
	ok(ps.hp > 0.0, "Рэй не умер: %.1f HP" % ps.hp)
	ok(ps.deaths == 0, "счётчик смертей не тронут")
	ok(bool(panel.get("_lethal_shown")), "пульт показал смертельный удар")
	await wait(2.2)
	ok(striker.hits == 0 and is_equal_approx(ps.hp, ps.max_hp), "после паузы замер сброшен, HP полное")

	print("\n=== ОШИБОК: %d ===" % fails.size())
	for f in fails:
		print("FAIL ", f)
	quit(1 if fails.size() > 0 else 0)


func _finish() -> void:
	print("\n=== ОШИБОК: %d ===" % fails.size())
	quit(1)
