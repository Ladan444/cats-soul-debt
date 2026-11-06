class_name Waypoints
extends RefCounted
## Навигатор (как в GTA): цель — шаг отслеживаемого задания или метка, поставленная игроком на карте мира;
## маршрут прокладывается по дорогам мира (data/world_routes.json ← Tools/world_routes.py) и рисуется на миникарте
## и на карте мира. Состояние статическое (на время игры); сбрасывается вместе с миникартой при новой игре и загрузке.
## Координаты — метры мира Godot, точка (x, z) как Vector2.

const ROUTES_PATH := "res://data/world_routes.json"
const REPATH_STEP := 3.0          ## на сколько метров должен сдвинуться Рэй (или цель), чтобы пересчитать маршрут
const ARRIVE_M := 6.0             ## ближе этого — «пришли», метка задания гаснет
const MERGE_M := 6.0             ## вершины дорог ближе этого — один перекрёсток
const VIRTUAL_K := 3.0            ## условное соединение (нет ленты дороги) «стоит» в стольких раз дороже — путь держится дорог
const SHORT_M := 30.0             ## ближе этого — напрямик, дорога не нужна
const SNAP_M := 140.0             ## дальше от дороги — маршрут идёт напрямик (лес, горы)
const GAP_M := 130.0              ## конец дороги соединяется с другой дорогой не дальше этого
const JOIN_M := 150.0             ## отдельные куски дорожной сети ближе этого соединяются (концы дорог у деревни, развилки)

## Отслеживаемое задание (""): главное, если у его шага есть цель, иначе последнее начатое побочное.
static var tracked_quest: String = ""
## Метка игрока на карте мира; null — нет.
static var custom: Variant = null
## Кнопка «Цель» на миникарте: показывать ли маршрут и ромб цели (карта мира показывает их всегда).
static var nav_on: bool = true

## AStar с повышенной ценой условных соединений.
class _Net extends AStar2D:
	var virt := {}

	func _compute_cost(from_id: int, to_id: int) -> float:
		var d := get_point_position(from_id).distance_to(get_point_position(to_id))
		return d * (VIRTUAL_K if virt.has(minf(from_id, to_id) * 100000.0 + maxf(from_id, to_id)) else 1.0)


static var _graph: Dictionary = {}
static var _loaded := false
static var _route: PackedVector2Array = PackedVector2Array()
static var _route_from := Vector2(INF, INF)
static var _route_to := Vector2(INF, INF)
static var _route_key := ""


static func reset() -> void:
	tracked_quest = ""
	custom = null
	_route = PackedVector2Array()
	_route_from = Vector2(INF, INF)
	_route_to = Vector2(INF, INF)


# --- Цели ------------------------------------------------------------------------------------------

## Цели, которые нужно показать: [{kind: "quest"|"custom", at: Vector2, label: String}].
static func targets(tree: SceneTree) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var q := _quest_target(tree)
	if not q.is_empty():
		out.append(q)
	if custom != null and in_world(tree):
		out.append({"kind": "custom", "at": custom, "label": "Моя метка"})
	return out


## Цель, до которой строится маршрут: метка игрока важнее задания (игрок поставил её сам).
static func main_target(tree: SceneTree) -> Dictionary:
	if custom != null and in_world(tree) and _player_pos(tree).distance_to(custom) < ARRIVE_M:
		custom = null   # дошли до своей метки
	if custom != null and in_world(tree):
		return {"kind": "custom", "at": custom, "label": "Моя метка"}
	return _quest_target(tree)


static func quests_with_target(tree: SceneTree) -> Array[String]:
	var ids: Array[String] = []
	for id in QuestState.active:
		if not QuestState.is_done(id) and not _step_target(tree, id).is_empty():
			ids.append(id)
	return ids


## Следующее отслеживаемое задание по кругу (кнопка на карте).
static func cycle_tracked(tree: SceneTree) -> void:
	var ids := quests_with_target(tree)
	if ids.is_empty():
		return
	var current := tracked_quest if tracked_quest in ids else ids[0]
	tracked_quest = ids[(ids.find(current) + 1) % ids.size()]
	_route = PackedVector2Array()


static func _quest_target(tree: SceneTree) -> Dictionary:
	var ids := quests_with_target(tree)
	if ids.is_empty():
		return {}
	var id := tracked_quest
	if id == "" or not id in ids:
		id = "chapter1" if "chapter1" in ids else ids[ids.size() - 1]
	return _step_target(tree, id)


