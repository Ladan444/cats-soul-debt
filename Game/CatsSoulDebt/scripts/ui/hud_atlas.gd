class_name HudAtlas
## Листы графики нового HUD (hud_atlas.png + data/hud_atlas.json из Арт/Генерации/UI/hud_v2): спрайты по имени.
## tex("slot_normal") → AtlasTexture; layout() — числа раскладки (холст 640×360).

const SHEET := preload("res://assets/ui/hud_atlas.png")
const DATA_PATH := "res://data/hud_atlas.json"

static var _data: Dictionary = {}
static var _cache: Dictionary = {}


static func _load() -> void:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))


static func layout() -> Dictionary:
	_load()
	return _data["layout"]


static func has(name: String) -> bool:
	_load()
	return _data["sprites"].has(name)


static func tex(name: String) -> AtlasTexture:
	if _cache.has(name):
		return _cache[name]
	_load()
	var r: Array = _data["sprites"][name]
	var t := AtlasTexture.new()
	t.atlas = SHEET
	t.region = Rect2(r[0], r[1], r[2], r[3])
	_cache[name] = t
	return t
