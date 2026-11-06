class_name DeepWater
extends Node
## Глубокая вода мира (решение автора 2026-11-06): реку и озеро пешком по дну не перейти — на мелководье зайти можно,
## но если вода выше Рэя, он тонет. Это обычная смерть (затемнение, возрождение у фонаря, счёт смертей), утерянные
## гелиосы — на последнем сухом месте, а не на дне. Гладь воды пишет Tools/blender/build_world.py (world_water.json).

const DATA := "res://assets/levels/world_water.json"
## Глубина (м от глади до ступней), с которой Рэй тонет: рост ~1,2 м.
const DEEP := 1.0
## Сколько секунд на глубине до смерти: рывок через край омута не убивает.
const HOLD := 0.35
## Ближе этой глубины место считается сухим (сюда лягут утерянные гелиосы).
const DRY := 0.1
const SPLASH := Color(0.72, 0.86, 0.95)

var player: CharacterBody3D
var _lake := PackedVector2Array()
var _lake_z := 0.0
var _river: Array = []       # [x, z, гладь, полуширина меша воды]
var _ponds: Array = []       # [x, z, радиус, гладь]
var _under := 0.0
var _last_dry := Vector3.INF


func _ready() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if player == null or not data is Dictionary:
		set_physics_process(false)
		return
	_lake_z = data["lake_z"]
	for p in data["lake"]:
		_lake.append(Vector2(p[0], p[1]))
	_river = data["river"]
	_ponds = data["ponds"]


## Гладь воды над точкой (x, z) или NAN, если воды там нет. Границы — как у мешей воды.
func surface_at(p: Vector2) -> float:
	if Geometry2D.is_point_in_polygon(p, _lake):
		return _lake_z
	for pond in _ponds:
		if p.distance_to(Vector2(pond[0], pond[1])) <= pond[2]:
			return pond[3]
	for k in _river.size() - 1:
		var a: Array = _river[k]
		var b: Array = _river[k + 1]
		var va := Vector2(a[0], a[1])
		var v := Vector2(b[0], b[1]) - va
		var t := (p - va).dot(v) / v.length_squared()
		if (t < 0.0 and k > 0) or (t > 1.0 and k < _river.size() - 2):
			continue                      # ближе к соседнему отрезку
		if t < 0.0 or t > 1.0:
			continue                      # за концом реки меша нет
		if p.distance_to(va + v * t) <= lerpf(a[3], b[3], t):
			return lerpf(a[2], b[2], t)
	return NAN


func _physics_process(delta: float) -> void:
	# is_alive, не hp: die() сразу возвращает здоровье, и за время затемнения Рэй утонул бы ещё несколько раз.
	if player.noclip or player.input_locked or not player.is_alive():
		_under = 0.0
		return
	var pos := player.global_position
	var surface := surface_at(Vector2(pos.x, pos.z))
	var depth := surface - pos.y if not is_nan(surface) else -1.0
	if player.is_on_floor() and depth < DRY:
		_last_dry = pos
	if depth < DEEP or PlayerState.god_mode:
		_under = 0.0
		return
	_under += delta
	if _under >= HOLD:
		_under = 0.0
		CombatFX.burst(Vector3(pos.x, surface + 0.1, pos.z), SPLASH, Vector3.UP, 18, 3.0, 9.0, 0.08, 0.5)
		# Защита ослабляет урон, поэтому с запасом: вода убивает всегда, кроме бессмертия мастер-меню.
		PlayerState.damage(1000000.0, _last_dry if _last_dry.is_finite() else pos)
