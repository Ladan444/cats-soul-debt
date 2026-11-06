extends Node
## Сохранение в один слот (автозагрузка SaveGame): user://save_0.json.
## Пока хранит PlayerState, сцену и позицию игрока. Список слотов («Загрузить») — позже.

const PATH := "user://save_0.json"

## Позиция, которую игрок должен занять после загрузки сцены (читает player.gd).
var pending_position: Variant = null


func has_save() -> bool:
	return FileAccess.file_exists(PATH)


func save(scene_path: String, player_position: Vector3) -> void:
	# Девятая смерть, а Перепутье ещё не загрузилось (сохранили в затемнении — выход в меню, закрытие окна):
	# сохраняем уже Перепутье, иначе после загрузки Рэй получал лишнюю жизнь в той же локации.
	var position: Array = [player_position.x, player_position.y, player_position.z]
	if PlayerState.deaths >= PlayerState.MAX_DEATHS and not scene_path.ends_with("crossroads.tscn"):
		scene_path = "res://scenes/levels/crossroads.tscn"
		position = []
	var data := {
		"version": 1,
		"scene": scene_path,
		"position": position,
		"player": PlayerState.to_dict(),
		"journal": JournalState.to_dict(),
		"quests": QuestState.to_dict(),
		"time_of_day": TimeOfDay.to_dict(),
		"saved_at": Time.get_datetime_string_from_system(),
	}
	# Сначала во временный файл, потом подмена: оборванная запись (сбой, выключение) не портит единственный слот;
	# прежнее сохранение остаётся в .bak.
	var f := FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open("user://")
	if FileAccess.file_exists(PATH):
		if FileAccess.file_exists(PATH + ".bak"):
			dir.remove(PATH.get_file() + ".bak")
		dir.rename(PATH.get_file(), PATH.get_file() + ".bak")
	dir.rename(PATH.get_file() + ".tmp", PATH.get_file())


## Загружает сохранение и переходит в сохранённую сцену. false — если сохранения нет или оно повреждено.
func load_and_continue() -> bool:
	if not has_save():
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY and FileAccess.file_exists(PATH + ".bak"):
		data = JSON.parse_string(FileAccess.get_file_as_string(PATH + ".bak"))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	# Сцены из сохранения может уже не быть (переименовали) — тогда не трогаем текущее состояние.
	var scene_path: String = data.get("scene", "res://scenes/levels/world.tscn")
	if not ResourceLoader.exists(scene_path):
		scene_path = "res://scenes/levels/world.tscn"
	Minimap.clear_cache()
	Cheats.reset_modes()   # чит-режимы мастер-меню (бессмертие, скорость, время) не переживают загрузку
	PlayerState.from_dict(data.get("player", {}))
	JournalState.from_dict(data.get("journal", {}))
	QuestState.from_dict(data.get("quests", {}))
	TimeOfDay.from_dict(data.get("time_of_day", {}))
	var p: Array = data.get("position", [])
	pending_position = Vector3(p[0], p[1], p[2]) if p.size() == 3 else null
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)
	return true


## Новая игра: чистое состояние, выбранная сложность, стартовая сцена.
func new_game(difficulty: int, scene_path: String) -> void:
	PlayerState.reset()
	JournalState.reset()
	QuestState.reset()
	QuestState.start("chapter1")
	TimeOfDay.day = 0
	TimeOfDay.set_hour(TimeOfDay.START_HOUR)
	# Отладочные режимы мастер-меню в новую игру не переносятся.
	Cheats.reset_modes()
	Minimap.clear_cache()
	Settings.set_value("difficulty", difficulty)
	Settings.save_settings()
	pending_position = null
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)
