extends SceneTree
## Собирает игровую сцену этажа Рубежа из серых блоков Blender (assets/levels/rubezh_<этаж>.glb):
## атмосфера, свет по залам, Рэй у ворот, враги и фонари на точках spawn-*, метки будущих сундуков
## и ключей, интерфейс, цикл смерти, навигация для врагов. Результат — scenes/levels/rubezh_<этаж>.tscn.
## Запуск: Godot_console --headless --path Game/CatsSoulDebt -s <абсолютный путь к этому файлу>
## Геометрию меняют в Blender (Tools/blender/build_greybox.py), потом пересобирают эту сцену.

const FLOOR := "f1"
const GLB := "res://assets/levels/rubezh_%s.glb" % FLOOR
const PROPS_GLB := "res://assets/levels/rubezh_%s_props.glb" % FLOOR
const OUT := "res://scenes/levels/rubezh_%s.tscn" % FLOOR
const TORCH_COLOR := Color(0.55, 0.7, 1.0)

var map_root: Node3D


func _initialize() -> void:
	# После первого кадра: запекание навигации требует работающего дерева.
	_build.call_deferred()


func _build() -> void:
	await process_frame
	map_root = Node3D.new()
	map_root.name = "Rubezh" + FLOOR.to_upper()
	map_root.set_script(load("res://scripts/levels/rubezh_level.gd"))

	var geometry_scene: PackedScene = load(GLB)
	var geometry := geometry_scene.instantiate()
	geometry.name = "Geometry"
	_add(geometry)
	# Детали KayKit (Tools/blender/rubezh_props.py): мебель, факелы, колонны; одевает скрипт уровня.
	if ResourceLoader.exists(PROPS_GLB):
		var props := (load(PROPS_GLB) as PackedScene).instantiate()
		props.name = "Props"
		_add(props)
		# Огонь факелов и свечей по пустышкам fx-* из rubezh_props.py.
		var ambience := Node3D.new()
		ambience.name = "Ambience"
		ambience.set_script(load("res://scripts/environment/ambience.gd"))
		ambience.set("outdoor", false)
		ambience.set("dungeon", true)
		ambience.set("player_path", NodePath("../Player"))
		ambience.set("geometry_path", NodePath("../Props"))
		_add(ambience)
	var rooms: Array[Node3D] = []
	var spawns: Array[Node3D] = []
	for c in geometry.get_children():
		if String(c.name).begins_with("room-"):
			rooms.append(c)
		elif String(c.name).begins_with("spawn-"):
			spawns.append(c)

	_build_environment()
	_build_lights(rooms)
	var gate := rooms.filter(func(r): return String(r.name) == "room-gate")[0] as Node3D
	_build_player_and_camera(gate.position + Vector3(0, 0, 3.0))
	_build_spawns(spawns)
	_build_exit_to_village(gate)
	# Финал Главы 1 — в центре Большого зала (у круга печати).
	var great := rooms.filter(func(r): return String(r.name) == "room-great")
	if not great.is_empty():
		var finale := Node3D.new()
		finale.name = "Chapter1Finale"
		finale.set_script(load("res://scripts/levels/chapter1_finale.gd"))
		finale.position = (great[0] as Node3D).position
		_add(finale)
	_build_hud()
	_bake_navigation(geometry_scene)
	map_root.set("player_path", NodePath("Player"))
	map_root.set("geometry_path", NodePath("Geometry"))

	var scene := PackedScene.new()
	var err := scene.pack(map_root)
	if err == OK:
		err = ResourceSaver.save(scene, OUT)
	print("сохранено: ", OUT, " (код ", err, "), залов ", rooms.size(), ", точек ", spawns.size())
	map_root.free()
	quit(err)


func _add(node: Node, parent: Node = null) -> Node:
	(parent if parent else map_root).add_child(node)
	node.owner = map_root
	return node


func _extras(n: Node) -> Dictionary:
	return n.get_meta("extras", {})


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_bloom = 0.15
	env.fog_enabled = true
	env.adjustment_enabled = true
	var blender: WorldEnvironment = load("res://scripts/environment/atmosphere_blender.gd").new()
	blender.name = "Atmosphere"
	blender.environment = env
	blender.set("target_path", NodePath("../Player"))
	var p := AtmospherePreset.new()
	p.zone_name = "Каменный Рубеж"
	p.start_x = -1000.0
	p.background_color = Color("0a0e14")
	p.ambient_color = Color(0.38, 0.45, 0.58)
	p.ambient_energy = 0.42
	p.fog_color = Color(0.12, 0.16, 0.22)
	p.fog_density = 0.01
	p.glow_intensity = 0.6
	p.saturation = 0.7
	var presets: Array[AtmospherePreset] = [p]
	blender.set("presets", presets)
	_add(blender)


