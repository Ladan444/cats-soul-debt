class_name ContentDB
## Справочник содержимого по id: предметы, скиллы, души из res://data/.
## Нужен для сохранений (в файле — только id) и стартового набора.

const DIRS := {"item": "res://data/items", "skill": "res://data/skills", "soul": "res://data/souls"}

static var _cache: Dictionary = {}


static func item(id: StringName) -> ItemData:
	return _lookup("item", id) as ItemData


static func skill(id: StringName) -> SkillData:
	return _lookup("skill", id) as SkillData


static func soul(id: StringName) -> SoulData:
	return _lookup("soul", id) as SoulData


static func _lookup(kind: String, id: StringName) -> Resource:
	var key := "%s/%s" % [kind, id]
	if not _cache.has(key):
		var path := "%s/%s.tres" % [DIRS[kind], id]
		_cache[key] = load(path) if ResourceLoader.exists(path) else null
	return _cache[key]
