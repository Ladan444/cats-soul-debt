class_name Minimap
extends Control
## Миникарта в правом верхнем углу HUD (решение автора: рисованная, круглая): пиксельная карта локации
## вид сверху, север вверху (как смотрит камера), стрелка Рэя, метки — фонари душ, переходы,
## жители и торговля, враги. Размеры — в UI-пикселях (родитель — UIScaler).
##
## Откуда карта: у сцены метаданные «minimap» {texture, origin (x, z мира у левого верхнего пикселя),
## mpp (метров на пиксель), zoom, reveal} — так у мира (картинку — вид сверху — пишет build_world.py).
## Иначе карта снимается при загрузке лучами сверху по коллизиям мира (Рубеж, тестовая карта):
## стены, пол, пропасти, двери. С reveal = true открывается по мере того, как Рэй ходит (подземелья).

const RADIUS := 34
const RING := preload("res://assets/ui/minimap_ring.png")
const BAKE_MPP := 0.5
const BAKE_BUDGET_USEC := 3000   ## сколько микросекунд кадра отдаём съёмке карты
const REVEAL_RADIUS_M := 9.0
const COL_FOG := Color(0.06, 0.05, 0.06, 1.0)
const MARK_COLORS := {"npc": Color("f2b450"), "trade": Color("3cd070"), "sleep": Color("6090ff"),
	"exit": Color("f4f2ec"), "lantern": Color("8fe8e0"), "lantern_off": Color("6a6a70"), "enemy": Color("e05040"),
	"quest": Color("ffd24a"), "custom": Color("6fb4ff")}

## Снятые карты и открытые области — на время игры (по пути сцены).
static var _cache: Dictionary = {}


## Новая игра или загрузка: открытые области прошлой игры не переносятся.
static func clear_cache() -> void:
	_cache.clear()
	Waypoints.reset()

var _tex: Texture2D
var _origin := Vector2.ZERO
var _mpp := 1.0
var _zoom := 1.0
var _reveal := false
var _fog_img: Image
var _fog_tex: ImageTexture
var _player: Node3D
var _scene_path := ""
var _view: Control
var _reveal_timer := 0.0


func _ready() -> void:
	# Кольцо больше окна: отступ окна от края картинки кольца считается по его размеру.
	var pad := (RING.get_width() - RADIUS * 2) / 2
	custom_minimum_size = Vector2(RING.get_size())
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Круглое окно: маска рисует круг, вид карты обрезается по нему.
	var mask := _Mask.new()
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mask.position = Vector2(pad, pad)
	mask.size = Vector2(RADIUS * 2, RADIUS * 2)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mask)
	_view = Control.new()
	_view.size = mask.size
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.draw.connect(_draw_view)
	mask.add_child(_view)
	var ring := TextureRect.new()
	ring.texture = RING
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)
	_setup.call_deferred()


class _Mask extends Control:
	func _draw() -> void:
		draw_circle(size / 2.0, size.x / 2.0, Color.WHITE)


func _setup() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_scene_path = scene.scene_file_path
	_player = scene.get_node_or_null("Player") as Node3D
	var meta: Dictionary = scene.get_meta("minimap", {})
	if meta.has("texture"):
		_tex = load(meta["texture"])
		_origin = meta.get("origin", Vector2.ZERO)
		_mpp = meta.get("mpp", 1.0)
		_zoom = meta.get("zoom", 1.0)
		_reveal = meta.get("reveal", false)
	else:
		# Подземелья: снимок по коллизиям (после первого кадра физики) частями за несколько кадров,
		# открывается по мере хода.
		_zoom = meta.get("zoom", 1.6)
		_reveal = meta.get("reveal", true)
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not is_inside_tree():
			return   # сцену сменили за эти два кадра
		await _bake(scene)
		if not is_inside_tree():
			return
	_init_fog()


## Туман поверх карты (только для открываемых по ходу): создаётся до первых снятых строк,
## чтобы недоснятая карта не светилась целиком.
func _init_fog() -> void:
	if not _reveal or _tex == null or _fog_tex != null:
		return
	var key := _scene_path + ":fog"
	if _cache.has(key):
		_fog_img = _cache[key]
	else:
		_fog_img = Image.create(_tex.get_width(), _tex.get_height(), false, Image.FORMAT_RGBA8)
		_fog_img.fill(COL_FOG)
		_cache[key] = _fog_img
	_fog_tex = ImageTexture.create_from_image(_fog_img)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _tex == null:
		return
	if _reveal:
		_reveal_timer -= delta
		if _reveal_timer <= 0.0:
			_reveal_timer = 0.2
			_reveal_around(_player.global_position)
	_view.queue_redraw()


