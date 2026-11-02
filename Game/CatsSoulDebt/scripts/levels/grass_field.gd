class_name GrassField
extends Node3D
## Трава вокруг Рэя в большом мире (сотни тысяч пучков в файл не пишем — PROGRESS, мир вокруг Брода):
## участки CELL × CELL м в радиусе RADIUS вокруг Рэя появляются и исчезают по ходу. Пучки — модели пака
## (меши и материал листвы берутся у NatureScatter), точки — детерминированно по номеру участка,
## высота — из сетки высот рельефа, густота — по карте смешивания земли (на дорогах, скалах, пашне,
## брусчатке, под водой и в снегу травы нет; на сухой траве и в тени леса — реже). Под постройками,
## мостами и в домах (там пол) травы нет — точку отсекает луч сверху, задевший что-то кроме рельефа.

const CELL := 8.0
const RADIUS := 52.0
## Пучков на м² на чистом лугу: мелкая и крупная трава, цветы (решение автора: «больше травы»).
const DENSITY := {"Grass_Small": 1.7, "Grass_Large_Extruded": 0.6, "Flower_1_Clump": 0.03, "Flower_3_Clump": 0.03,
	"Petals_1": 0.02}

@export var player_path: NodePath
@export var nature_path: NodePath
@export var terrain_shape_path: NodePath
## Карта смешивания (те же текстуры, что у шейдера земли) и её привязка.
@export var splat_a: Texture2D
@export var splat_b: Texture2D
@export var splat_c: Texture2D
@export var splat_origin := Vector2.ZERO
@export var splat_step := 2.0

var _first_physics := -1
var _pending: Array[Vector2i] = []
const BUILD_PER_FRAME := 3
var _player: Node3D
var _meshes: Dictionary = {}
var _cells: Dictionary = {}
var _center := Vector2i(1 << 30, 0)
var _heights: PackedFloat32Array
var _hw := 0
var _hd := 0
var _h_origin := Vector2.ZERO
var _h_step := 2.0
var _a: Image
var _b: Image
var _c: Image


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	var nature := get_node_or_null(nature_path)
	if nature:
		for model in DENSITY:
			if nature.meshes.has(model):
				_meshes[model] = nature.meshes[model]
	var cs := get_node_or_null(terrain_shape_path) as CollisionShape3D
	if cs and cs.shape is HeightMapShape3D:
		var hm := cs.shape as HeightMapShape3D
		_heights = hm.map_data
		_hw = hm.map_width
		_hd = hm.map_depth
		_h_step = cs.scale.x
		# Угол сетки (Godot x, z) — центр формы минус половина размера.
		_h_origin = Vector2(cs.global_position.x - (_hw - 1) * _h_step / 2.0,
			cs.global_position.z - (_hd - 1) * _h_step / 2.0)
	_a = _image(splat_a)
	_b = _image(splat_b)
	_c = _image(splat_c)


func _image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	return img


func _process(_delta: float) -> void:
	if _player == null or _meshes.is_empty() or _heights.is_empty():
		return
	# Лучи «нет ли над клеткой постройки» нужны готовой физике: коллизии домов world_level ставит в _ready,
	# в мир они попадают через такт — первые клетки иначе засевали траву внутри домов.
	if _first_physics < 0:
		_first_physics = Engine.get_physics_frames()
	if Engine.get_physics_frames() - _first_physics < 2:
		return
	# Новые клетки — по несколько за кадр, ближние первыми: раньше при переходе через границу клетки строилось
	# ~14 клеток (тысячи лучей) за один кадр — рывок каждые 8 м.
	for i in BUILD_PER_FRAME:
		if _pending.is_empty():
			break
		var key: Vector2i = _pending.pop_front()
		if not _cells.has(key):
			_cells[key] = _build_cell(key)
	var p := _player.global_position
	var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if c == _center:
		return
	_center = c
	var r := int(ceil(RADIUS / CELL))
	var want := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dz).length() * CELL <= RADIUS + CELL:
				want[c + Vector2i(dx, dz)] = true
	for key in _cells.keys():
		if not want.has(key):
			for n in _cells[key]:
				n.queue_free()
			_cells.erase(key)
	_pending.clear()
	for key in want:
		if not _cells.has(key):
			_pending.append(key)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i): return (a - c).length_squared() < (b - c).length_squared())


## Высота земли в точке Godot (x, z) — билинейно по сетке коллизии.
func _height(x: float, z: float) -> float:
	var fx := (x - _h_origin.x) / _h_step
	var fz := (z - _h_origin.y) / _h_step
	var i := clampi(int(floor(fx)), 0, _hw - 2)
	var k := clampi(int(floor(fz)), 0, _hd - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - k, 0.0, 1.0)
	var h00 := _heights[k * _hw + i]
	var h10 := _heights[k * _hw + i + 1]
	var h01 := _heights[(k + 1) * _hw + i]
	var h11 := _heights[(k + 1) * _hw + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Доля травы (0…1) по карте смешивания в точке Godot (x, z).
func _grass_weight(x: float, z: float) -> float:
	if _a == null:
		return 1.0
	var px := clampi(int(round((x - splat_origin.x) / splat_step)), 0, _a.get_width() - 1)
	var py := clampi(int(round((-z - splat_origin.y) / splat_step)), 0, _a.get_height() - 1)
	var a := _a.get_pixel(px, py)
	var b := _b.get_pixel(px, py)
	var c := _c.get_pixel(px, py)
	var bare := maxf(maxf(a.r, a.b), maxf(maxf(a.a * 0.9, b.r), maxf(c.g, c.b)))
	var w := 1.0 - bare
	w *= 1.0 - 0.5 * a.g
	w *= 1.0 - 0.45 * b.a
	return clampf(w, 0.0, 1.0)


func _build_cell(key: Vector2i) -> Array:
	var nodes := []
	var rng := RandomNumberGenerator.new()
	var base := Vector3(key.x * CELL, 0.0, key.y * CELL)
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = 1          # только мир (не Рэй и не враги)
	var terrain := get_node_or_null(terrain_shape_path)
	if terrain and terrain.get_parent() is CollisionObject3D:
		ray.exclude = [(terrain.get_parent() as CollisionObject3D).get_rid()]   # рельеф — не постройка
	for model in _meshes:
		rng.seed = hash(Vector3i(key.x, key.y, hash(model)))
		var n := int(CELL * CELL * DENSITY[model])
		var xforms: Array[Transform3D] = []
		var tints: PackedFloat32Array = []
		for i in n:
			var x := base.x + rng.randf() * CELL
			var z := base.z + rng.randf() * CELL
			var keep := rng.randf()
			var yaw := rng.randf() * TAU
			var s := rng.randf_range(0.75, 1.2)
			var tint := rng.randf_range(0.88, 1.08)
			if keep > _grass_weight(x, z):
				continue
			var y := _height(x, z)
			ray.from = Vector3(x, y + 8.0, z)
			ray.to = Vector3(x, y + 0.2, z)
			if not space.intersect_ray(ray).is_empty():
				continue
			xforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(x, y, z) - base))
			tints.append(tint)
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[model]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_custom_data(i, Color(tints[i], 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		mmi.global_position = base
		nodes.append(mmi)
	return nodes
