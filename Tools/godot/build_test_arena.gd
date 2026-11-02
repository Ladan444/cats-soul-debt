extends SceneTree
## Собирает тестовую арену (три зоны: таверна, Рубеж, озеро) — стенд только для автотестов боя и меню, в игру не входит
## (решение автора 2026-10-29: тестовые карты из игры убраны; папка res://tests/ исключена из сборки exe). Сохраняет в res://tests/test_arena.tscn.
## Запуск: Game/Godot_v4.7.2-stable_win64_console.exe --headless --path Game/CatsSoulDebt -s Tools/godot/build_test_arena.gd
## После пересборки ручные правки сцены теряются — менять карту лучше здесь или перестать пересобирать.
##
## Зоны вдоль X: таверна [-24, -8], Каменный Рубеж [-8, 8], Озеро Тихой Воды [8, 40]. Глубина Z: [-7, 7].

const OUT := "res://tests/test_arena.tscn"
const DEPTH := 14.0

var map_root: Node3D


func _initialize() -> void:
	# Сборка — после первого кадра: запекание навигации требует, чтобы дерево уже работало.
	_build.call_deferred()


func _build() -> void:
	await process_frame
	map_root = Node3D.new()
	map_root.name = "TestMap"

	_build_environment()
	_build_tavern()
	_build_rubezh()
	_build_lake()
	_build_bounds()
	_build_player_and_camera()
	_build_combat()
	_build_hud()
	_bake_navigation()

	var scene := PackedScene.new()
	var err := scene.pack(map_root)
	if err == OK:
		err = ResourceSaver.save(scene, OUT)
	print("сохранено: ", OUT, " (код ", err, ")")
	map_root.free()
	quit(err)


# --- Общие помощники -------------------------------------------------------

func _add(node: Node, parent: Node = null) -> Node:
	(parent if parent else map_root).add_child(node)
	node.owner = map_root
	return node


func _group(group_name: String) -> Node3D:
	var g := Node3D.new()
	g.name = group_name
	return _add(g)


