extends SceneTree
## Сохранения тестов отделены от сохранений игрока (scripts/core/user_files.gd): игра пишет туда же, где и раньше, а этот
## запуск через -s — только в свою папку; файлы игрока не меняются. Запуск: godot_run.ps1 htest Tools/godot/tests/user_files_test.gd

const UserFiles := preload("res://scripts/core/user_files.gd")

var errors := 0


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("OK   " if cond else "FAIL ") + what)
	if not cond:
		errors += 1


## Отпечаток файла игрока: содержимое и время записи. "" — файла нет.
func stamp(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	return "%s:%d" % [FileAccess.get_sha256(file_path), FileAccess.get_modified_time(file_path)]


func _run() -> void:
	var save := root.get_node("SaveGame")
	var settings := root.get_node("Settings")
	# Игра и сборка: те же пути, что и раньше, — старые сейвы находятся.
	check(UserFiles.path_for("save_0.json", false) == "user://save_0.json", "игра: сохранение по прежнему пути")
	check(UserFiles.path_for("settings.cfg", false) == "user://settings.cfg", "игра: настройки по прежнему пути")
	check(not UserFiles.is_automated_run(PackedStringArray(), false), "запуск из редактора без аргументов — как игра")
	check(not UserFiles.is_automated_run(PackedStringArray(["--path", "x", "res://scenes/levels/world.tscn"]), false), "запуск сцены вручную — как игра")
	check(not UserFiles.is_automated_run(PackedStringArray(["-s", "x.gd", "--headless"]), true), "сборку аргументы в другую папку не уводят")
	for args in [["-s", "x.gd"], ["--script", "x.gd"], ["--headless"], ["--quit-after", "120"]]:
		check(UserFiles.is_automated_run(PackedStringArray(args), false), "автоматический запуск: %s" % args[0])

	# Этот запуск: всё в своей папке.
	check(save.PATH.begins_with(UserFiles.TEST_DIR), "SaveGame.PATH в папке тестов (%s)" % save.PATH)
	check(settings.PATH.begins_with(UserFiles.TEST_DIR), "Settings.PATH в папке тестов (%s)" % settings.PATH)
	var real_paths := ["user://save_0.json", "user://save_0.json.bak", "user://save_0.json.tmp", "user://settings.cfg"]
	var before := real_paths.map(stamp)
	check(not save.has_save(), "тест начинает без сохранения: папка очищена")

	# Запись через игровые функции, дважды, чтобы задействовать и .bak.
	var ps := root.get_node("PlayerState")
	ps.reset()
	ps.add_helios(7)
	save.save("res://scenes/levels/world.tscn", Vector3(1, 2, 3))
	ps.add_helios(5)
	save.save("res://scenes/levels/world.tscn", Vector3(4, 5, 6))
	settings.set_value("tutorial_hints", false)
	settings.save_settings()
	check(FileAccess.file_exists(UserFiles.TEST_DIR + "save_0.json"), "сохранение записано в папку тестов")
	check(FileAccess.file_exists(UserFiles.TEST_DIR + "save_0.json.bak"), "и копия .bak там же")
	check(FileAccess.file_exists(UserFiles.TEST_DIR + "settings.cfg"), "настройки записаны в папку тестов")
	check(real_paths.map(stamp) == before, "файлы игрока не изменились и новых не появилось")

	# Загрузка читает ту же папку.
	ps.reset()
	check(save.load_and_continue(), "сохранение загружается из папки тестов")
	for i in 30:
		await process_frame
	check(ps.helios == 12, "гелиосы из сохранения теста (%d)" % ps.helios)
	check(real_paths.map(stamp) == before, "после загрузки файлы игрока те же")

	# Ни один тест не обращается к файлам игрока напрямую, мимо SaveGame и Settings.
	var dir_path := ProjectSettings.globalize_path("res://").path_join("../../Tools/godot/tests").simplify_path()
	var names := DirAccess.get_files_at(dir_path)
	check(names.size() > 10, "тесты найдены (%d)" % names.size())
	var direct := []
	var forbidden := ["user:" + "//save", "user:" + "//settings"]
	for file_name in names:
		if not file_name.ends_with(".gd") or file_name == "user_files_test.gd":   # этот тест только сверяет отпечатки
			continue
		var text := FileAccess.get_file_as_string(dir_path.path_join(file_name))
		for pattern in forbidden:
			if pattern in text:
				direct.append(file_name)
	check(direct.is_empty(), "тесты не пишут в файлы игрока напрямую %s" % str(direct))
	print("=== ОШИБОК: %d ===" % errors)
	quit(errors)