func _world_to_px(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - _origin) / _mpp


func _draw_view() -> void:
	if _tex == null or _player == null or not is_instance_valid(_player):
		return
	var scale := _zoom * _mpp           # UI-пикселей на пиксель карты
	var center := _world_to_px(_player.global_position)
	var half := _view.size / 2.0 / scale
	var src := Rect2(center - half, half * 2.0)
	_view.draw_rect(Rect2(Vector2.ZERO, _view.size), COL_FOG)
	_view.draw_texture_rect_region(_tex, Rect2(Vector2.ZERO, _view.size), src)
	if _fog_tex:
		_view.draw_texture_rect_region(_fog_tex, Rect2(Vector2.ZERO, _view.size), src)
	var pp := _player.global_position
	var mid := _view.size / 2.0
	var tree := get_tree()
	_draw_route(pp, mid)
	for t in Waypoints.targets(tree):
		_mark(Vector3(t["at"].x, pp.y, t["at"].y), pp, mid, t["kind"], 2, true)
	for n in tree.get_nodes_in_group("enemies"):
		if n.visible and n.has_method("is_alive") and n.is_alive():
			_mark(n.global_position, pp, mid, "enemy", 1)
	for n in tree.get_nodes_in_group("soul_lanterns"):
		_mark(n.global_position, pp, mid, "lantern" if n.get("lit") else "lantern_off", 2)
	for n in tree.get_nodes_in_group("level_exits"):
		_mark(n.global_position, pp, mid, "exit", 2, true)
	for n in tree.get_nodes_in_group("level_markers"):
		var kind: String = n.get("kind")
		if kind in ["npc", "trade", "sleep"]:
			_mark(n.global_position, pp, mid, kind, 2)
	# Стрелка Рэя — по направлению взгляда.
	var f: Vector3 = _player.get("_facing") if _player.get("_facing") != null else Vector3.BACK
	var dir := Vector2(f.x, f.z).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var side := Vector2(-dir.y, dir.x)
	var tip := mid + dir * 4.0
	var pts := PackedVector2Array([tip, mid - dir * 3.0 + side * 3.0, mid - dir * 1.5, mid - dir * 3.0 - side * 3.0])
	_view.draw_colored_polygon(pts, Color("1e1614"))
	var inner := PackedVector2Array([mid + dir * 3.0, mid - dir * 2.0 + side * 2.0, mid - dir * 1.0, mid - dir * 2.0 - side * 2.0])
	_view.draw_colored_polygon(inner, Color("f4f2ec"))


## Маршрут навигатора (только в большом мире, где есть дороги): тёмная подложка и золотой пунктир.
func _draw_route(pp: Vector3, mid: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.scene_file_path.ends_with("world.tscn"):
		return
	var pts := Waypoints.route(get_tree())
	if pts.size() < 2:
		return
	var v := PackedVector2Array()
	for p in pts:
		v.append((mid + (p - Vector2(pp.x, pp.z)) * _zoom).round())
	_view.draw_polyline(v, Color("1e1614"), 3.0)
	for i in range(1, v.size()):
		var a := v[i - 1]
		var b := v[i]
		var len := a.distance_to(b)
		var dir := (b - a) / maxf(len, 0.001)
		var d := 0.0
		while d < len:
			_view.draw_line(a + dir * d, a + dir * minf(d + 3.0, len), MARK_COLORS["quest"], 1.0)
			d += 5.0


func _mark(world: Vector3, player_pos: Vector3, mid: Vector2, kind: String, r: int, diamond := false) -> void:
	var d := Vector2(world.x - player_pos.x, world.z - player_pos.z) * _zoom
	if d.length() > RADIUS - 2:
		if kind not in ["exit", "quest", "custom"]:
			return
		d = d.normalized() * (RADIUS - 3)   # переходы и цели навигатора видны всегда — прижаты к краю
	if _reveal and _fog_img and kind not in ["exit", "quest", "custom"]:
		var px := _world_to_px(world)
		if px.x < 0 or px.y < 0 or px.x >= _fog_img.get_width() or px.y >= _fog_img.get_height():
			return
		if _fog_img.get_pixelv(Vector2i(px)).a > 0.5:
			return
	var p := (mid + d).floor()
	var col: Color = MARK_COLORS.get(kind, Color.WHITE)
	if diamond:
		_view.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r - 1), p + Vector2(r + 1, 0),
			p + Vector2(0, r + 1), p + Vector2(-r - 1, 0)]), Color("1e1614"))
		_view.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r),
			p + Vector2(-r, 0)]), col)
	else:
		_view.draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)).grow(1), Color("1e1614"))
		_view.draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), col)