func _mat(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(color)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Твёрдый ящик: StaticBody3D + меш + коллизия.
func _box(parent: Node, node_name: String, pos: Vector3, size: Vector3, material: Material, collide := true) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.name = node_name
	body.position = pos
	_add(body, parent)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	_add(mi, body)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		cs.shape = shape
		_add(cs, body)
	return body


func _cylinder(parent: Node, node_name: String, pos: Vector3, radius: float, height: float, material: Material, collide := true) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.material = material
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.name = node_name
	body.position = pos
	_add(body, parent)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	_add(mi, body)
	if collide:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		cs.shape = shape
		_add(cs, body)
	return body


func _light(parent: Node, node_name: String, pos: Vector3, color: Color, energy: float, light_range: float, flicker := 0.0, shadows := true) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = node_name
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = shadows
	if flicker > 0.0:
		l.set_script(load("res://scripts/environment/flicker_light.gd"))
		l.set("strength", flicker)
	_add(l, parent)
	return l


# --- Атмосфера ---------------------------------------------------------------

func _preset(zone: String, start_x: float, bg: Color, ambient: Color, ambient_energy: float,
		fog: Color, fog_density: float, glow: float, saturation: float, hub := false) -> AtmospherePreset:
	var p := AtmospherePreset.new()
	p.zone_name = zone
	p.hub = hub
	p.start_x = start_x
	p.background_color = bg
	p.ambient_color = ambient
	p.ambient_energy = ambient_energy
	p.fog_color = fog
	p.fog_density = fog_density
	p.glow_intensity = glow
	p.saturation = saturation
	return p


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_bloom = 0.15
	env.fog_enabled = true
	env.ssr_enabled = true  # отражения в воде озера и лужах Рубежа
	env.adjustment_enabled = true

	var blender: WorldEnvironment = load("res://scripts/environment/atmosphere_blender.gd").new()
	blender.name = "Atmosphere"
	blender.environment = env
	blender.set("target_path", NodePath("../Player"))
	blender.set("blend_width", 6.0)
	var presets: Array[AtmospherePreset] = [
		# Таверна: тёплый оранжевый -> насыщенный зелёный, уют.
		_preset("Ивовый Брод — таверна", -1000.0, Color("1a0f08"), Color(0.52, 0.4, 0.3), 0.35,
			Color(0.3, 0.19, 0.1), 0.008, 1.0, 1.1, true),
		# Рубеж: холодный синий -> стальной серый, сырость, давление.
		_preset("Каменный Рубеж", -8.0, Color("0a0e14"), Color(0.35, 0.42, 0.55), 0.32,
			Color(0.14, 0.18, 0.24), 0.012, 0.6, 0.7),
		# Озеро: глубокий фиолетовый -> абсолютный чёрный, мистика.
		_preset("Озеро Тихой Воды", 8.0, Color("06030a"), Color(0.4, 0.25, 0.55), 0.25,
			Color(0.14, 0.06, 0.2), 0.015, 1.1, 1.0),
	]
	blender.set("presets", presets)
	_add(blender)


# --- Таверна (x от -24 до -8) -------------------------------------------------

func _build_tavern() -> void:
	var g := _group("Tavern")
	var wood := _mat(Color("6b4a32"))
	var dark_wood := _mat(Color("4a3020"))
	var stone := _mat(Color("7a6a5a"))
	var wall := _mat(Color("5a3e2a"))

	_box(g, "Floor", Vector3(-16, -0.1, 0), Vector3(16, 0.2, DEPTH), wood)
	_box(g, "BackWall", Vector3(-16, 2, -7.2), Vector3(16, 4, 0.4), wall)
	_box(g, "SideWall", Vector3(-24.2, 2, 0), Vector3(0.4, 4, DEPTH), wall)
	_box(g, "Rug", Vector3(-15, 0.01, 0.5), Vector3(5, 0.02, 3.5), _mat(Color("7a2a24")), false)

	# Камин с огнём.
	_box(g, "Fireplace", Vector3(-20, 1.25, -6.4), Vector3(3, 2.5, 1.2), stone)
	_box(g, "Fire", Vector3(-20, 0.5, -5.75), Vector3(1.4, 0.6, 0.2), _emissive(Color(1.0, 0.45, 0.12), 6.0), false)
	_light(g, "FireLight", Vector3(-20, 1.0, -5.0), Color(1.0, 0.55, 0.25), 4.0, 9.0, 0.3)

	# Стойка и бочки.
	_box(g, "BarCounter", Vector3(-11, 0.55, -4.8), Vector3(5, 1.1, 1), dark_wood)
	_box(g, "BarShelf", Vector3(-11, 1.6, -6.7), Vector3(5, 3.2, 0.6), dark_wood)
	for i in 3:
		_cylinder(g, "Barrel%d" % i, Vector3(-8.9 - i * 0.9, 0.5, -6.2), 0.4, 1.0, dark_wood)
	_light(g, "BarLamp", Vector3(-11, 2.2, -4.0), Color(1.0, 0.7, 0.4), 1.5, 5.0, 0.1)

	# Столы со свечами.
	var tables := [Vector3(-18, 0.4, 1.5), Vector3(-13, 0.4, 2.5), Vector3(-15.5, 0.4, -2.0)]
	for i in tables.size():
		var t := _box(g, "Table%d" % i, tables[i], Vector3(1.6, 0.8, 1.0), dark_wood)
		_cylinder(t, "Candle", Vector3(0, 0.52, 0), 0.05, 0.25, _emissive(Color(1, 0.8, 0.55), 4.0), false)
		# Без теней: иначе столешница отбрасывает на пол огромный тёмный прямоугольник.
		_light(t, "CandleLight", Vector3(0, 0.85, 0), Color(1, 0.62, 0.3), 1.6, 5.0, 0.25, false)


# --- Каменный Рубеж (x от -8 до 8) --------------------------------------------

func _build_rubezh() -> void:
	var g := _group("Rubezh")
	var stone := _mat(Color("4a5058"))
	var dark_stone := _mat(Color("3c434c"))
	var moss := _mat(Color("3e5a3a"))
	var puddle := _mat(Color("151a20"), 0.05, 0.6)

	_box(g, "Floor", Vector3(0, -0.1, 0), Vector3(16, 0.2, DEPTH), stone)
	_box(g, "BackWall", Vector3(0, 3, -7.3), Vector3(16, 6, 0.6), dark_stone)

	# Колонны у стены и обломки колонн спереди — они попадут в размытый передний план.
	for i in 4:
		var x := -6.0 + i * 4.0
		_box(g, "PillarBack%d" % i, Vector3(x, 2.5, -5.8), Vector3(1, 5, 1), dark_stone)
		_box(g, "Moss%d" % i, Vector3(x, 0.3, -5.25), Vector3(1.05, 0.6, 0.1), moss, false)
	for i in 2:
		_box(g, "BrokenPillar%d" % i, Vector3(-3.0 + i * 6.0, 0.6, 6.3), Vector3(1, 1.2, 1), dark_stone)

	# Холодные факелы на стене.
	for i in 3:
		var x := -4.0 + i * 4.0
		_box(g, "TorchFlame%d" % i, Vector3(x, 2.2, -6.85), Vector3(0.2, 0.3, 0.2), _emissive(Color(0.6, 0.75, 1.0), 5.0), false)
		_light(g, "TorchLight%d" % i, Vector3(x, 2.2, -6.3), Color(0.55, 0.7, 1.0), 2.2, 9.0, 0.15)

	# Лужи от капающей воды.
	_box(g, "Puddle0", Vector3(-2, 0.005, 1.5), Vector3(2.2, 0.01, 1.4), puddle, false)
	_box(g, "Puddle1", Vector3(4, 0.005, -2.0), Vector3(1.6, 0.01, 1.2), puddle, false)
	# Ящики.
	_box(g, "Crate0", Vector3(6, 0.4, -4.5), Vector3(0.8, 0.8, 0.8), _mat(Color("4a3a2a")))
	_box(g, "Crate1", Vector3(6.6, 0.3, -3.6), Vector3(0.6, 0.6, 0.6), _mat(Color("4a3a2a")))


# --- Озеро Тихой Воды (x от 8) -------------------------------------------------

func _build_lake() -> void:
	var g := _group("Lake")
	var shore := _mat(Color("2a2630"))
	var water := _mat(Color("2a1a40"), 0.02, 0.8)
	var pier := _mat(Color("3a2e2a"))
	var crystal := _emissive(Color(0.7, 0.35, 1.0), 2.0)

	_box(g, "Shore", Vector3(12, -0.1, 0), Vector3(8, 0.2, DEPTH), shore)
	_box(g, "Water", Vector3(28, -0.25, 0), Vector3(24, 0.1, DEPTH), water, false)
	_box(g, "Pier", Vector3(22, -0.1, 0), Vector3(12, 0.2, 2.5), pier)

	# Круг печати на конце причала.
	_cylinder(g, "SealCircle", Vector3(27, 0.02, 0), 1.1, 0.04, _mat(Color("101014"), 0.4), false)
	_cylinder(g, "SealRim", Vector3(27, 0.01, 0), 1.25, 0.02, _emissive(Color(0.55, 0.25, 0.9), 3.0), false)
	_light(g, "SealLight", Vector3(27, 0.8, 0), Color(0.6, 0.3, 1.0), 2.0, 6.0, 0.1, false)

	# Фонари душ вдоль причала.
	for i in 3:
		var pos := Vector3(18 + i * 3.5, 0, 1.15 if i % 2 == 0 else -1.15)
		_box(g, "LanternPost%d" % i, pos + Vector3(0, 0.6, 0), Vector3(0.12, 1.2, 0.12), pier, false)
		_box(g, "LanternGlow%d" % i, pos + Vector3(0, 1.3, 0), Vector3(0.25, 0.3, 0.25), _emissive(Color(0.75, 0.6, 1.0), 3.0), false)
		_light(g, "LanternLight%d" % i, pos + Vector3(0, 1.4, 0), Color(0.7, 0.55, 1.0), 1.6, 6.0, 0.1)

	# Кристаллы на берегу.
	var crystals := [Vector3(10, 0, -5), Vector3(13.5, 0, -6), Vector3(11, 0, 4.5), Vector3(14.5, 0, 5.5)]
	for i in crystals.size():
		var mesh := PrismMesh.new()
		mesh.size = Vector3(0.6, 1.4, 0.6)
		mesh.material = crystal
		var mi := MeshInstance3D.new()
		mi.name = "Crystal%d" % i
		mi.mesh = mesh
		mi.position = crystals[i] + Vector3(0, 0.7, 0)
		_add(mi, g)
		_light(g, "CrystalLight%d" % i, crystals[i] + Vector3(0, 1.2, 0), Color(0.65, 0.35, 1.0), 1.2, 5.0, 0.0, false)


# --- Границы ------------------------------------------------------------------

func _build_bounds() -> void:
	var g := _group("Bounds")
	var walls := {
		"North": [Vector3(4, 1.5, -7.6), Vector3(56, 3, 0.4)],
		"South": [Vector3(4, 1.5, 7.2), Vector3(56, 3, 0.4)],
		"West": [Vector3(-24.6, 1.5, 0), Vector3(0.4, 3, DEPTH)],
		# Кромка берега, кроме прохода на причал.
		"ShoreNorth": [Vector3(16.2, 1.5, -4.1), Vector3(0.4, 3, 5.7)],
		"ShoreSouth": [Vector3(16.2, 1.5, 4.1), Vector3(0.4, 3, 5.7)],
		# Борта и конец причала.
		"PierNorth": [Vector3(22, 1.5, -1.45), Vector3(12, 3, 0.4)],
		"PierSouth": [Vector3(22, 1.5, 1.45), Vector3(12, 3, 0.4)],
		"PierEnd": [Vector3(28.2, 1.5, 0), Vector3(0.4, 3, 2.5)],
	}
	for wall_name in walls:
		var body := StaticBody3D.new()
		body.name = wall_name
		body.position = walls[wall_name][0]
		_add(body, g)
		var shape := BoxShape3D.new()
		shape.size = walls[wall_name][1]
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		cs.shape = shape
		_add(cs, body)


# --- Игрок, камера, HUD --------------------------------------------------------

func _build_player_and_camera() -> void:
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector3(-16, 0, 4.5)
	var skins: Array[Texture2D] = [
		load("res://assets/sprites/ray/ray_combat.png"),
		load("res://assets/sprites/velmor/velmor_combat.png"),
		load("res://assets/sprites/liara/liara_combat.png"),
	]
	player.set("debug_skins", skins)
	player.set("debug_skin_names", PackedStringArray(["Рэй", "Вельмор", "Лиара"]))
	_add(player)

	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 16.0
	attrs.dof_blur_far_transition = 6.0
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = 9.0
	attrs.dof_blur_near_transition = 3.0
	attrs.dof_blur_amount = 0.12

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 30.0
	cam.attributes = attrs
	var cam_pos := player.position + Vector3(0, 9, 11)
	cam.transform = Transform3D(Basis.looking_at(player.position - cam_pos, Vector3.UP), cam_pos)
	cam.set_script(load("res://scripts/camera/diorama_camera.gd"))
	cam.set("target_path", NodePath("../Player"))
	_add(cam)


# --- Навигация врагов -----------------------------------------------------------

## Навигационная сетка по коллизиям зон (пол, стены, мебель) — враги обходят препятствия.
## Запекается здесь и сохраняется в сцене: для запекания карту ненадолго ставим в дерево.
func _bake_navigation() -> void:
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav.geometry_source_group_name = &"navigation_geometry"
	# Кратно размеру ячейки 0,25 — иначе движок округляет с предупреждением.
	nav.agent_radius = 0.5
	nav.agent_height = 1.5
	nav.agent_max_climb = 0.25
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	# Разбор геометрии требует узлов в дереве; вся карта со скриптами туда не ставится
	# (запустились бы _ready HUD, врагов и меню) — ставим копию одних зон.
	var geometry := Node3D.new()
	for zone in ["Tavern", "Rubezh", "Lake", "Bounds"]:
		var copy := map_root.get_node(zone).duplicate()
		copy.add_to_group("navigation_geometry")
		geometry.add_child(copy)
	root.add_child(geometry)
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, source, geometry)
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	root.remove_child(geometry)
	geometry.free()
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = nav
	_add(region)
	print("навигация: вершин ", nav.vertices.size(), ", полигонов ", nav.get_polygon_count())


