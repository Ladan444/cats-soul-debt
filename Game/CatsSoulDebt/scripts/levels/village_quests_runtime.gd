extends Node3D
## Жители и побочные квесты в мире вокруг Брода (данные — scripts/data/village_quests.gd):
## при запуске ставит жителей у их мест (пустышки poi-<место> из Blender; если там дом — шагает на юг до земли),
## у дома Лиары — воспоминания соседей; места квестов: находки (QuestProp), триггер «place:<место>» в радиусе,
## враги — когда квест взят и Рэй подошёл.

const DATA := preload("res://scripts/data/village_quests.gd")
const VILLAGER := preload("res://scripts/levels/villager_npc.gd")
const PROP := preload("res://scripts/levels/quest_prop.gd")
const LIARA := preload("res://scripts/levels/liara_house.gd")
const SPIRIT_NPC := preload("res://scripts/levels/spirit_npc.gd")
const ENEMIES := {"drowned": "res://scripts/combat/drowned_soldier.gd", "creature": "res://scripts/combat/lake_creature.gd"}
const PLACE_RADIUS := 14.0
const SPAWN_RADIUS := 45.0

@export var geometry_path: NodePath
@export var player_path: NodePath
## Навигация участками (local_navigation.gd): печётся вокруг места, когда там появляются враги.
@export var navigation_path: NodePath

var _geo: Node3D
var _player: Node3D
var _sites: Dictionary = {}       # место → позиция
var _spawned: Dictionary = {}     # «квест:место» → true


func _ready() -> void:
	_geo = get_node_or_null(geometry_path) as Node3D
	_player = get_node_or_null(player_path) as Node3D
	# Лучам нужна готовая физика (коллизии рельефа и домов).
	await get_tree().physics_frame
	await get_tree().physics_frame
	for id in DATA.VILLAGERS:
		var at = _free_spot(DATA.VILLAGERS[id]["poi"])
		if at == null:
			continue
		var npc: Node3D = VILLAGER.new()
		npc.name = "Villager_" + id
		npc.set("villager_id", id)
		add_child(npc)
		npc.global_position = at
	for id in DATA.MIKA:
		var spot: Vector2 = DATA.MIKA[id]["at"]
		var kid: Node3D = VILLAGER.new()
		kid.name = "Villager_" + id
		kid.set("villager_id", id)
		add_child(kid)
		kid.global_position = _ground(Vector3(spot.x, 0, spot.y))
	var liara_at = _free_spot(DATA.LIARA_POI)
	if liara_at != null:
		var house: Node3D = LIARA.new()
		house.name = "LiaraHouse"
		add_child(house)
		house.global_position = liara_at
	for qid in DATA.QUESTS:
		var q: Dictionary = DATA.QUESTS[qid]
		for step in q["steps"]:
			if String(step["event"]).begins_with("place:"):
				_site(String(step["event"]).trim_prefix("place:"))
		var k := 0
		for p in q.get("props", []):
			var base = _site(p["place"])
			if base == null:
				continue
			var prop: Node3D = PROP.new()
			prop.name = "QuestProp_%s_%d" % [qid, k]
			prop.set("quest_id", qid)
			prop.set("item_id", p.get("item", ""))
			prop.set("also", PackedStringArray(p.get("also", [])))
			prop.set("helios", p.get("helios", 0))
			prop.set("flag", p.get("flag", ""))
			prop.set("label_text", p.get("label", ""))
			prop.set("verb", p.get("prompt", "взять"))
			prop.set("lines", PackedStringArray(p.get("lines", [])))
			prop.set("persist_id", "world:quest_prop:%s:%d" % [qid, k])
			add_child(prop)
			prop.global_position = _ground(_away_from_villagers((base as Vector3) + Vector3(p.get("offset", 0.0), 0, 1.5 + k)))
			k += 1
	_place_spirits()


## Духи у фонарей душ (пустышки npc-guide-NN и spawn-spirit-NN рядом с fx-soul-lantern-NN): проводник — у каждого,
## призрак — с шансом SPIRIT.chance за загрузку и только у зажжённого фонаря.
func _place_spirits() -> void:
	if _geo == null:
		return
	for c in _geo.get_children():
		var n := String(c.name)
		var role := "guide" if n.begins_with("npc-guide-") else ("spirit" if n.begins_with("spawn-spirit-") else "")
		if role == "":
			continue
		var num := n.get_slice("-", 2)
		var lantern := get_tree().current_scene.get_node_or_null("Lanterns/SoulLantern_" + num)
		if lantern == null:
			continue
		if role == "spirit" and (not lantern.get("lit") or randf() >= float(DATA.SPIRIT["chance"])):
			continue
		place_spirit(role, num)