## Где выполняется текущий шаг задания (по событию шага); {} — цели нет или она не в этой сцене.
static func _step_target(tree: SceneTree, quest_id: String) -> Dictionary:
	var event := QuestState.waiting_for(quest_id)
	var text := QuestState.current_step_text(quest_id)
	var title := QuestState.title(quest_id)
	var label := "%s: %s" % [title, text]
	var at: Variant = null
	if event.begins_with("place:") and in_world(tree):
		var id := event.trim_prefix("place:")
		var pois: Dictionary = _data().get("pois", {})
		if id == "great_hall":
			id = "rubezh"
		if pois.has(id):
			at = _v(pois[id]["at"])
	elif event.begins_with("talk:"):
		var who := event.trim_prefix("talk:")
		for n in tree.get_nodes_in_group("npcs"):
			if String(n.get("npc_id")) == who and n is Node3D:
				at = Vector2(n.global_position.x, n.global_position.z)
				break
		if at == null and who == "velmor" and in_world(tree):
			at = _v(_data().get("pois", {}).get("tavern", {}).get("at", [0, 0]))
	elif event == "lantern_lit":
		var best := INF
		var pp := _player_pos(tree)
		for l in tree.get_nodes_in_group("soul_lanterns"):
			if l is Node3D and not l.get("lit"):
				var p := Vector2(l.global_position.x, l.global_position.z)
				if pp.distance_to(p) < best:
					best = pp.distance_to(p)
					at = p
	elif event.begins_with("item:"):
		var item := event.trim_prefix("item:")
		for n in tree.get_nodes_in_group("quest_props"):
			if String(n.get("item_id")) == item and n is Node3D:
				at = Vector2(n.global_position.x, n.global_position.z)
				break
	if at == null:
		return {}
	if _player_pos(tree).distance_to(at) < ARRIVE_M:
		return {}
	return {"kind": "quest", "at": at, "label": label, "quest": quest_id}


## Дороги и места из world_routes.json действуют только в большом мире.
static func in_world(tree: SceneTree) -> bool:
	var scene := tree.current_scene
	return scene != null and scene.scene_file_path.ends_with("world.tscn")


static func _player_pos(tree: SceneTree) -> Vector2:
	var p := tree.get_first_node_in_group("player") as Node3D
	return Vector2(p.global_position.x, p.global_position.z) if p else Vector2.ZERO


# --- Маршрут ---------------------------------------------------------------------------------------

## Маршрут от Рэя до главной цели: точки (x, z) по дорогам, начиная с позиции Рэя. Пусто — цели нет.
## Пересчитывается, когда Рэй или цель сдвинулись; иначе — кэш.
static func route(tree: SceneTree) -> PackedVector2Array:
	var t := main_target(tree) if in_world(tree) else {}
	if t.is_empty():
		_route = PackedVector2Array()
		return _route
	var from := _player_pos(tree)
	var to: Vector2 = t["at"]
	if _route.size() > 1 and from.distance_to(_route_from) < REPATH_STEP and to.distance_to(_route_to) < 0.5:
		return _route
	_route_from = from
	_route_to = to
	_route = find_route(from, to)
	return _route


## Кратчайший путь по дорогам между двумя точками мира. К дороге и от неё — кратчайшим участком до НАСТОЯЩЕЙ дороги
## (не до условных соединений — они лежат поперёк полей); этот участок и прямой путь обходят дома деревни.
static func find_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var g := _data()
	if g.is_empty() or not _loaded:
		return PackedVector2Array([from, to])
	var nodes: PackedVector2Array = _graph["nodes"]
	var astar: AStar2D = _graph["astar"]
	var a := _snap(from, true)
	var b := _snap(to, true)
	# Совсем рядом или далеко от дорог — напрямик (лес, горы).
	if from.distance_to(to) < SHORT_M or a["dist"] > SNAP_M or b["dist"] > SNAP_M:
		return _simplify(_avoid(from, to))
	var sa := _attach(astar, nodes, a)
	var sb := _attach(astar, nodes, b)
	var ids := astar.get_id_path(sa, sb)
	_detach(astar, sa, nodes.size())
	_detach(astar, sb, nodes.size())
	var road := PackedVector2Array()
	for id in ids:
		road.append(a["at"] if id == sa else (b["at"] if id == sb else nodes[id]))
	if road.size() < 2:
		return _simplify(_avoid(from, to))
	var pts := _avoid(from, road[0])
	for i in range(1, road.size()):
		pts.append(road[i])
	for p in _avoid(road[road.size() - 1], to):
		pts.append(p)
	return _simplify(pts)