func _reveal_around(pos: Vector3) -> void:
	var c := _world_to_px(pos)
	var r := REVEAL_RADIUS_M / _mpp
	var w := _fog_img.get_width()
	var h := _fog_img.get_height()
	var changed := false
	for y in range(maxi(0, int(c.y - r)), mini(h, int(c.y + r) + 1)):
		for x in range(maxi(0, int(c.x - r)), mini(w, int(c.x + r) + 1)):
			if Vector2(x, y).distance_to(c) <= r and _fog_img.get_pixel(x, y).a > 0.0:
				_fog_img.set_pixel(x, y, Color(0, 0, 0, 0))
				changed = true
	if changed:
		_fog_tex.update(_fog_img)


## Снимок локации лучами сверху вниз по коллизиям мира (слой 1): стены, пол, пропасти, двери.
func _bake(scene: Node) -> void:
	if _cache.has(_scene_path):
		var c: Dictionary = _cache[_scene_path]
		_tex = c["tex"]
		_origin = c["origin"]
		_mpp = BAKE_MPP
		return
	var box := AABB()
	var first := true
	for vi in scene.find_children("*", "VisualInstance3D", true, false):
		if not (vi is MeshInstance3D) or not vi.is_visible_in_tree():
			continue
		var b: AABB = vi.global_transform * vi.get_aabb()
		if b.size.length() > 600.0:
			continue
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var w := mini(int(box.size.x / BAKE_MPP) + 1, 600)
	var h := mini(int(box.size.z / BAKE_MPP) + 1, 600)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(COL_FOG)
	var tex := ImageTexture.create_from_image(img)
	_tex = tex
	_origin = Vector2(box.position.x, box.position.z)
	_mpp = BAKE_MPP
	_init_fog()
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var top := box.end.y + 2.0
	var bottom := box.position.y - 2.0
	var floor_y := _player.global_position.y if _player else 0.0
	# Строки снимаются по кадрам, начиная с той, где стоит Рэй, и дальше в обе стороны.
	var start_row := 0
	if _player:
		start_row = clampi(int((_player.global_position.z - box.position.z) / BAKE_MPP), 0, h - 1)
	var rows: Array[int] = []
	for d in h:
		if start_row + d < h:
			rows.append(start_row + d)
		if d > 0 and start_row - d >= 0:
			rows.append(start_row - d)
	var t0 := Time.get_ticks_usec()
	for y in rows:
		for x in w:
			var wx := box.position.x + (x + 0.5) * BAKE_MPP
			var wz := box.position.z + (y + 0.5) * BAKE_MPP
			q.from = Vector3(wx, top, wz)
			q.to = Vector3(wx, bottom, wz)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			img.set_pixel(x, y, _bake_color(hit, floor_y))
		if Time.get_ticks_usec() - t0 > BAKE_BUDGET_USEC:
			tex.update(img)
			await get_tree().process_frame
			if not is_inside_tree() or get_tree().current_scene == null or get_tree().current_scene.scene_file_path != _scene_path:
				return   # сцену сменили — недоснятая карта в кэш не попадает
			space = get_viewport().world_3d.direct_space_state
			t0 = Time.get_ticks_usec()
	tex.update(img)
	_cache[_scene_path] = {"tex": tex, "origin": _origin}


func _bake_color(hit: Dictionary, floor_y: float) -> Color:
	var col: Object = hit["collider"]
	var name := ""
	var node := col as Node
	for i in 3:
		if node == null:
			break
		name += String(node.name) + "/"
		node = node.get_parent()
	if "Door" in name:
		return Color(0.62, 0.42, 0.22)
	if "Chasm" in name:
		return Color(0.04, 0.04, 0.06)
	var hy: float = hit["position"].y
	if "Wall" in name or hy > floor_y + 1.6:
		return Color(0.60, 0.58, 0.54)
	# Пол: чем ниже, тем темнее (пандусы и нижние залы читаются).
	var t := clampf((hy - floor_y + 6.0) / 8.0, 0.25, 1.0)
	return Color(0.24, 0.27, 0.32).lerp(Color(0.38, 0.40, 0.44), t)
