extends Npc
## Духи у фонарей душ (CANON; данные — GUIDE и SPIRIT в scripts/data/village_quests.gd). Их видят только мёртвые —
## спрайт полупрозрачный (CombatFX.set_ghost).
## role = "guide": проводник-сова — у зажжённого фонаря открывает карту мира (перенос к другому фонарю).
## role = "spirit": призрак — шепчет обрывок лора, подсказывает, где ближайшая находка квеста, меняется редкими вещами.

const DATA := preload("res://scripts/data/village_quests.gd")
const DIRS := ["к востоку", "к северо-востоку", "к северу", "к северо-западу", "к западу", "к юго-западу", "к югу", "к юго-востоку"]

@export var role: String = "guide"
@export var lantern_path: NodePath

var _info: Dictionary
var _i := 0


func _ready() -> void:
	_info = DATA.GUIDE if role == "guide" else DATA.SPIRIT
	npc_id = role
	display_name = _info["name"]
	if sheet == null and ResourceLoader.exists(_info["sheet"]):
		sheet = load(_info["sheet"])
		hframes = 4
		vframes = 3
	super()
	CombatFX.set_ghost(sprite, 0.35)


func talk() -> void:
	if role == "guide":
		_talk_guide()
	else:
		_talk_spirit()


func _lantern_lit() -> bool:
	var l := get_node_or_null(lantern_path)
	return l != null and l.get("lit")


func _pick(key: String) -> String:
	var pool: Array = _info[key]
	_i += 1
	return pool[_i % pool.size()]


func _talk_guide() -> void:
	if not _lantern_lit():
		say(PackedStringArray([_pick("unlit")]))
		return
	ask(_pick("lit"), PackedStringArray(["Открыть карту", "Остаться"]), func(i):
		var map := get_tree().get_first_node_in_group("world_map")
		if i == 0 and map:
			map.open_map())


func _talk_spirit() -> void:
	ask(_pick("lore"), PackedStringArray(["Спросить о тайниках", "Меняться", "Уйти"]), _on_spirit_choice)


func _on_spirit_choice(i: int) -> void:
	if i == 0:
		say(PackedStringArray([_hint()]))
	elif i == 1:
		var scene := get_tree().current_scene
		var shop := scene.get_node_or_null("ShopScreen")
		if shop == null:
			shop = load("res://scripts/ui/shop_screen.gd").new()
			shop.name = "ShopScreen"
			scene.add_child(shop)
		shop.open("spirit")


## Ближайшая находка взятого квеста (QuestProp): направление, место и расстояние в шагах.
func _hint() -> String:
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().current_scene.find_children("QuestProp_*", "", true, false):
		if n is Node3D and n.call("can_interact"):
			var d := global_position.distance_to(n.global_position)
			if d < best_d:
				best_d = d
				best = n
	if best == null:
		return DATA.SPIRIT["no_hint"]
	var to := best.global_position - global_position
	var ang := atan2(-to.z, to.x)              # Godot −z — север
	var dir: String = DIRS[int(round(ang / (TAU / 8.0))) % 8]
	var place := _place_near(best.global_position)
	return "%s%s… шагов %d. Там ждёт то, что ищут живые." % [dir, (", у места «%s»" % place) if place != "" else "", int(best_d)]


func _place_near(at: Vector3) -> String:
	var map := get_tree().get_first_node_in_group("world_map")
	if map == null:
		return ""
	var best := ""
	var best_d := 120.0
	for p in map.get("places"):
		var d := Vector2(at.x, at.z).distance_to(p[1])
		if d < best_d:
			best_d = d
			best = p[0]
	return best