## Прямой участок a→b в обход домов деревни (контуры — data/world_routes.json, «buildings»): если отрезок пересекает дом,
## идёт через его угол (или пару углов), где короче. Конец внутри контура (цель у стены, Рэй на крыльце) этот дом не считает.
static func _avoid(a: Vector2, b: Vector2, depth := 0) -> PackedVector2Array:
	var direct := PackedVector2Array([a, b])
	if depth > 4:
		return direct
	for bd in _data().get("buildings", []):
		var poly := PackedVector2Array()
		for q in bd["poly"]:
			poly.append(_v(q))
		if Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly) or not _crosses(a, b, poly):
			continue
		var best := PackedVector2Array()
		var best_len := INF
		var n := poly.size()
		for i in n:
			for k in 2:   # один угол или два соседних
				var via := PackedVector2Array([poly[i]])
				if k == 1:
					via.append(poly[(i + 1) % n])
				var ok := true
				var prev := a
				for v in via:
					if _crosses(prev, v, poly, true):
						ok = false
					prev = v
				if not ok or _crosses(prev, b, poly, true):
					continue
				var l := a.distance_to(via[0]) + prev.distance_to(b)
				if via.size() == 2:
					l += via[0].distance_to(via[1])
				if l < best_len:
					best_len = l
					best = via
		if best.is_empty():
			return direct
		var out := PackedVector2Array()
		var prev2 := a
		for v in best:
			for p in _avoid(prev2, v, depth + 1):
				out.append(p)
			prev2 = v
		for p in _avoid(prev2, b, depth + 1):
			out.append(p)
		return out
	return direct


## Пересекает ли отрезок контур; inner — касание в углах не считается (идём вдоль стены к углу).
static func _crosses(a: Vector2, b: Vector2, poly: PackedVector2Array, inner := false) -> bool:
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, p, q)
		if hit == null:
			continue
		if inner and (hit.distance_to(p) < 0.05 or hit.distance_to(q) < 0.05 or hit.distance_to(a) < 0.05 or hit.distance_to(b) < 0.05):
			continue
		return true
	return false


static func length_of(path: PackedVector2Array) -> float:
	return _length(path)


static func _length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
	return l