## Поставить духа у фонаря NN (без проверки шанса — для _place_spirits и тестов). Возвращает узел или null.
func place_spirit(role: String, num: String) -> Node3D:
	var marker := _geo.get_node_or_null(("npc-guide-" if role == "guide" else "spawn-spirit-") + num) as Node3D
	var lantern := get_tree().current_scene.get_node_or_null("Lanterns/SoulLantern_" + num)
	var node_name := ("Guide_" if role == "guide" else "Spirit_") + num
	if marker == null or lantern == null or has_node(node_name):
		return get_node_or_null(node_name) as Node3D
	var npc: Node3D = SPIRIT_NPC.new()
	npc.name = node_name
	npc.set("role", role)
	add_child(npc)
	npc.set("lantern_path", npc.get_path_to(lantern))
	npc.global_position = _ground(marker.global_position)
	return npc


## Находка не у самого жителя: иначе подсказки «говорить» и «взять» висят вместе и «Действие» срабатывает
## у одного из двух наугад (мельница, пристань, хижина). Ближе 3 м к жителю — отодвинуть от него.
func _away_from_villagers(at: Vector3) -> Vector3:
	for v in get_children():
		if not String(v.name).begins_with("Villager_"):
			continue
		var d := at - (v as Node3D).global_position
		d.y = 0.0
		if d.length() < 3.0:
			var dir := d.normalized() if d.length() > 0.1 else Vector3.RIGHT
			at = (v as Node3D).global_position + dir * 3.0
	return at


## Позиция места квеста (пустышка poi-<место>), с кэшем.
func _site(place: String):
	if not _sites.has(place):
		_sites[place] = _free_spot(place)
	return _sites[place]


## Земля рядом с пустышкой poi-<место>: если над землёй постройка — шаг на юг (к камере), пока не земля.
func _free_spot(place: String):
	var marker := _geo.get_node_or_null("poi-" + place) as Node3D if _geo else null
	if marker == null:
		push_warning("VillageQuests: нет пустышки poi-%s" % place)
		return null
	var p := marker.global_position
	for k in 40:
		var at := p + Vector3(0, 0, k * 1.0)
		var hit := _ray(at)
		if hit.is_empty():
			continue
		if hit.collider.name == "TerrainBody" or String(hit.collider.name).begins_with("Terrain"):
			return hit.position + Vector3(0, 0.1, 0 if k == 0 else 1.5)
	return _ground(p)


func _ground(at: Vector3) -> Vector3:
	var hit := _ray(at)
	return hit.position + Vector3(0, 0.1, 0) if not hit.is_empty() else at


func _ray(at: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 60, 0), at - Vector3(0, 60, 0))
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(q)


func _process(_delta: float) -> void:
	if _player == null:
		return
	var p := _player.global_position
	for place in _sites:
		var at = _sites[place]
		if at == null:
			continue
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		if d < PLACE_RADIUS:
			QuestState.notify("place:" + place)
		if d < SPAWN_RADIUS:
			_spawn_for(place, at)


## Враги квестов у места: один раз за загрузку сцены, пока квест взят и не сдан.
func _spawn_for(place: String, at: Vector3) -> void:
	for qid in DATA.QUESTS:
		var key := "%s:%s" % [qid, place]
		if _spawned.has(key) or not QuestState.active.has(qid) or QuestState.is_done(qid):
			continue
		for e in DATA.QUESTS[qid].get("enemies", []):
			if e["place"] != place:
				continue
			_spawned[key] = true
			var nav := get_node_or_null(navigation_path)
			if nav:
				nav.bake_around(place, at)
			for i in int(e["count"]):
				var enemy := CharacterBody3D.new()
				enemy.set_script(load(ENEMIES[e["kind"]]))
				enemy.name = "QuestEnemy_%s_%d" % [qid, i]
				var a := TAU * float(i) / maxf(e["count"], 1.0)
				# Позиция — до добавления в сцену: Enemy._ready запоминает её как точку появления и возрождения
				# (корень сцены в начале координат — локальная позиция совпадает с мировой).
				enemy.position = _ground(at + Vector3(cos(a) * 4.0, 0, sin(a) * 4.0 + 3.0)) + Vector3(0, 0.3, 0)
				get_tree().current_scene.add_child(enemy)