## Холодные факелы у северной стены каждого зала, тусклые огни в длинных коридорах.
func _build_lights(rooms: Array[Node3D]) -> void:
	var g := Node3D.new()
	g.name = "Lights"
	_add(g)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = TORCH_COLOR
	flame_mat.emission_enabled = true
	flame_mat.emission = TORCH_COLOR
	flame_mat.emission_energy_multiplier = 5.0
	for r in rooms:
		var e := _extras(r)
		var w: float = e.get("w", 6.0)
		var h: float = e.get("h", 6.0)
		var tags: String = e.get("tags", "")
		var rid := String(r.name).trim_prefix("room-")
		if "corridor" in tags:
			if maxf(w, h) >= 10.0:
				_light(g, "Corridor_" + rid, r.position + Vector3(0, 2.4, 0), 1.0, 7.0, false)
			continue
		if "bridge" in tags:
			continue
		var count := 2 if w >= 18.0 else 1
		for i in count:
			var x := 0.0 if count == 1 else (-w / 4.0 if i == 0 else w / 4.0)
			var pos := r.position + Vector3(x, 2.6, -h / 2.0 + 0.6)
			_light(g, "Torch_%s_%d" % [rid, i], pos, 2.6, maxf(w, h) * 0.8, true)
			# С деталями KayKit огонь дают настоящие факелы (Ambience, точки fx-torch) — кубик не нужен.
			if ResourceLoader.exists(PROPS_GLB):
				continue
			var flame := MeshInstance3D.new()
			flame.name = "Flame_%s_%d" % [rid, i]
			var box := BoxMesh.new()
			box.size = Vector3(0.2, 0.3, 0.2)
			box.material = flame_mat
			flame.mesh = box
			flame.position = pos + Vector3(0, -0.2, -0.3)
			_add(flame, g)


func _light(parent: Node, node_name: String, pos: Vector3, energy: float, light_range: float, flicker: bool) -> void:
	var l := OmniLight3D.new()
	l.name = node_name
	l.position = pos
	l.light_color = TORCH_COLOR
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	# Общий свет зала не должен светиться «шаром» в тумане: видимый огонь — у факелов (Ambience).
	l.light_volumetric_fog_energy = 0.2
	if flicker:
		l.set_script(load("res://scripts/environment/flicker_light.gd"))
		l.set("strength", 0.15)
	_add(l, parent)


func _build_player_and_camera(start: Vector3) -> void:
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	player.position = start
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
	var cam_pos := start + Vector3(0, 9, 11)
	cam.transform = Transform3D(Basis.looking_at(start - cam_pos, Vector3.UP), cam_pos)
	cam.set_script(load("res://scripts/camera/diorama_camera.gd"))
	cam.set("target_path", NodePath("../Player"))
	_add(cam)


