class_name NatureScatter
extends Node3D
## Растительность из пака (Tools/blender/nature_pack.py) по расстановке из генератора локации
## (для мира — assets/levels/world_nature.json, пишет Tools/blender/build_world.py).
## Собирается при запуске: MultiMesh по модели и участку карты (участки дальше visibility range
## не рисуются — густая трава не грузит кадр), коллизии стволов и камней — одним StaticBody3D.
## Подлесок и мелочи (Dt_*, Pr_*) — их сотня тысяч — показываются только участками вокруг Рэя (как трава в GrassField):
## узлов столько же, сколько в маленькой карте, размер мира на кадр не влияет; коллизии предметов — всегда.
## Формат расстановки: {модель: [x, y, z, поворот, масштаб, ...]} в осях Godot.

const PACK_SCENE := "res://assets/models/nature/nature_pack.glb"
const PACK_INFO := "res://assets/models/nature/pack.json"
## Дополнения: подлесок и мелочи (Tools/blender/nature_extras.py). Dt_* — мелочь, Pr_* — предметы.
const EXTRAS_SCENE := "res://assets/models/nature/nature_extras.glb"
const EXTRAS_INFO := "res://assets/models/nature/pack_extras.json"
const TEXTURES := "res://assets/models/nature/textures/"
const SHADER := preload("res://assets/shaders/foliage.gdshader")

## Группы моделей: размер участка, дальность видимости, тени, коллизия.
const GROUPS := {
	"grass": {"chunk": 16.0, "range": 42.0, "shadow": false, "collide": ""},
	"flower": {"chunk": 16.0, "range": 42.0, "shadow": false, "collide": ""},
	"bush": {"chunk": 32.0, "range": 75.0, "shadow": true, "collide": ""},
	"rock": {"chunk": 48.0, "range": 120.0, "shadow": true, "collide": "crown"},
	"tree": {"chunk": 48.0, "range": 170.0, "shadow": true, "collide": "trunk"},
	"detail": {"shadow": false, "collide": "", "stream": true},
	"prop": {"shadow": true, "collide": "solid", "stream": true},
}
## Участки подлеска: размер, радиус вокруг Рэя, сколько строить за кадр (ближние первыми).
const STREAM_CELL := 24.0
const STREAM_RADIUS := 66.0
const STREAM_PER_FRAME := 2
## Ветер (на метр высоты) и подкраска по текстуре. Трава гнётся сильнее крон.
const SWAY := {"Grass": 0.05, "Flowers": 0.04, "Bush_Leaves": 0.02, "Reed": 0.03, "ExtrasFoliage": 0.03}
const TREE_SWAY := 0.005
## Коллизия ствола: мера из пака у некоторых ив и сосен захватывает низкие ветки (до 2,6 м) — невидимая стена.
const MAX_TRUNK := 0.35
## Салатовая листва пака — приглушить к насыщенному, но не кислотному зелёному Брода.
const TINT := {"NormalTree_Leaves": Color(0.7, 0.8, 0.58), "Bush_Leaves": Color(0.62, 0.74, 0.55),
	"PineTree_Leaves": Color(0.66, 0.86, 0.62), "Grass": Color(0.95, 1.0, 0.9)}

@export_file("*.json") var data_path: String

var _materials: Dictionary = {}
## Меши пака с материалами листвы (берёт и GrassField — трава вокруг Рэя).
var meshes: Dictionary = {}
## Участок → {модель: [x, y, z, поворот, масштаб, ...]}; участок на экране → его узлы.
var _stream: Dictionary = {}
var _stream_live: Dictionary = {}
var _stream_queue: Array[Vector2i] = []
var _stream_center := Vector2i(2147483647, 2147483647)
var _player: Node3D


