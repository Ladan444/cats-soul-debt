extends SceneTree
## Собирает основную карту — мир вокруг Ивового Брода (старый Брод и тестовые карты убраны 2026-10-29):
## рельеф — участки 64 м из высот Blender (Арт/Blender/world_heights.bin + world_terrain.json, пишет
## Tools/blender/build_world.py) с LOD, коллизия — HeightMapShape3D; карта смешивания земли → ресурсы;
## геометрия — assets/levels/world.glb; растительность — NatureScatter (world_nature.json), трава — GrassField;
## Рэй у колодца, камера, атмосфера, интерфейс. Результат — scenes/levels/world.tscn.
## Запуск: Godot_console --headless --path Game/CatsSoulDebt -s <абсолютный путь к этому файлу>

const GLB := "res://assets/levels/world.glb"
const OUT := "res://scenes/levels/world.tscn"
const NATURE := "res://assets/levels/world_nature.json"
const SPLAT := "res://assets/levels/world_splat_%s.res"
const CHUNKS := "res://assets/levels/world_terrain/"
## Клеток (по 2 м) в участке рельефа.
const CHUNK_CELLS := 32
## Старт — к югу от колодца (Blender x, y).
const START := Vector2(0, -20)
const TAVERN := "res://scenes/levels/tavern.tscn"
## Куда встаёт Рэй в таверне — у входной двери (Tools/blender/build_tavern.py, exit-village).
const TAVERN_ARRIVAL := Vector3(-1, 0.2, 4.0)
const RUBEZH := "res://scenes/levels/rubezh_f1.tscn"
## Куда встаёт Рэй в Рубеже — у ворот (этаж 1).
const RUBEZH_ARRIVAL := Vector3(0, 0, 64.5)
## Места на карте мира (id пустышки poi-<id> → подпись), как POIS в Tools/world_layout.py.
const PLACES := {"rubezh": "Каменный Рубеж", "main_bridge": "Главный мост", "old_bridge": "Старый мостик",
	"tavern": "Ивовый Брод", "rickety_bridge": "Ветхий мостик", "hunters": "Охотничий лагерь",
	"logging": "Заброшенная вырубка", "shrine": "Лесное святилище", "cemetery": "Старое кладбище",
	"mine": "Заброшенная шахта", "cave": "Пещера", "gorge": "Ущелье", "adit": "Старая штольня",
	"pier": "Пристань Оды", "hermit": "Хижина Клауса", "south_edge": "К южным землям"}
## Фонарь подписывается по ближайшему месту: «Фонарь: <место>» (родительный падеж не склоняем).

var map_root: Node3D
var grass: Node3D
var data_dir: String
var info: Dictionary
var heights: PackedFloat32Array
var nx: int
var ny: int
var step: float
var origin: Vector2


