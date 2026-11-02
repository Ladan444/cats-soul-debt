extends SceneTree
## Собирает сцену таверны внутри из Blender (assets/levels/tavern.glb, Tools/blender/build_tavern.py):
## тёплый свет камина и свечей, Рэй у кровати (начало новой игры), граф Вельмор за стойкой,
## выход на площадь Брода, интерфейс. Результат — scenes/levels/tavern.tscn.
## Запуск: Godot_console --headless --path Game/CatsSoulDebt -s <абсолютный путь к этому файлу>

const GLB := "res://assets/levels/tavern.glb"
const OUT := "res://scenes/levels/tavern.tscn"
const VILLAGE := "res://scenes/levels/world.tscn"

var map_root: Node3D


func _initialize() -> void:
	map_root = Node3D.new()
	map_root.name = "Tavern"
	map_root.set_script(load("res://scripts/levels/tavern_level.gd"))
	var geometry: Node3D = (load(GLB) as PackedScene).instantiate()
	geometry.name = "Geometry"
	_add(geometry)
	var points := {}
	for c in geometry.get_children():
		if c is Node3D and not (c is MeshInstance3D):
			points[String(c.name)] = (c as Node3D).position
	_build_environment()
	_build_player_and_camera(points["spawn-start"])
	_build_velmor(points["npc-velmor"])
	var ambience := Node3D.new()
	ambience.name = "Ambience"
	ambience.set_script(load("res://scripts/environment/ambience.gd"))
	ambience.set("player_path", NodePath("../Player"))
	ambience.set("geometry_path", NodePath("../Geometry"))
	ambience.set("outdoor", false)
	_add(ambience)
	_build_exit(points["exit-village"])
	_build_hud()
	map_root.set("player_path", NodePath("Player"))
	map_root.set("geometry_path", NodePath("Geometry"))
	# Миникарта: снимок по коллизиям, комната видна сразу целиком.
	map_root.set_meta("minimap", {"zoom": 2.5, "reveal": false})
	var scene := PackedScene.new()
	var err := scene.pack(map_root)
	if err == OK:
		err = ResourceSaver.save(scene, OUT)
	print("сохранено: ", OUT, " (код ", err, "), точек ", points.size())
	map_root.free()
	quit(err)


func _add(node: Node, parent: Node = null) -> Node:
	(parent if parent else map_root).add_child(node)
	node.owner = map_root
	return node


## Тёплый полумрак (PROJECT_BIBLE: камин, свечи, уют обманчив): слабый фоновый свет, огонь — главный источник.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_bloom = 0.15
	env.fog_enabled = true
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.8
	env.adjustment_enabled = true
	var blender: WorldEnvironment = load("res://scripts/environment/atmosphere_blender.gd").new()
	blender.name = "Atmosphere"
	blender.environment = env
	blender.set("target_path", NodePath("../Player"))
	var p := AtmospherePreset.new()
	p.zone_name = "Таверна «Красная черепица»"
	p.hub = true
	p.start_x = -1000.0
	p.background_color = Color("140c08")
	# Фон — нейтрально-холодный: тепло дают только огонь и свечи, иначе дерево и побелка сливаются в оранжевое.
	p.ambient_color = Color(0.6, 0.6, 0.66)
	p.ambient_energy = 0.34
	p.fog_color = Color(0.2, 0.17, 0.15)
	p.fog_density = 0.01
	p.glow_intensity = 0.6
	p.saturation = 0.88
	var presets: Array[AtmospherePreset] = [p]
	blender.set("presets", presets)
	_add(blender)
	# Дневной свет из окон северной стены — чуть холоднее огня.
	var sun := DirectionalLight3D.new()
	sun.name = "WindowLight"
	sun.light_color = Color(0.9, 0.93, 1.0)
	sun.light_energy = 0.35
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-40, 160, 0)
	_add(sun)


func _build_player_and_camera(start: Vector3) -> void:
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	player.position = start + Vector3(0, 0.2, 0)
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
	attrs.dof_blur_far_distance = 18.0
	attrs.dof_blur_far_transition = 8.0
	attrs.dof_blur_amount = 0.08
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 30.0
	cam.attributes = attrs
	var cam_pos := start + Vector3(0, 9, 11)
	cam.transform = Transform3D(Basis.looking_at(start - cam_pos, Vector3.UP), cam_pos)
	cam.set_script(load("res://scripts/camera/diorama_camera.gd"))
	cam.set("target_path", NodePath("../Player"))
	_add(cam)


func _build_velmor(at: Vector3) -> void:
	var npc := Node3D.new()
	npc.name = "Velmor"
	npc.set_script(load("res://scripts/levels/velmor_npc.gd"))
	npc.set("sheet", load("res://assets/sprites/velmor/velmor_combat.png"))
	npc.position = at
	_add(npc)


func _build_exit(at: Vector3) -> void:
	# Мир вокруг Брода: у двери таверны (пустышка door-tavern), на 2 м от стены — наружу (к югу, +z).
	var world: Node3D = (load("res://assets/levels/world.glb") as PackedScene).instantiate()
	var porch: Vector3 = (world.get_node("door-tavern") as Node3D).position + Vector3(0, 0.4, 2.0)
	world.free()
	var exit := Area3D.new()
	exit.name = "ExitToVillage"
	exit.set_script(load("res://scripts/levels/level_exit.gd"))
	exit.set("target_scene", VILLAGE)
	exit.set("target_position", porch)
	exit.set("size", Vector3(3.0, 3.0, 0.8))
	exit.set("label", "↓ на площадь")
	exit.position = at
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
	var journal_map: Resource = load("res://data/maps/tavern.tres")
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