# --- Бой: враги, чучело, фонари душ, цикл смерти (COMBAT_SPEC) ------------------

func _build_combat() -> void:
	var g := _group("Combat")
	# Тренировочное чучело — в таверне, у стойки.
	_actor(g, "TrainingDummy", "res://scripts/combat/training_dummy.gd", Vector3(-10, 0, 1.0))
	# Утопшие солдаты — в Каменном Рубеже.
	_actor(g, "DrownedSoldier0", "res://scripts/combat/drowned_soldier.gd", Vector3(2, 0, -2))
	_actor(g, "DrownedSoldier1", "res://scripts/combat/drowned_soldier.gd", Vector3(5, 0, 2.5))
	# Твари Тихой Воды — на берегу озера.
	_actor(g, "LakeCreature0", "res://scripts/combat/lake_creature.gd", Vector3(12, 0, -2.5))
	_actor(g, "LakeCreature1", "res://scripts/combat/lake_creature.gd", Vector3(13.5, 0, 2.5))
	# Фонари душ: на входе в Рубеж и на берегу озера.
	for spot in [["SoulLanternRubezh", Vector3(-6, 0, 3.5)], ["SoulLanternLake", Vector3(9.5, 0, 3.0)]]:
		var lantern := Node3D.new()
		lantern.name = spot[0]
		lantern.set_script(load("res://scripts/combat/soul_lantern.gd"))
		lantern.position = spot[1]
		_add(lantern, g)
	# Цикл смерти — после фонарей: при запуске подписывается на их зажжение.
	var cycle := CanvasLayer.new()
	cycle.name = "DeathCycle"
	cycle.set_script(load("res://scripts/combat/death_cycle.gd"))
	cycle.set("player_path", NodePath("../Player"))
	_add(cycle)