func _initialize() -> void:
	data_dir = ProjectSettings.globalize_path("res://").path_join("../../Арт/Blender/").simplify_path()
	info = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join("world_terrain.json")))
	heights = FileAccess.get_file_as_bytes(data_dir.path_join("world_heights.bin")).to_float32_array()
	nx = int(info.size[0])
	ny = int(info.size[1])
	step = float(info.step)
	origin = Vector2(info.origin[0], info.origin[1])
	map_root = Node3D.new()
	map_root.name = "World"
	map_root.set_script(load("res://scripts/levels/world_level.gd"))
	_build_terrain()
	var geometry: Node3D = (load(GLB) as PackedScene).instantiate()
	geometry.name = "Geometry"
	_add(geometry)
	# Группы «Edit_<id>» внутри glb можно двигать в редакторе (правки — в Tools/world_overrides.json).
	map_root.set_editable_instance(geometry, true)
	var nature := Node3D.new()
	nature.name = "Nature"
	nature.set_script(load("res://scripts/levels/nature_scatter.gd"))
	nature.set("data_path", NATURE)
	_add(nature)
	# Трава — участками вокруг Рэя (после Nature: берёт у него меши пака).
	grass = Node3D.new()
	grass.name = "Grass"
	grass.set_script(load("res://scripts/levels/grass_field.gd"))
	grass.set("player_path", NodePath("../Player"))
	grass.set("nature_path", NodePath("../Nature"))
	grass.set("terrain_shape_path", NodePath("../Terrain/TerrainBody/Shape"))
	_add(grass)
	_build_environment()
	var start := Vector3(START.x, _height(START.x, START.y), -START.y)
	_build_player_and_camera(start)
	var ambience := Node3D.new()
	ambience.name = "Ambience"
	ambience.set_script(load("res://scripts/environment/ambience.gd"))
	ambience.set("player_path", NodePath("../Player"))
	ambience.set("geometry_path", NodePath("../Geometry"))
	_add(ambience)
	# Смена дня и ночи (TimeOfDay): солнце/луна, небо, туман, светлячки ночью; в паузе мастер-меню тоже.
	var day := Node.new()
	day.name = "DayNight"
	day.set_script(load("res://scripts/environment/day_night.gd"))
	day.set("sun_path", NodePath("../Sun"))
	day.set("atmosphere_path", NodePath("../Atmosphere"))
	day.set("ambience_path", NodePath("../Ambience"))
	day.set("noon_yaw", -30.0)
	day.process_mode = Node.PROCESS_MODE_ALWAYS
	_add(day)
	_build_lanterns(geometry)
	_build_exits(geometry)
	_build_pickups(geometry)
	# Жители Брода и их побочные квесты (scripts/data/village_quests.gd) — расставляются при запуске.
	var villagers := Node3D.new()
	villagers.name = "Villagers"
	villagers.set_script(load("res://scripts/levels/village_quests_runtime.gd"))
	villagers.set("geometry_path", NodePath("../Geometry"))
	villagers.set("player_path", NodePath("../Player"))
	villagers.set("navigation_path", NodePath("../LocalNavigation"))
	var local_nav := Node.new()
	local_nav.name = "LocalNavigation"
	local_nav.set_script(load("res://scripts/levels/local_navigation.gd"))
	local_nav.set("terrain_shape_path", NodePath("../Terrain/TerrainBody/Shape"))
	local_nav.set("nature_body_path", NodePath("../Nature/Collision"))
	_add(local_nav)
	_add(villagers)
	# Постоянные лагеря врагов (квалды, кобольды, голем, мини-босс) — появляются, когда Рэй рядом.
	var camps := Node3D.new()
	camps.name = "Camps"
	camps.set_script(load("res://scripts/levels/world_camps.gd"))
	camps.set("player_path", NodePath("../Player"))
	camps.set("navigation_path", NodePath("../LocalNavigation"))
	_add(camps)
	_build_hud()
	_build_minimap()
	_build_world_map(geometry)
	map_root.set("player_path", NodePath("Player"))
	map_root.set("geometry_path", NodePath("Geometry"))
	map_root.set("terrain_path", NodePath("Terrain"))
	_build_splat()
	var scene := PackedScene.new()
	var err := scene.pack(map_root)
	if err == OK:
		err = ResourceSaver.save(scene, OUT)
	print("сохранено: ", OUT, " (код ", err, ")")
	map_root.free()
	quit(err)


func _add(node: Node, parent: Node = null) -> Node:
	(parent if parent else map_root).add_child(node)
	node.owner = map_root
	return node


## Высота в клетке (i — столбец по x, r — строка по Blender y).
func _h(i: int, r: int) -> float:
	return heights[clampi(r, 0, ny - 1) * nx + clampi(i, 0, nx - 1)]


## Высота в точке Blender (x, y) — билинейно.
func _height(x: float, y: float) -> float:
	var fx := (x - origin.x) / step
	var fy := (y - origin.y) / step
	var i := int(floor(fx))
	var r := int(floor(fy))
	var tx := fx - i
	var ty := fy - r
	return lerpf(lerpf(_h(i, r), _h(i + 1, r), tx), lerpf(_h(i, r + 1), _h(i + 1, r + 1), tx), ty)


