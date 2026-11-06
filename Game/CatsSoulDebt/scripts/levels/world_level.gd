extends Node3D
## Мир вокруг Ивового Брода (Tools/blender/build_world.py → assets/levels/world.glb; рельеф — участки
## из высот, собирает Tools/godot/build_world.gd). При запуске одевает геометрию из Blender:
## земля — шейдер terrain_splat по карте смешивания (1 пиксель = 2 м), вода — шейдер реки,
## дома и мебель — наборы Quaternius/KayKit, фонари душ — светящееся стекло и огонёк,
## дороги — цвет профиля из Blender с пиксельной текстурой колеи (road_ribbon), крепость, мосты, места
## и мелочи — шейдер wall_xray: цвет вершин из Blender + пиксельная текстура детализацией и «окно» вокруг Рэя.

const TERRAIN_SHADER := preload("res://assets/shaders/terrain_splat.gdshader")
const WATER_SHADER := preload("res://assets/shaders/water_river.gdshader")
const WALL_SHADER := preload("res://assets/shaders/wall_xray.gdshader")
const ROAD_SHADER := preload("res://assets/shaders/road_ribbon.gdshader")
const TEX := "res://assets/textures/village/"
## Слои земли → текстуры деревни (Tools/texture_pipeline.py village).
const TERRAIN_LAYERS := {"tex_grass": "village_grass", "tex_dry": "village_grass_dry", "tex_road": "village_dirt_road",
	"tex_cobble": "village_square_cobble", "tex_soil": "village_field_soil", "tex_rock": "village_rock",
	"tex_pebbles": "village_riverbed", "tex_pebbles_small": "village_riverbed_small"}
const WATER := ["Lake", "River", "Ponds", "Poi_water", "MillWater"]
## Меши с цветом вершин: [текстура детализации (пусто — без неё), плитка в метрах, радиус окна (0 — не резать)].
## Мосты не режутся (как в Броде: Рэй на них всегда сверху); низкие мелочи режутся только выше колен (шейдер).
const DRESS := {"Fortress": ["village_wall_stone", 6.4, 2.6], "FortressRoofs": ["", 0.0, 2.6],
	"Bridge_stone": ["village_wall_stone", 6.4, 0.0], "Bridge_cobble": ["village_square_cobble", 6.4, 0.0],
	"Bridge_arch": ["village_stone_dressed", 3.2, 0.0], "Bridge_trim": ["village_stone_dressed", 3.2, 0.0],
	"Bridge_wood": ["village_wood_beam", 3.2, 0.0], "BridgesWood": ["village_wood_beam", 3.2, 0.0],
	"BridgesPlanks": ["village_wood_beam", 3.2, 0.0],
	"VillageWood": ["village_wood_beam", 3.2, 2.2], "VillageStone": ["village_wall_stone", 6.4, 2.2],
	"VillageThatch": ["village_grass_dry", 6.4, 2.2],
	"Poi_stone": ["village_wall_stone", 6.4, 2.2], "Poi_rock": ["village_rock", 6.4, 2.2],
	"Poi_wood": ["village_wood_beam", 3.2, 2.2], "Poi_oldwood": ["village_wood_beam", 3.2, 2.2],
	"Poi_slate": ["village_rock", 6.4, 2.2],
	"Detail_stone": ["village_wall_stone", 6.4, 2.2], "Detail_darkstone": ["village_wall_stone", 6.4, 2.2],
	"Detail_wood": ["village_wood_beam", 3.2, 2.2], "Detail_oldwood": ["village_wood_beam", 3.2, 2.2],
	"Detail_hay": ["village_grass_dry", 6.4, 2.2], "Detail_moss": ["village_grass", 6.4, 2.2],
	"MillWheel": ["", 0.0, 2.2], "MillBoards": ["village_wood_beam", 3.2, 2.2], "MillDark": ["", 0.0, 2.2],
	"MillMoss": ["village_grass", 6.4, 2.2], "Poi_moss": ["village_grass", 6.4, 2.2],
	"Poi_thatch": ["village_grass_dry", 3.2, 2.2], "VillageDark": ["", 0.0, 2.2]}
## Без коллизии: тонкое и плоское (по крышам, мху и соломе не ходят, ленты дорог лежат на рельефе).
const NO_COLLISION := ["FortressRoofs", "VillageThatch", "Detail_moss", "Detail_hay", "Detail_glass", "Detail_flame",
	"Poi_cloth", "Poi_rune", "MillWheel", "MillMoss", "Poi_moss", "Poi_thatch", "Poi_fur", "Detail_bottles", "Detail_herbs", "BridgesPlanks"]
## Колесо водяной мельницы (MillWheel, начало — на оси вдоль x): наливное, верх идёт по течению, на юг; рад/с.
const MILL_WHEEL_SPEED := 0.55
## Фонарь душ: стекло и огонёк (CANON: фиолетовый вихрь за стеклом).
const SOUL_GLASS := Color(0.5, 0.32, 0.88, 0.6)
const SOUL_FLAME := Color(0.82, 0.62, 1.0)