func _actor(parent: Node, node_name: String, script_path: String, pos: Vector3) -> void:
	var body := CharacterBody3D.new()
	body.name = node_name
	body.set_script(load(script_path))
	body.position = pos
	_add(body, parent)


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
	label.position = Vector2(6, 44)  # под кнопками меню HUD
	label.add_theme_color_override("font_outline_color", Color("2a1e18"))
	label.add_theme_constant_override("outline_size", 2)
	label.set_script(load("res://scripts/ui/debug_hud.gd"))
	label.set("player_path", NodePath("../../../Player"))
	label.set("atmosphere_path", NodePath("../../../Atmosphere"))
	_add(label, scaler)

	var map_res := load("res://tests/test_arena_map.tres")
	var book := CanvasLayer.new()
	book.name = "Book"
	book.set_script(load("res://scripts/ui/book/book.gd"))
	book.set("map", map_res)
	book.set("player_path", NodePath("../Player"))
	_add(book)

	var tracker := Node.new()
	tracker.name = "MapTracker"
	tracker.set_script(load("res://scripts/journal/map_tracker.gd"))
	tracker.set("map", map_res)
	tracker.set("player_path", NodePath("../Player"))
	_add(tracker)

	var pause := CanvasLayer.new()
	pause.name = "PauseMenu"
	pause.set_script(load("res://scripts/ui/pause_menu.gd"))
	_add(pause)

	var keys := Node.new()
	keys.name = "DebugKeys"
	keys.set_script(load("res://scripts/debug/debug_keys.gd"))
	_add(keys)