## Рельеф: участки CHUNK_CELLS × CHUNK_CELLS клеток (меш с LOD — ресурс в CHUNKS) + одна коллизия на весь мир.
func _build_terrain() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CHUNKS))
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	_add(terrain)
	var count := 0
	for cr in range(0, ny - 1, CHUNK_CELLS):
		for ci in range(0, nx - 1, CHUNK_CELLS):
			var mesh := _chunk_mesh(ci, cr, mini(CHUNK_CELLS, nx - 1 - ci), mini(CHUNK_CELLS, ny - 1 - cr))
			var path := CHUNKS + "c_%02d_%02d.res" % [ci / CHUNK_CELLS, cr / CHUNK_CELLS]
			ResourceSaver.save(mesh, path)
			var mi := MeshInstance3D.new()
			mi.name = "C_%02d_%02d" % [ci / CHUNK_CELLS, cr / CHUNK_CELLS]
			mi.mesh = load(path)
			_add(mi, terrain)
			count += 1
	# Коллизия: карта высот (ячейка 1 → масштаб step), строки по z (Godot z = −Blender y).
	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = ny
	var data := PackedFloat32Array()
	data.resize(nx * ny)
	for zi in ny:
		var r := ny - 1 - zi
		for i in nx:
			data[zi * nx + i] = heights[r * nx + i]
	shape.map_data = data
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	_add(body, terrain)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	cs.position = Vector3(origin.x + (nx - 1) * step / 2.0, 0, -(origin.y + (ny - 1) * step / 2.0))
	cs.scale = Vector3(step, 1, step)
	_add(cs, body)
	print("участков рельефа: ", count)


func _chunk_mesh(ci: int, cr: int, w: int, d: int) -> Mesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for r in range(cr, cr + d + 1):
		for i in range(ci, ci + w + 1):
			verts.append(Vector3(origin.x + i * step, _h(i, r), -(origin.y + r * step)))
			var dx := (_h(i + 1, r) - _h(i - 1, r)) / (2.0 * step)
			var dz := -(_h(i, r + 1) - _h(i, r - 1)) / (2.0 * step)
			normals.append(Vector3(-dx, 1.0, -dz).normalized())
	var row := w + 1
	for r in d:
		for i in w:
			var a := r * row + i
			var b := a + 1
			var c := a + row
			var e := c + 1
			idx.append_array([a, c, b, b, c, e])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


## Переходы: дверь таверны (пустышка door-tavern) → зал таверны; ворота Рубежа (poi-rubezh-gate) → этаж 1.
## Обратные точки прибытия — в build_tavern.gd и build_rubezh.gd (там же берутся из world.glb).
func _build_exits(geometry: Node3D) -> void:
	var door := geometry.get_node_or_null("door-tavern") as Node3D
	if door:
		var exit := Area3D.new()
		exit.name = "ExitToTavern"
		exit.set_script(load("res://scripts/levels/level_exit.gd"))
		exit.set("target_scene", TAVERN)
		exit.set("target_position", TAVERN_ARRIVAL)
		exit.set("size", Vector3(2.4, 3.0, 1.0))
		exit.set("label", "Таверна «Красная черепица»")
		exit.position = door.position + Vector3(0, 0.2, 0)
		_add(exit)
	var gate := geometry.get_node_or_null("poi-rubezh-gate") as Node3D
	if gate:
		var exit := Area3D.new()
		exit.name = "ExitToRubezh"
		exit.set_script(load("res://scripts/levels/level_exit.gd"))
		exit.set("target_scene", RUBEZH)
		exit.set("target_position", RUBEZH_ARRIVAL)
		exit.set("size", Vector3(5.0, 4.0, 2.0))
		exit.set("label", "Каменный Рубеж")
		exit.position = gate.position
		_add(exit)


## Находки мира: пустышка item-<id предмета> (build_world.py) → StoryPickup с сохранением «подобрано».
## Росток каменной ивы Главы 1 — у святилища (решение автора 2026-10-27; новые ростки — в следующих главах).
func _build_pickups(geometry: Node3D) -> void:
	for c in geometry.get_children():
		var n := String(c.name)
		if not n.begins_with("item-"):
			continue
		var id := n.trim_prefix("item-").get_slice(".", 0)
		var p := Node3D.new()
		p.set_script(load("res://scripts/levels/story_pickup.gd"))
		p.name = "Story_" + id
		p.set("kind", "item")
		p.set("content_id", StringName(id))
		p.set("persist_id", "world:%s:ch1" % id)
		p.position = (c as Node3D).position
		_add(p)


