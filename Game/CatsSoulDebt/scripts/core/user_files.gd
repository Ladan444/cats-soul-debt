extends RefCounted
## Единственное место, решающее, где лежат файлы игрока (сохранение, настройки).
## Игра — экспортированная или запущенная из редактора — хранит их прямо в user://, как всегда.
## Автоматический запуск (тест через -s, headless, --quit-after) работает в своей папке: файлы игрока ему недоступны
## через SaveGame и Settings. Папка очищается при старте процесса — каждый тест начинает без сохранения и с настройками
## по умолчанию. Скрипт не ссылается на автозагрузки: его можно загружать и из тестов (-s), и до них.

const TEST_DIR := "user://test_sandbox/"
const _AUTOMATED_ARGS := ["-s", "--script", "--headless", "--quit-after"]

static var _sandbox_ready := false


## Путь к файлу игрока в этом запуске.
static func path(file_name: String) -> String:
	var automated := is_automated_run(OS.get_cmdline_args(), OS.has_feature("template"))
	if automated and not _sandbox_ready:
		_prepare_sandbox()
	return path_for(file_name, automated)


static func path_for(file_name: String, automated: bool) -> String:
	return (TEST_DIR if automated else "user://") + file_name


## exported — сборка игры (шаблон экспорта): там никакие аргументы не уводят сохранения в другую папку.
static func is_automated_run(args: PackedStringArray, exported: bool) -> bool:
	if exported:
		return false
	for arg in args:
		if arg in _AUTOMATED_ARGS:
			return true
	return false


static func _prepare_sandbox() -> void:
	_sandbox_ready = true
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var dir := DirAccess.open(TEST_DIR)
	if dir:
		for file_name in dir.get_files():
			dir.remove(file_name)
