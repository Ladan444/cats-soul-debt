extends SceneTree
## Тест сенсорного управления: касание включает экранные кнопки и прячет подписи клавиш,
## джойстик двигает Рэя, кнопка «Удар» бьёт, «Рывок» — рывок, клавиатура возвращает режим клавиш.
## Запуск — только в окне (в headless окно 100×100 и движок пересчитывает координаты касаний):
## Godot_console --resolution 1280x720 --path Game/CatsSoulDebt -s <абсолютный путь к этому файлу>

var fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e)


func drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	root.push_input(e)


func _run() -> void:
	var settings := root.get_node("Settings")
	var glyphs := root.get_node("InputGlyphs")
	var old_mode = settings.get_value("touch_controls")
	settings.set_value("touch_controls", 0)
	root.get_node("PlayerState").reset()
	change_scene_to_file("res://scenes/levels/world.tscn")
	await create_timer(3.0).timeout
	var scene := current_scene
	var player: CharacterBody3D = scene.get_node("Player")
	var controls: Control = scene.get_node("HUD/UIScaler/TouchControls")
	await process_frame
	ok(not controls.visible, "без касаний экранных кнопок нет")
	ok(glyphs.label(&"attack") != "", "подпись клавиши удара есть: %s" % glyphs.label(&"attack"))

	# Первое касание — в пустом месте справа вверху: включает режим касания.
	var xf: Transform2D = controls.get_global_transform_with_canvas()
	touch(0, xf * Vector2(controls.size.x * 0.7, controls.size.y * 0.4), true)
	touch(0, xf * Vector2(controls.size.x * 0.7, controls.size.y * 0.4), false)
	await process_frame
	await process_frame
	ok(controls.visible, "после касания появились джойстик и кнопки")
	ok(glyphs.label(&"attack") == "", "подписи клавиш спрятаны")

	print("— Джойстик")
	var start := Vector2(60, controls.size.y - 60)
	var x0 := player.global_position.x
	touch(1, xf * start, true)
	drag(1, xf * (start + Vector2(30, 0)))
	await create_timer(0.6).timeout
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	ok(v.x > 0.8, "джойстик вправо: вектор %s" % v)
	ok(player.global_position.x - x0 > 0.8, "Рэй пошёл вправо на %.2f м" % (player.global_position.x - x0))

	print("— Кнопка удара одновременно с джойстиком")
	var attack_center: Vector2 = controls.size + Vector2(-34, -40)
	touch(2, xf * attack_center, true)
	await physics_frame
	await physics_frame
	ok(player.is_attacking(), "удар касанием")
	touch(2, xf * attack_center, false)
	touch(1, xf * (start + Vector2(30, 0)), false)
	await create_timer(0.6).timeout
	ok(Input.get_vector("move_left", "move_right", "move_up", "move_down") == Vector2.ZERO, "палец убран — Рэй стоит")

	print("— Рывок")
	var energy0: float = root.get_node("PlayerState").energy
	var dash_center: Vector2 = controls.size + Vector2(-72, -24)
	touch(3, xf * dash_center, true)
	await physics_frame
	await physics_frame
	touch(3, xf * dash_center, false)
	ok(root.get_node("PlayerState").energy < energy0, "рывок касанием потратил энергию")

	print("— Возврат к клавиатуре")
	var k := InputEventKey.new()
	k.keycode = KEY_W
	k.physical_keycode = KEY_W
	k.pressed = true
	root.push_input(k)
	k = k.duplicate()
	k.pressed = false
	root.push_input(k)
	await process_frame
	await process_frame
	ok(not controls.visible, "клавиатура спрятала экранные кнопки")
	ok(glyphs.label(&"attack") != "", "подписи клавиш вернулись")

	settings.set_value("touch_controls", 1)
	await process_frame
	await process_frame
	ok(controls.visible, "настройка «Всегда» показывает кнопки и с клавиатурой")
	settings.set_value("touch_controls", old_mode)

	print("\n=== ОШИБОК: %d ===" % fails.size())
	for f in fails:
		print("FAIL ", f)
	quit(1 if fails.size() > 0 else 0)
