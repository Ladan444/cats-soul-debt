extends SceneTree
## Тест подсказок обучения (TutorialHints): новая игра → таверна → «Идти» → после шага запоминается;
## выключатель в настройках; повторно не показывается; сохранение помнит.
## Запуск (в окне): godot_run.ps1 test Tools/godot/tests/tutorial_test.gd

var fails: Array[String] = []
# Автозагрузки в -s не видны при компиляции — берём из дерева.
var _Settings: Node
var _SaveGame: Node
var _PlayerState: Node
var _InputGlyphs: Node


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func wait(s: float) -> void:
	await create_timer(s).timeout


func hints() -> Control:
	return current_scene.find_child("TutorialHints", true, false) as Control


func _run() -> void:
	_Settings = root.get_node("Settings")
	_SaveGame = root.get_node("SaveGame")
	_PlayerState = root.get_node("PlayerState")
	_InputGlyphs = root.get_node("InputGlyphs")
	_Settings.set_value("tutorial_hints", true)
	_SaveGame.new_game(1, "res://scenes/levels/tavern.tscn")
	await wait(1.0)
	var h = hints()
	ok(h != null, "узел TutorialHints в HUD")
	if h == null:
		quit(1)
		return
	await wait(1.5)
	ok(h._current == "move", "в таверне первой всплывает подсказка «Идти» (сейчас: %s)" % h._current)
	ok(h._plank.visible and h._row.get_child_count() >= 2, "плашка видна, в ней текст и картинки клавиш")
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("C:/Temp/tutorial_move.png")
	# Игрок пошёл — подсказка гаснет и запоминается.
	Input.action_press("move_right")
	await wait(1.6)
	Input.action_release("move_right")
	await wait(0.6)
	ok(_PlayerState.is_taken("hint:move"), "после шага подсказка «Идти» запомнена")
	ok(h._current == "", "плашка погасла")
	# Выключатель.
	_PlayerState.taken.erase("hint:move")
	_Settings.set_value("tutorial_hints", false)
	_SaveGame.new_game(1, "res://scenes/levels/tavern.tscn")
	await wait(3.5)
	h = hints()
	ok(h != null and h._current == "", "при выключенных подсказках ничего не показывается")
	# Геймпад: текст про стик.
	_Settings.set_value("tutorial_hints", true)
	_InputGlyphs.gamepad = true
	h._build("move")
	ok(h._row.get_child_count() >= 2, "подсказка на геймпаде собирается")
	_InputGlyphs.gamepad = false
	# Сохраняется вместе с игрой: ключ в _PlayerState.taken.
	_PlayerState.take("hint:run")
	ok(_PlayerState.to_dict()["taken"].has("hint:run"), "показанные подсказки уходят в сохранение")
	_Settings.set_value("tutorial_hints", true)
	print("=== ОШИБОК: %d ===" % fails.size())
	quit(1 if fails.size() > 0 else 0)