## Точки spawn-* из Blender: фонари и враги — настоящие, остальное — метки до своих систем.
func _build_spawns(spawns: Array[Node3D]) -> void:
	var g := Node3D.new()
	g.name = "Combat"
	_add(g)
	var markers := Node3D.new()
	markers.name = "Markers"
	_add(markers)
	for s in spawns:
		var e := _extras(s)
		var kind: String = e.get("kind", "")
		var label: String = e.get("label", "")
		var n: Node3D
		match kind:
			"lantern":
				n = Node3D.new()
				n.set_script(load("res://scripts/combat/soul_lantern.gd"))
				n.name = "SoulLantern_" + String(s.name).get_slice("-", 2)
			"enemy":
				n = CharacterBody3D.new()
				n.set_script(load("res://scripts/combat/drowned_soldier.gd"))
				n.name = "Drowned_" + String(s.name).get_slice("-", 2)
			"creature":
				n = CharacterBody3D.new()
				n.set_script(load("res://scripts/combat/lake_creature.gd"))
				n.name = "Creature_" + String(s.name).get_slice("-", 2)
			"kvald", "kobold", "golem":
				# Новые враги (COMBAT_SPEC 3а). Кобольды одной комнаты — одна стая: pack_id по ближайшему центру комнаты.
				n = CharacterBody3D.new()
				n.set_script(load({"kvald": "res://scripts/combat/kvald.gd", "kobold": "res://scripts/combat/kobold.gd",
					"golem": "res://scripts/combat/mine_golem.gd"}[kind]))
				n.name = "%s_%s" % [kind.capitalize(), String(s.name).get_slice("-", 2)]
				if kind == "kobold":
					n.set("pack_id", "pack_%d_%d" % [roundi(s.position.x / 10.0), roundi(s.position.z / 10.0)])
				elif kind == "golem" and label == "boss":
					n.set("boss", true)
			"chest":
				n = Node3D.new()
				n.set_script(load("res://scripts/levels/chest.gd"))
				n.name = "Chest_" + String(s.name).get_slice("-", 2)
				n.set("contents", label)
				n.set("persist_id", "%s:%s" % [OUT, n.name])
			"soul", "item" when ContentDB.soul(label) != null or ContentDB.item(label) != null:
				# Сюжетные находки Главы 1: подпись метки — id души или предмета (rubezh_layout.py).
				n = Node3D.new()
				n.set_script(load("res://scripts/levels/story_pickup.gd"))
				n.name = "Story_" + label
				n.set("kind", kind)
				n.set("content_id", StringName(label))
				n.set("persist_id", "%s:%s" % [OUT, n.name])
			"key", "bigkey":
				n = Area3D.new()
				n.set_script(load("res://scripts/levels/key_pickup.gd"))
				n.name = "%s_%s" % [kind.capitalize(), String(s.name).get_slice("-", 2)]
				n.set("key_label", label)
				n.set("persist_id", "%s:%s" % [OUT, n.name])
			_:
				n = Node3D.new()
				n.set_script(load("res://scripts/levels/level_marker.gd"))
				n.set("kind", kind)
				n.set("label", label)
				n.name = "%s_%s" % [kind.capitalize(), String(s.name).get_slice("-", 2)]
				n.position = s.position
				_add(n, markers)
				continue
		n.position = s.position
		_add(n, g)
	# Цикл смерти — после фонарей: при запуске подписывается на их зажжение.
	var cycle := CanvasLayer.new()
	cycle.name = "DeathCycle"
	cycle.set_script(load("res://scripts/combat/death_cycle.gd"))
	cycle.set("player_path", NodePath("../Player"))
	_add(cycle)


## У южного края ворот — лестница наверх, в Ивовый Брод (к обрыву у таверны).
func _build_exit_to_village(gate: Node3D) -> void:
	# Мир вокруг Брода: перед воротами крепости, на мосту (ворота смотрят на юг, +z).
	const VILLAGE := "res://scenes/levels/world.tscn"
	var arrival := Vector3(0, 10, 0)
	if ResourceLoader.exists("res://assets/levels/world.glb"):
		var world: Node3D = (load("res://assets/levels/world.glb") as PackedScene).instantiate()
		var world_gate := world.get_node_or_null("poi-rubezh-gate") as Node3D
		if world_gate:
			arrival = world_gate.position + Vector3(0, 0.5, 7.0)
		world.free()
	var exit := Area3D.new()
	exit.name = "ExitToVillage"
	exit.set_script(load("res://scripts/levels/level_exit.gd"))
	exit.set("target_scene", VILLAGE)
	exit.set("target_position", arrival)
	exit.set("size", Vector3(10, 3, 1.5))
	exit.set("label", "↑ к воротам, в долину")
	exit.position = gate.position + Vector3(0, 0, 4.3)
	_add(exit)


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
	# Карта места в журнале (Tools/journal_maps.py) и отметки исследованного по ходу Рэя.
	var journal_map: Resource = load("res://data/maps/rubezh_%s.tres" % FLOOR)
	book.set("map", journal_map)
	var tracker := Node.new()
	tracker.name = "MapTracker"
	tracker.set_script(load("res://scripts/journal/map_tracker.gd"))
	tracker.set("map", journal_map)
	tracker.set("player_path", NodePath("../Player"))
	_add(tracker)
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


## Навигация по коллизиям серых блоков (двери тоже преграда — пока они закрыты).
func _bake_navigation(geometry_scene: PackedScene) -> void:
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.agent_radius = 0.5
	nav.agent_height = 1.5
	nav.agent_max_climb = 0.25
	nav.agent_max_slope = 30.0
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	var temp := geometry_scene.instantiate()
	if ResourceLoader.exists(PROPS_GLB):
		temp.add_child((load(PROPS_GLB) as PackedScene).instantiate())
	root.add_child(temp)
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, source, temp)
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	root.remove_child(temp)
	temp.free()
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = nav
	_add(region)
	print("навигация: полигонов ", nav.get_polygon_count())
