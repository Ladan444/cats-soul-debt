extends SceneTree
## Тест нового HUD (макет «Красивый HUD»): хотбар 8 ячеек 26×26, полосы, искры, плашка гелиосов, миникарта с кнопками
## (масштаб клавишами и кликом по кнопкам, «Цель»), клик по кругу → большая карта; в Рубеже — большая карта подземелья
## как в мире (без платного переноса в точку). Запуск (в окне): godot_run.ps1 test Tools/godot/tests/hud_test.gd

var fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func wait(s: float) -> void:
	await create_timer(s).timeout


func tap(action: String) -> void:
	for p in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = p
		root.push_input(e)


func _run() -> void:
	root.get_node("Settings").set_value("tutorial_hints", false)
	root.get_node("SaveGame").new_game(1, "res://scenes/levels/world.tscn")
	await wait(3.0)
	var hud = current_scene.find_child("HUD", true, false)
	var slots: Array = []
	for n in ["Skill0", "Skill1", "Skill2", "Skill3", "Item0", "Item1", "Item2", "Item3"]:
		slots.append(current_scene.find_child(n, true, false))
	ok(slots.all(func(s): return s != null and s.size == Vector2(26, 26)), "8 ячеек хотбара 26×26")
	ok(slots[1].position.x - slots[0].position.x == 28.0, "шаг ячеек 28 (26 + зазор 2)")
	ok(current_scene.find_child("HPBar", true, false) != null and current_scene.find_child("EnergyBar", true, false) != null, "полосы HP и энергии")
	ok(current_scene.find_child("Spark8", true, false) != null, "9 искр-отметок")
	var mm = current_scene.find_child("Minimap", true, false)
	ok(mm != null and mm.size == Vector2(100, 100), "миникарта 100×100 (кольцо с кнопками)")
	var z0: int = mm.get("_zoom_i")
	tap("minimap_zoom_in")
	await wait(0.2)
	ok(mm.get("_zoom_i") == mini(z0 + 1, 2), "клавиша «крупнее» меняет масштаб (%d → %d)" % [z0, mm.get("_zoom_i")])
	tap("minimap_zoom_out")
	await wait(0.2)
	ok(mm.get("_zoom_i") == z0, "клавиша «мельче» возвращает масштаб")
	var W: GDScript = load("res://scripts/ui/waypoints.gd")
	var nav0: bool = W.nav_on
	tap("minimap_target")
	await wait(0.2)
	ok(W.nav_on == not nav0, "«Цель» (T) переключает навигатор на миникарте")
	tap("minimap_target")
	# кнопки кликом: «+» на (240°, радиус 45) от центра кольца
	mm.call("_activate", "plus")
	ok(mm.get("_zoom_i") == mini(z0 + 1, 2), "кнопка «+» увеличивает масштаб")
	mm.call("_activate", "minus")
	# клик по кругу открывает большую карту
	mm.call("_activate", "ring")
	await wait(1.0)
	var wm = current_scene.get_node("WorldMap")
	ok(wm.call("is_open") and paused, "клик по кругу миникарты открывает карту мира, игра на паузе")
	wm.call("close_map")
	await wait(0.3)
	# Рубеж: большая карта подземелья
	root.get_node("SaveGame").new_game(1, "res://scenes/levels/rubezh_f1.tscn")
	await wait(3.5)
	current_scene.get_node("Book").call("open_map")
	await wait(1.0)
	var dm = current_scene.get_node_or_null("DungeonMap")
	ok(dm != null and dm.call("is_open") and paused, "в Рубеже карта открывается полноэкранной (DungeonMap)")
	dm.call("_select_point", Vector2(50, 50))
	ok(dm.get("_point") == null, "платного переноса в точку в подземелье нет")
	dm.call("close_map")
	await wait(0.3)
	ok(not paused, "карта закрыта, пауза снята")
	print("=== ОШИБОК: %d ===" % fails.size())
	quit(1 if fails.size() > 0 else 0)