## Фонари душ: у каждого подвесного фонаря (пустышка fx-soul-lantern-NN) — SoulLantern без своей модели
## (свет, подсказка, точка возрождения у подножия посоха); за ними — цикл смерти.
func _build_lanterns(geometry: Node3D) -> void:
	var g := Node3D.new()
	g.name = "Lanterns"
	_add(g)
	for c in geometry.get_children():
		var n := String(c.name)
		if not n.begins_with("fx-soul-lantern-"):
			continue
		var at: Vector3 = (c as Node3D).position
		var lantern := Node3D.new()
		lantern.set_script(load("res://scripts/combat/soul_lantern.gd"))
		lantern.name = "SoulLantern_" + n.get_slice("-", 3)
		lantern.position = at
		lantern.set("builtin_model", false)
		lantern.set("glow_offset", Vector3.ZERO)
		var ground_r := _height(at.x, -(at.z + 1.2))
		lantern.set("respawn_offset", Vector3(0, ground_r - at.y + 0.3, 1.2))
		_add(lantern, g)
	var cycle := CanvasLayer.new()
	cycle.name = "DeathCycle"
	cycle.set_script(load("res://scripts/combat/death_cycle.gd"))
	cycle.set("player_path", NodePath("../Player"))
	_add(cycle)


## Миникарта — вид сверху из Blender (world_map_top.png, границы — в json рядом), 2 м на пиксель.
func _build_minimap() -> void:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join("world_map_top.json")))
	var img := Image.load_from_file(data_dir.path_join("world_map_top.png"))
	if not (meta is Dictionary) or img == null:
		push_warning("нет вида сверху — миникарта снимется лучами")
		return
	var b: Array = meta.bounds_m
	var mpp := 2.0
	img.resize(int((b[2] - b[0]) / mpp), int((b[3] - b[1]) / mpp), Image.INTERPOLATE_LANCZOS)
	var path := "res://assets/levels/world_minimap.res"
	ResourceSaver.save(ImageTexture.create_from_image(img), path)
	# Левый верхний пиксель — северо-запад: Godot x = x0 Blender, z = −y1 Blender.
	map_root.set_meta("minimap", {"texture": path, "origin": Vector2(b[0], -b[3]), "mpp": mpp, "zoom": 1.0,
		"reveal": false})


