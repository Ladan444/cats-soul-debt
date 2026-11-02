extends Node
## Состояние журнала Рэя (автозагрузка JournalState): открытые и прочитанные записи,
## исследованные и намеченные комнаты карт. Сохраняется вместе с игрой (SaveGame).

signal entry_unlocked(id: StringName)
signal room_explored(map_id: StringName, room_id: String)

const ENTRIES_DIR := "res://data/journal"
const MAPS_DIR := "res://data/maps"

var entries: Array[JournalEntry] = []
var maps: Array[JournalMap] = []
var unlocked: Dictionary = {}  # id -> true
var read: Dictionary = {}      # id -> true (непрочитанные помечены скрепкой)
var explored: Dictionary = {}  # "map/room" -> true
var hinted: Dictionary = {}    # "map/room" -> true


func _ready() -> void:
	entries.assign(_load_dir(ENTRIES_DIR))
	entries.sort_custom(func(a, b): return a.chapter < b.chapter or (a.chapter == b.chapter and a.order < b.order))
	maps.assign(_load_dir(MAPS_DIR))
	reset()


func reset() -> void:
	unlocked.clear()
	read.clear()
	explored.clear()
	hinted.clear()
	for e in entries:
		if e.unlocked_by_default:
			unlocked[e.id] = true
	for m in maps:
		for r in m.rooms:
			if r.get("hinted", false):
				hinted["%s/%s" % [m.id, r["id"]]] = true


func entry(id: StringName) -> JournalEntry:
	for e in entries:
		if e.id == id:
			return e
	return null


func visible_entries(section: JournalEntry.Section) -> Array[JournalEntry]:
	var result: Array[JournalEntry] = []
	for e in entries:
		if e.section == section and unlocked.has(e.id):
			result.append(e)
	return result


func unlock(id: StringName) -> void:
	if not unlocked.has(id):
		unlocked[id] = true
		entry_unlocked.emit(id)


func mark_read(id: StringName) -> void:
	read[id] = true


func is_new(id: StringName) -> bool:
	return unlocked.has(id) and not read.has(id)


func explore(map_id: StringName, room_id: String) -> void:
	var key := "%s/%s" % [map_id, room_id]
	if not explored.has(key):
		explored[key] = true
		room_explored.emit(map_id, room_id)


## Состояние комнаты: 0 — неизвестна, 1 — намечена (карандаш), 2 — исследована (чернила).
func room_state(map_id: StringName, room_id: String) -> int:
	var key := "%s/%s" % [map_id, room_id]
	if explored.has(key):
		return 2
	return 1 if hinted.has(key) else 0


func to_dict() -> Dictionary:
	return {"unlocked": unlocked.keys().map(str), "read": read.keys().map(str),
		"explored": explored.keys(), "hinted": hinted.keys()}


func from_dict(d: Dictionary) -> void:
	reset()
	for id in d.get("unlocked", []):
		unlocked[StringName(id)] = true
	for id in d.get("read", []):
		read[StringName(id)] = true
	for key in d.get("explored", []):
		explored[key] = true
	for key in d.get("hinted", []):
		hinted[key] = true


func _load_dir(dir: String) -> Array:
	var result := []
	var da := DirAccess.open(dir)
	if da == null:
		return result
	for file in da.get_files():
		# В экспортированной игре рядом с .tres лежат .remap — берём исходное имя.
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			result.append(load("%s/%s" % [dir, file]))
	return result
