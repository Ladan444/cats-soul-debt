extends SceneTree
## Тест экрана после финала (ChapterEndScreen): титры идут, Enter пропускает, «Ждите продолжения» и кнопка в меню;
## «Продолжить» распознаёт сохранение после финала. Сохранение теста — в его папке (user_files.gd), сейв игрока не трогается.
## Запуск (в окне): godot_run.ps1 test Tools/godot/tests/chapter_end_test.gd

var fails: Array[String] = []
var _SaveGame: Node
var _QuestState: Node
var CES: GDScript   # ChapterEndScreen: класс по имени в -s не виден при компиляции (автозагрузки)


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	_SaveGame = root.get_node("SaveGame")
	_QuestState = root.get_node("QuestState")
	CES = load("res://scripts/ui/chapter_end_screen.gd")
	var path: String = _SaveGame.PATH

	# 1. Распознавание сохранения.
	var steps: int = _QuestState.QUESTS["chapter1"]["steps"].size()
	_write(path, steps - 1)
	ok(not CES.save_is_finished(), "сохранение до финала — не финал")
	_write(path, steps)
	ok(CES.save_is_finished(), "сохранение после финала распознаётся")

	# 2. Экран.
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await wait(1.0)
	CES.open(self)
	await wait(0.5)
	var screen = _find_screen()
	ok(screen != null, "экран открыт")
	await wait(5.5)   # «Конец Главы 1» (≈5 с) → титры
	ok(screen._credits != null and screen._final_box == null, "идут титры")
	root.get_viewport().get_texture().get_image().save_png("C:/Temp/chapter_end_credits.png")
	var y0: float = screen._credits.position.y
	await wait(1.0)
	ok(screen._credits.position.y < y0, "титры прокручиваются вверх")
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	root.push_input(ev)
	await wait(1.6)
	ok(screen._final_box != null, "Enter пропускает титры")
	ok(screen._menu_button != null and screen._menu_button.has_focus(), "кнопка «В главное меню» в фокусе")
	root.get_viewport().get_texture().get_image().save_png("C:/Temp/chapter_end_final.png")
	screen._menu_button.pressed.emit()
	await wait(0.5)
	ok(_find_screen() == null, "кнопка закрывает экран")

	print("=== ОШИБОК: %d ===" % fails.size())
	quit(1 if fails.size() > 0 else 0)


func _write(path: String, chapter_step: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "scene": "res://scenes/levels/tavern.tscn", "quests": {"active": {"chapter1": chapter_step}}}))
	f.close()


func _find_screen() -> Node:
	for c in root.get_children():
		if c.get_script() == CES:
			return c
	return null