## Убирает дубли подряд идущих точек.
static func _simplify(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.3:
			out.append(p)
	return out


## Ближайшая точка на дорогах: {seg: индекс отрезка, at: Vector2, dist: float, a, b: индексы вершин}.
static func _snap(p: Vector2, real_only := false) -> Dictionary:
	var best := {"dist": INF}
	var segs: Array = _graph["real"] if real_only else _graph["segs"]
	for i in segs.size():
		var s: Array = segs[i]
		var pa: Vector2 = _graph["nodes"][s[0]]
		var pb: Vector2 = _graph["nodes"][s[1]]
		var q := Geometry2D.get_closest_point_to_segment(p, pa, pb)
		var d := p.distance_to(q)
		if d < best["dist"]:
			best = {"dist": d, "at": q, "a": s[0], "b": s[1]}
	return best


## Временная вершина на отрезке дороги (соединена с его концами); возвращает её id.
static func _attach(astar: AStar2D, nodes: PackedVector2Array, snap: Dictionary) -> int:
	var id := astar.get_available_point_id()
	astar.add_point(id, snap["at"])
	astar.connect_points(id, snap["a"], true)
	astar.connect_points(id, snap["b"], true)
	return id


static func _detach(astar: AStar2D, id: int, _n: int) -> void:
	if astar.has_point(id):
		astar.remove_point(id)


# --- Данные ----------------------------------------------------------------------------------------

static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _data() -> Dictionary:
	if _loaded:
		return _graph.get("data", {})
	_loaded = true
	var text := FileAccess.get_file_as_string(ROUTES_PATH)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Waypoints: нет %s (python Tools/world_routes.py)" % ROUTES_PATH)
		_graph = {}
		return {}
	_build(data)
	return data


## Граф: вершины — точки дорог (близкие склеены в перекрёстки), рёбра — звенья дорог и мосты.
static func _build(data: Dictionary) -> void:
	var g := {"nodes": [], "segs": [], "real": [], "astar": _Net.new()}
	for r in data["roads"]:
		var prev := -1
		for pt in r["points"]:
			var id := _add_node(g, _v(pt))
			if prev >= 0:
				_link(g, prev, id)
			prev = id
	for b in data["bridges"]:
		_link(g, _add_node(g, _v(b["a"])), _add_node(g, _v(b["b"])))
	# Дороги, которые касаются друг друга серединой звена (развилки), склеиваем: вершину рядом с чужим звеном
	# соединяем с его концами.
	var nodes: Array = g["nodes"]
	for i in nodes.size():
		for s in (g["segs"] as Array).duplicate():
			if s[0] == i or s[1] == i:
				continue
			var q := Geometry2D.get_closest_point_to_segment(nodes[i], nodes[s[0]], nodes[s[1]])
			if q.distance_to(nodes[i]) < MERGE_M:
				_link(g, i, s[0])
				_link(g, i, s[1])
	_join_components(g)
	_close_gaps(g)
	_graph = {"data": data, "nodes": PackedVector2Array(nodes), "segs": g["segs"], "real": g["real"], "astar": g["astar"]}


static func _add_node(g: Dictionary, p: Vector2) -> int:
	var nodes: Array = g["nodes"]
	for i in nodes.size():
		if nodes[i].distance_to(p) < MERGE_M:
			return i
	nodes.append(p)
	(g["astar"] as AStar2D).add_point(nodes.size() - 1, p)
	return nodes.size() - 1


static func _link(g: Dictionary, a: int, b: int, virtual := false) -> void:
	var astar: AStar2D = g["astar"]
	if a == b or astar.are_points_connected(a, b):
		return
	astar.connect_points(a, b, true)
	(g["segs"] as Array).append([a, b])
	if not virtual:
		(g["real"] as Array).append([a, b])
	else:
		(astar as _Net).virt[minf(a, b) * 100000.0 + maxf(a, b)] = true


## Дорожная сеть рисовалась кусками (дороги упираются в кольцо деревни, в мосты): соединяем ближайшие вершины
## разных кусков, пока есть пары ближе JOIN_M (как минимальное остовное дерево).
static func _join_components(g: Dictionary) -> void:
	var nodes: Array = g["nodes"]
	var astar: AStar2D = g["astar"]
	while true:
		var comp := {}
		var n_comp := 0
		for i in nodes.size():
			if comp.has(i):
				continue
			var stack := [i]
			comp[i] = n_comp
			while not stack.is_empty():
				var cur: int = stack.pop_back()
				for nb in astar.get_point_connections(cur):
					if not comp.has(nb):
						comp[nb] = n_comp
						stack.append(nb)
			n_comp += 1
		if n_comp <= 1:
			return
		var best := JOIN_M
		var pair := [-1, -1]
		for i in nodes.size():
			for j in range(i + 1, nodes.size()):
				if comp[i] != comp[j]:
					var d: float = nodes[i].distance_to(nodes[j])
					if d < best:
						best = d
						pair = [i, j]
		if pair[0] < 0:
			return
		_link(g, pair[0], pair[1], true)


## Концы дорог, которые упираются «в пустоту» рядом с другой дорогой (ворота деревни, кольцо, мост), соединяем с ближайшей
## вершиной, до которой по дорогам намного дольше, чем напрямик (иначе кратчайший путь делал бы огромный крюк).
static func _close_gaps(g: Dictionary) -> void:
	var nodes: Array = g["nodes"]
	var astar: AStar2D = g["astar"]
	for i in nodes.size():
		if astar.get_point_connections(i).size() != 1:
			continue
		var cands: Array = []
		for j in nodes.size():
			if j != i:
				var d: float = nodes[i].distance_to(nodes[j])
				if d < GAP_M:
					cands.append([d, j])
		cands.sort()
		for c in cands:
			var path := astar.get_id_path(i, c[1])
			var plen := 0.0
			for k in range(1, path.size()):
				plen += astar.get_point_position(path[k]).distance_to(astar.get_point_position(path[k - 1]))
			if path.is_empty() or plen > c[0] * 2.5 + 20.0:
				_link(g, i, c[1], true)
				break


## Ближайшая точка настоящей дороги (ленты на земле, без условных соединений) к точке мира; null — дорог нет.
static func nearest_road_point(p: Vector2) -> Variant:
	if _data().is_empty():
		return null
	var s := _snap(p, true)
	return s["at"] if s["dist"] < INF else null


static func distance_to_road(p: Vector2) -> float:
	if _data().is_empty():
		return INF
	return _snap(p, true)["dist"]
