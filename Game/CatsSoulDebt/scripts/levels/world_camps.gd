extends Node3D
## Постоянные лагеря врагов мира вокруг Брода (решение автора 2026-10-29, враги — эпик боя, COMBAT_SPEC 3а):
## квалды — пост из трёх у пристани Оды; кобольды «Рыжие упыри» — стая 4 у тропы в ущелье и стая 3 на тропе через
## восточный лес (святилище — вырубка: узко, плохо видно), в засаде; голем-шахтёр — у входа в Заброшенную шахту,
## мини-босс — на площадке у старой штольни. Лагерь появляется, когда Рэй ближе SPAWN_DISTANCE: навигация вокруг
## печётся (LocalNavigation, ключ — место), враги ставятся на землю. Возрождение после смерти Рэя — DeathCycle.
## Точки — в метрах Godot (x, z), по планировке Tools/world_layout.py (места POIS и тропы ROADS).

const SPAWN_DISTANCE := 70.0
const SCRIPTS := {"kvald": "res://scripts/combat/kvald.gd", "kobold": "res://scripts/combat/kobold.gd",
	"golem": "res://scripts/combat/mine_golem.gd"}
## id лагеря → центр (x, z), место для навигации (общее с квестами), враги: [вид, смещение (x, z), свойства].
const CAMPS := {
	# Квалды — на берегу в 30 м от Оды: при 13 м к жительнице и находкам её квестов нельзя было подойти без боя.
	"pier_kvalds": {"at": Vector2(162.0, -31.0), "nav": "pier", "enemies": [
		["kvald", Vector2(-3.2, 0.0), {}], ["kvald", Vector2(-1.2, -1.6), {}], ["kvald", Vector2(-1.2, 1.6), {}]]},
	"gorge_kobolds": {"at": Vector2(-575.0, -252.0), "nav": "gorge", "enemies": [
		["kobold", Vector2(-4.0, -2.0), {"pack_id": "gorge"}], ["kobold", Vector2(4.0, 1.0), {"pack_id": "gorge"}],
		["kobold", Vector2(-2.0, 4.5), {"pack_id": "gorge"}], ["kobold", Vector2(3.0, -5.0), {"pack_id": "gorge"}]]},
	"forest_kobolds": {"at": Vector2(344.0, -504.0), "nav": "forest_road", "enemies": [
		["kobold", Vector2(-3.5, 1.0), {"pack_id": "forest_road"}], ["kobold", Vector2(3.5, -1.5), {"pack_id": "forest_road"}],
		["kobold", Vector2(0.5, 4.5), {"pack_id": "forest_road"}]]},
	"mine_golem": {"at": Vector2(-555.0, -507.0), "nav": "mine", "enemies": [["golem", Vector2.ZERO, {}]]},
	# Мини-босс — в 26 м от находки квеста у штольни (радиус обнаружения 10): бой по желанию, а не по пути за квестом.
	"adit_boss": {"at": Vector2(-559.0, -90.0), "nav": "adit", "enemies": [["golem", Vector2.ZERO, {"boss": true}]]},
}

@export var player_path: NodePath
@export var navigation_path: NodePath

var _player: Node3D
var _spawned: Dictionary = {}


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D


func _process(_delta: float) -> void:
	if _player == null:
		return
	var p := Vector2(_player.global_position.x, _player.global_position.z)
	for id in CAMPS:
		if not _spawned.has(id) and p.distance_to(CAMPS[id]["at"]) < SPAWN_DISTANCE:
			_spawn(id)


## Поставить лагерь сразу (тесты, мастер-меню).
func spawn_now(id: String) -> void:
	if not _spawned.has(id):
		_spawn(id)


func _spawn(id: String) -> void:
	_spawned[id] = true
	var camp: Dictionary = CAMPS[id]
	var at2: Vector2 = camp["at"]
	var center := _ground(Vector3(at2.x, 0, at2.y))
	var nav := get_node_or_null(navigation_path)
	if nav:
		nav.bake_around(String(camp["nav"]), center)
	var k := 0
	for e in camp["enemies"]:
		var off: Vector2 = e[1]
		var enemy := CharacterBody3D.new()
		enemy.set_script(load(SCRIPTS[e[0]]))
		enemy.name = "Camp_%s_%d" % [id, k]
		for prop in e[2]:
			enemy.set(prop, e[2][prop])
		# Позиция — до добавления: Enemy._ready запоминает её как точку появления и возрождения.
		enemy.position = _ground(Vector3(at2.x + off.x, 0, at2.y + off.y)) + Vector3(0, 0.3, 0)
		add_child(enemy)
		k += 1


## Земля под точкой: луч сверху до рельефа (TerrainBody); стволы деревьев и камни на пути пропускаются.
func _ground(at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 200, 0), at - Vector3(0, 200, 0))
	q.collision_mask = 1
	var space := get_world_3d().direct_space_state
	for i in 8:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return at
		if String((hit.collider as Node).name) == "TerrainBody":
			return hit.position + Vector3(0, 0.1, 0)
		q.exclude = q.exclude + [hit.rid]
	return at
