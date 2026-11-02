extends SceneTree
## Тест ограничителя кадров: при vsync = выкл. в меню и в мире кадров ≤ лимита, в фоне — 15, настройка применяется.
## Запуск (в окне): godot_run.ps1 test Tools/godot/tests/fps_limit_test.gd

var fails: Array[String] = []
var _S: Node


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func measure(seconds: float) -> float:
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await create_timer(seconds).timeout
	return (Engine.get_frames_drawn() - f0) / ((Time.get_ticks_msec() - t0) / 1000.0)


func _run() -> void:
	_S = root.get_node("Settings")
	_S.set_value("vsync", false)   # VSync выключен — ограничитель обязан держать кадры сам
	_S.set_value("max_fps", 1)
	ok(Engine.max_fps == 60, "лимит 60 применён (Engine.max_fps = %d)" % Engine.max_fps)
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await create_timer(1.5).timeout
	var fps := await measure(3.0)
	ok(fps <= 66.0, "главное меню: %.0f кадров/с ≤ 66" % fps)
	_S.set_value("max_fps", 0)
	ok(Engine.max_fps == 30, "лимит 30 применяется")
	fps = await measure(2.0)
	ok(fps <= 36.0, "при лимите 30: %.0f кадров/с" % fps)
	_S.set_value("max_fps", 1)
	root.get_node("SaveGame").new_game(1, "res://scenes/levels/world.tscn")
	await create_timer(3.0).timeout
	fps = await measure(3.0)
	ok(fps <= 66.0, "в мире: %.0f кадров/с ≤ 66" % fps)
	_S._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	ok(Engine.max_fps == 15, "в фоне — 15 кадров/с")
	_S._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	ok(Engine.max_fps == 60, "после возврата — снова настройка (60)")
	_S.set_value("vsync", true)
	print("=== ОШИБОК: %d ===" % fails.size())
	quit(1 if fails.size() > 0 else 0)