func _ready() -> void:
	if data_path.is_empty():
		return
	var placed: Dictionary = _read_json(data_path)
	var info: Dictionary = _read_json(PACK_INFO).get("models", {})
	info.merge(_read_json(EXTRAS_INFO).get("models", {}))
	meshes = _pack_meshes(PACK_SCENE)
	if ResourceLoader.exists(EXTRAS_SCENE):
		meshes.merge(_pack_meshes(EXTRAS_SCENE))
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for model in placed:
		var mesh: Mesh = meshes.get(model)
		if mesh == null:
			push_warning("NatureScatter: нет модели %s в паке" % model)
			continue
		var group := group_of(model)
		var cfg: Dictionary = GROUPS[group]
		var data: Array = placed[model]
		if cfg.get("stream", false):
			_add_to_stream(model, data)
		else:
			var chunks := _split(data, cfg.chunk)
			for key in chunks:
				_add_chunk(model, mesh, data, chunks[key], cfg)
		var rec: Dictionary = info.get(model, {})
		if rec.has("box"):
			_add_box_colliders(body, data, rec["box"])
		elif group == "prop":
			if rec.has("solid"):
				_add_colliders(body, data, rec["solid"])
		elif cfg.collide != "":
			var r: float = rec.get(cfg.collide, 0.3)
			if group == "rock":
				r *= 0.8
			elif group == "tree":
				r = minf(r, MAX_TRUNK)
			_add_colliders(body, data, r)


func _process(_delta: float) -> void:
	if _stream.is_empty():
		set_process(false)
		return
	for i in STREAM_PER_FRAME:
		if _stream_queue.is_empty():
			break
		var key: Vector2i = _stream_queue.pop_front()
		if not _stream_live.has(key):
			_stream_live[key] = _build_stream_cell(key)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var p := _player.global_position
	var c := Vector2i(floori(p.x / STREAM_CELL), floori(p.z / STREAM_CELL))
	if c == _stream_center:
		return
	_stream_center = c
	var r := int(ceil(STREAM_RADIUS / STREAM_CELL))
	var want: Array[Vector2i] = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dz).length() * STREAM_CELL <= STREAM_RADIUS + STREAM_CELL:
				want.append(c + Vector2i(dx, dz))
	want.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - c).length_squared() < (b - c).length_squared())
	var wanted := {}
	for key in want:
		wanted[key] = true
	for key in _stream_live.keys():
		if not wanted.has(key):
			for n in _stream_live[key]:
				n.queue_free()
			_stream_live.erase(key)
	_stream_queue.clear()
	for key in want:
		if not _stream_live.has(key) and _stream.has(key):
			_stream_queue.append(key)


func _add_to_stream(model: String, data: Array) -> void:
	for i in range(0, data.size(), 5):
		var key := Vector2i(floori(data[i] / STREAM_CELL), floori(data[i + 2] / STREAM_CELL))
		var cell: Dictionary = _stream.get_or_add(key, {})
		var arr: PackedFloat32Array = cell.get(model, PackedFloat32Array())
		arr.append(data[i])
		arr.append(data[i + 1])
		arr.append(data[i + 2])
		arr.append(data[i + 3])
		arr.append(data[i + 4])
		cell[model] = arr