@export var player_path: NodePath
@export var geometry_path: NodePath
@export var terrain_path: NodePath
@export var splat_a: Texture2D
@export var splat_b: Texture2D
@export var splat_c: Texture2D
@export var splat_origin := Vector2.ZERO
@export var splat_size := Vector2.ONE
@export var splat_step := 2.0

var _player: Node3D
var _means: Dictionary = {}
var _mill_wheel: Node3D


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	var deep := DeepWater.new()
	deep.name = "DeepWater"
	deep.player = _player as CharacterBody3D
	add_child(deep)
	var terrain_mat := _terrain_material()
	for chunk in get_node(terrain_path).get_children():
		if chunk is MeshInstance3D:
			(chunk as MeshInstance3D).material_override = terrain_mat
	# Меши — и прямо в Geometry, и в группах правки «Edit_<id>» (дом, пролёт забора, мелочь — их двигает автор
	# в редакторе, меню «Мир: сохранить правки»); вид меша — имя до «__».
	for child in get_node(geometry_path).find_children("*", "MeshInstance3D", true, false):
		_dress(child as MeshInstance3D)


func _dress(node: MeshInstance3D) -> void:
	var n := String(node.name).get_slice("__", 0)
	if n in WATER:
		var water := ShaderMaterial.new()
		water.shader = WATER_SHADER
		water.set_shader_parameter("flow", Vector2(0.0, 0.45) if n == "River" else Vector2(0.05, 0.02))
		node.material_override = water
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif n in ["Houses", "FortressHouses"]:
		KitDress.quaternius(node)
	elif n == "Props":
		KitDress.kaykit(node)
	elif n == "Roads":
		var road := ShaderMaterial.new()
		road.shader = ROAD_SHADER
		road.set_shader_parameter("road_texture", load(TEX + "village_dirt_road.png"))
		road.set_shader_parameter("detail_mean", _mean("village_dirt_road"))
		node.material_override = road
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif n == "Detail_glass":
		var m := StandardMaterial3D.new()
		m.albedo_color = SOUL_GLASS
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color(SOUL_GLASS, 1.0)
		m.emission_energy_multiplier = 1.5
		node.material_override = m
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif n == "Detail_flame":
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = SOUL_FLAME
		m.emission_enabled = true
		m.emission = SOUL_FLAME
		m.emission_energy_multiplier = 3.0
		node.material_override = m
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif DRESS.has(n) or n.begins_with("Poi_") or n.begins_with("Detail_"):
		var spec: Array = DRESS.get(n, ["", 0.0, 2.2])
		var m := ShaderMaterial.new()
		m.shader = WALL_SHADER
		m.set_shader_parameter("albedo", Color.WHITE)
		m.set_shader_parameter("use_vertex_color", true)
		m.set_shader_parameter("radius", spec[2])
		if spec[0] != "":
			m.set_shader_parameter("use_texture", true)
			m.set_shader_parameter("albedo_texture", load(TEX + spec[0] + ".png"))
			m.set_shader_parameter("texture_meters", spec[1])
			m.set_shader_parameter("detail_mean", _mean(spec[0]))
		node.material_override = m
		# Коллизия по мешу (мосты — настил, крепость — стены, места и мелочи — камни и брёвна).
		if not n in NO_COLLISION:
			node.create_trimesh_collision()
		if n == "MillWheel":
			_mill_wheel = node
	elif node.mesh:
		# Цвет вершин из Blender (материал «Цвет вершин»).
		for i in node.mesh.get_surface_count():
			var src := node.mesh.surface_get_material(i) as BaseMaterial3D
			if src:
				src.vertex_color_use_as_albedo = true
				src.roughness = 0.95


## Средняя яркость текстуры (в линейных цветах, как в шейдере) — для детализации поверх цвета вершин.
func _mean(tex_name: String) -> float:
	if not _means.has(tex_name):
		var img := (load(TEX + tex_name + ".png") as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		var total := 0.0
		var count := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var c := img.get_pixel(x, y).srgb_to_linear()
				total += c.r * 0.3 + c.g * 0.55 + c.b * 0.15
				count += 1
		_means[tex_name] = maxf(total / maxi(count, 1), 0.02)
	return _means[tex_name]


func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter("splat_a", splat_a)
	m.set_shader_parameter("splat_b", splat_b)
	m.set_shader_parameter("splat_c", splat_c)
	m.set_shader_parameter("splat_origin", splat_origin)
	m.set_shader_parameter("splat_size", splat_size)
	m.set_shader_parameter("splat_step", splat_step)
	for param in TERRAIN_LAYERS:
		m.set_shader_parameter(param, load(TEX + TERRAIN_LAYERS[param] + ".png"))
	return m


func _process(delta: float) -> void:
	if _mill_wheel:
		_mill_wheel.rotate_object_local(Vector3.RIGHT, MILL_WHEEL_SPEED * delta)
	if _player:
		RenderingServer.global_shader_parameter_set("player_world_position", _player.global_position + Vector3(0, 0.8, 0))