## Карта мира с быстрыми перемещениями: вид сверху 1 м/пиксель (с mip-уровнями — карта уменьшается
## плавно), подписи мест и фонарей по пустышкам poi-*.
func _build_world_map(geometry: Node3D) -> void:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join("world_map_top.json")))
	var img := Image.load_from_file(data_dir.path_join("world_map_top.png"))
	if not (meta is Dictionary) or img == null:
		return
	var b: Array = meta.bounds_m
	img.resize(int(b[2] - b[0]), int(b[3] - b[1]), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	var path := "res://assets/levels/world_map.res"
	ResourceSaver.save(ImageTexture.create_from_image(img), path)
	var places := []
	for c in geometry.get_children():
		var n := String(c.name)
		if n.begins_with("poi-") and PLACES.has(n.trim_prefix("poi-")):
			var p: Vector3 = (c as Node3D).position
			places.append([PLACES[n.trim_prefix("poi-")], Vector2(p.x, p.z)])
	var names := {}
	for l in map_root.get_node("Lanterns").get_children():
		var lp := Vector2(l.position.x, l.position.z)
		var best := ""
		var best_d := INF
		for p in places:
			var d := lp.distance_to(p[1])
			if d < best_d:
				best_d = d
				best = p[0]
		names[String(l.name)] = "Фонарь душ: %s" % best if best_d < 260.0 else "Фонарь душ"
	var map := CanvasLayer.new()
	map.name = "WorldMap"
	map.set_script(load("res://scripts/ui/fast_travel_map.gd"))
	map.set("player_path", NodePath("../Player"))
	map.set("camera_path", NodePath("../Camera3D"))
	map.set("map_texture", load(path))
	map.set("map_origin", Vector2(b[0], -b[3]))
	map.set("map_mpp", 1.0)
	map.set("places", places)
	map.set("lantern_names", names)
	_add(map)


## Карта смешивания земли (PNG из Blender, вне проекта) → ресурсы без сжатия.
func _build_splat() -> void:
	for key in ["a", "b", "c"]:
		var img := Image.load_from_file(data_dir.path_join("world_splat_%s.png" % key))
		var tex := ImageTexture.create_from_image(img)
		var path := SPLAT % key
		ResourceSaver.save(tex, path)
		map_root.set("splat_" + key, load(path))
		grass.set("splat_" + key, load(path))
	grass.set("splat_origin", origin)
	grass.set("splat_step", step)
	map_root.set("splat_origin", origin)
	map_root.set("splat_size", Vector2(nx, ny))
	map_root.set("splat_step", step)


## День в долине (как в Броде; цикл дня и ночи — позже).
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# HDR (решение автора: «больше визуальных эффектов и HDR»): Filmic (AgX сравнивали — выцветает зелень),
	# свечение только у ярких мест (фонари, огонь, блики воды), SSIL — цветной отражённый свет от земли и стен.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.2
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.2
	env.glow_bloom = 0.06
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(1, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(5, 0.6)
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.adjustment_contrast = 1.06
	env.fog_enabled = true
	env.fog_height = 1.0
	env.fog_height_density = 0.06
	env.fog_aerial_perspective = 0.35
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(1.0, 0.94, 0.82)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 60.0
	env.volumetric_fog_ambient_inject = 0.15
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	var blender: WorldEnvironment = load("res://scripts/environment/atmosphere_blender.gd").new()
	blender.name = "Atmosphere"
	blender.environment = env
	blender.set("target_path", NodePath("../Player"))
	var p := AtmospherePreset.new()
	p.zone_name = "Долина Серебряной Реки"
	p.hub = false   # в мире бои (враги квестов) — хотбар нужен
	p.start_x = -10000.0
	p.background_color = Color(0.62, 0.70, 0.78)
	p.ambient_color = Color(0.70, 0.66, 0.56)
	p.ambient_energy = 0.45
	p.fog_color = Color(0.68, 0.72, 0.76)
	p.fog_density = 0.003
	p.glow_intensity = 0.5
	p.saturation = 1.15
	var presets: Array[AtmospherePreset] = [p]
	blender.set("presets", presets)
	_add(blender)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.9, 0.74)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_blend_splits = true
	sun.light_volumetric_fog_energy = 1.6
	sun.rotation_degrees = Vector3(-52, -30, 0)
	_add(sun)


func _build_player_and_camera(start: Vector3) -> void:
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	player.position = start + Vector3(0, 0.3, 0)
	_add(player)
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 22.0
	attrs.dof_blur_far_transition = 10.0
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = 9.0
	attrs.dof_blur_near_transition = 3.0
	attrs.dof_blur_amount = 0.1
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 30.0
	cam.far = 600.0
	cam.attributes = attrs
	var cam_pos := start + Vector3(0, 9, 11)
	cam.transform = Transform3D(Basis.looking_at(start - cam_pos, Vector3.UP), cam_pos)
	cam.set_script(load("res://scripts/camera/diorama_camera.gd"))
	cam.set("target_path", NodePath("../Player"))
	_add(cam)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	_add(layer)
	var scaler: Control = load("res://scripts/ui/ui_scaler.gd").new()
	scaler.name = "UIScaler"
	_add(scaler, layer)
	var hud := Control.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/ui/hud.gd"))
	hud.set("atmosphere_path", NodePath("../../../Atmosphere"))
	_add(hud, scaler)
	var touch: Control = load("res://scripts/ui/touch_controls.gd").new()
	touch.name = "TouchControls"
	_add(touch, scaler)
	var label := Label.new()
	label.name = "DebugHint"
	label.position = Vector2(6, 44)
	label.add_theme_color_override("font_outline_color", Color("2a1e18"))
	label.add_theme_constant_override("outline_size", 2)
	label.set_script(load("res://scripts/ui/debug_hud.gd"))
	label.set("player_path", NodePath("../../../Player"))
	label.set("atmosphere_path", NodePath("../../../Atmosphere"))
	_add(label, scaler)
	var book := CanvasLayer.new()
	book.name = "Book"
	book.set_script(load("res://scripts/ui/book/book.gd"))
	book.set("player_path", NodePath("../Player"))
	_add(book)
	var dialogue := CanvasLayer.new()
	dialogue.name = "DialogueBox"
	dialogue.set_script(load("res://scripts/ui/dialogue_box.gd"))
	_add(dialogue)
	var pause := CanvasLayer.new()
	pause.name = "PauseMenu"
	pause.set_script(load("res://scripts/ui/pause_menu.gd"))
	_add(pause)
	var keys := Node.new()
	keys.name = "DebugKeys"
	keys.set_script(load("res://scripts/debug/debug_keys.gd"))
	_add(keys)