func _build_stream_cell(key: Vector2i) -> Array:
	var nodes := []
	var cell: Dictionary = _stream[key]
	for model in cell:
		var arr: PackedFloat32Array = cell[model]
		var count := arr.size() / 5
		var center := Vector3.ZERO
		for n in count:
			center += Vector3(arr[n * 5], arr[n * 5 + 1], arr[n * 5 + 2])
		center /= count
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[model]
		mm.instance_count = count
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(model) ^ (key.x * 73856093) ^ (key.y * 19349663)
		for n in count:
			var s := arr[n * 5 + 4]
			var basis := Basis(Vector3.UP, arr[n * 5 + 3]).scaled(Vector3(s, s, s))
			mm.set_instance_transform(n, Transform3D(basis, Vector3(arr[n * 5], arr[n * 5 + 1], arr[n * 5 + 2]) - center))
			mm.set_instance_custom_data(n, Color(rng.randf_range(0.88, 1.08), 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = center
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if GROUPS[group_of(model)].shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		nodes.append(mmi)
	return nodes


static func group_of(model: String) -> String:
	if model.begins_with("Dt_"):
		return "detail"
	if model.begins_with("Pr_"):
		return "prop"
	if model.begins_with("Grass") or model.begins_with("Reed"):
		return "grass"
	if model.begins_with("Flower") or model.begins_with("Petals") or model.begins_with("LilyPad"):
		return "flower"
	if model.begins_with("Bush") or model.begins_with("Plant"):
		return "bush"
	if model.begins_with("Rock"):
		return "rock"
	return "tree"


func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## Меши пака по имени модели; материалы поверхностей — шейдер листвы с пиксельной текстурой.
func _pack_meshes(path: String) -> Dictionary:
	var out := {}
	var scene: Node = (load(path) as PackedScene).instantiate()
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		var tree := group_of(String(mi.name)) == "tree"
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var tex_name := src.resource_name.trim_prefix("nature_") if src else ""
			if tex_name != "":
				mesh.surface_set_material(i, _material(tex_name, tree))
		out[String(mi.name)] = mesh
	scene.free()
	return out


func _material(tex_name: String, tree: bool) -> ShaderMaterial:
	var key := tex_name + (":tree" if tree else "")
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_texture", load(TEXTURES + tex_name + ".png"))
	m.set_shader_parameter("tint", TINT.get(tex_name, Color.WHITE))
	m.set_shader_parameter("sway", TREE_SWAY if tree else SWAY.get(tex_name, 0.0))
	# Камни и трава Рэя не закрывают — окно в них не нужно.
	m.set_shader_parameter("xray", tree or tex_name == "Bush_Leaves" or tex_name == "ExtrasFoliage")
	if tree:
		m.set_shader_parameter("near_fade_from", 0.42)
		m.set_shader_parameter("near_fade_to", 0.7)
	if tex_name == "ExtrasFoliage":
		m.set_shader_parameter("up_normal", 0.8)
	_materials[key] = m
	return m


## Экземпляры по участкам карты: {Vector2i: [смещение в data, ...]}.
func _split(data: Array, size: float) -> Dictionary:
	var out := {}
	for i in range(0, data.size(), 5):
		var key := Vector2i(floori(data[i] / size), floori(data[i + 2] / size))
		if not out.has(key):
			out[key] = []
		out[key].append(i)
	return out


func _add_chunk(model: String, mesh: Mesh, data: Array, idx: Array, cfg: Dictionary) -> void:
	# Центр участка — среднее положений (от него считается дальность видимости).
	var center := Vector3.ZERO
	for i in idx:
		center += Vector3(data[i], data[i + 1], data[i + 2])
	center /= idx.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = idx.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(model) ^ int(center.x * 13.0 + center.z * 7.0)
	for n in idx.size():
		var i: int = idx[n]
		var s: float = data[i + 4]
		var basis := Basis(Vector3.UP, data[i + 3]).scaled(Vector3(s, s, s))
		mm.set_instance_transform(n, Transform3D(basis, Vector3(data[i], data[i + 1], data[i + 2]) - center))
		mm.set_instance_custom_data(n, Color(rng.randf_range(0.88, 1.08), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_%d" % [model, get_child_count()]
	mmi.multimesh = mm
	mmi.position = center
	mmi.visibility_range_end = cfg.range
	mmi.visibility_range_end_margin = 8.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cfg.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Длинные предметы (брёвна): коробка по размеру модели, повёрнута вместе с экземпляром.
func _add_box_colliders(body: StaticBody3D, data: Array, size: Array) -> void:
	for i in range(0, data.size(), 5):
		var s: float = data[i + 4]
		var shape := BoxShape3D.new()
		shape.size = Vector3(size[0], size[1], size[2]) * s
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(Basis(Vector3.UP, data[i + 3]), Vector3(data[i], data[i + 1] + size[1] * s * 0.5, data[i + 2]))
		body.add_child(cs)


func _add_colliders(body: StaticBody3D, data: Array, radius: float) -> void:
	for i in range(0, data.size(), 5):
		var shape := CylinderShape3D.new()
		shape.radius = maxf(radius * data[i + 4], 0.15)
		shape.height = 3.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(data[i], data[i + 1] + 1.5, data[i + 2])
		body.add_child(cs)
