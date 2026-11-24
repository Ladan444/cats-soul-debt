extends SceneTree
## Собирает арену баланса M01 («гимн боя»): площадка, Рэй, манекен, руна ударов и пульт.
## Сцена только для ручной настройки и автотеста: лежит в res://tests/ и в сборку не входит
## (exclude_filter="tests/*"). Запуск: powershell -File Tools/combat_gym.ps1
## После пересборки ручные правки сцены теряются — менять арену здесь.

const OUT := "res://tests/combat_gym.tscn"
const FLOOR := "res://assets/textures/rubezh/rubezh_floor_flagstone.png"
const WALL := "res://assets/textures/rubezh/rubezh_wall_brick.png"

var gym: Node3D


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	await process_frame
	gym = Node3D.new()
	gym.name = "CombatGym"

	_build_arena()
	_build_environment()
	_build_player()
	_build_dummy()
	_build_striker()
	_build_ui()

	var scene := PackedScene.new()
	var err := scene.pack(gym)
	if err == OK:
		err = ResourceSaver.save(scene, OUT)
	print("сохранено: ", OUT, " (код ", err, ")")
	gym.free()
	quit(err)


func _add(node: Node, parent: Node = null) -> Node:
	(parent if parent else gym).add_child(node)
	node.owner = gym
	return node


func _texture(path: String, uv_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	m.roughness = 1.0
	return m


func _box(parent: Node, node_name: String, pos: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	_add(body, parent)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	_add(mi, body)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	cs.shape = shape
	_add(cs, body)
	return body


func _light(parent: Node, node_name: String, pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	_add(light, parent)
	return light


func _build_arena() -> void:
	var floor := _box(gym, "Floor", Vector3(0, -0.2, 0), Vector3(24, 0.4, 24), _texture(FLOOR, 6.0))
	floor.add_to_group("navigation_geometry")
	var wall_mat := _texture(WALL, 4.0)
	# Невысокие стены по краям: Рэй не уходит с площадки, но обзор открыт.
	_box(gym, "WallN", Vector3(0, 0.5, -12), Vector3(24, 1.4, 0.4), wall_mat)
	_box(gym, "WallS", Vector3(0, 0.5, 12), Vector3(24, 1.4, 0.4), wall_mat)
	_box(gym, "WallW", Vector3(-12, 0.5, 0), Vector3(0.4, 1.4, 24), wall_mat)
	_box(gym, "WallE", Vector3(12, 0.5, 0), Vector3(0.4, 1.4, 24), wall_mat)
	# Две колонны у манекена — ориентир и опора для света.
	var trim := _texture("res://assets/textures/rubezh/rubezh_stone_trim.png", 2.0)
	for x in [-2.4, 2.4]:
		_box(gym, "Pillar%s" % ("W" if x < 0 else "E"), Vector3(x, 1.4, -1.4), Vector3(0.7, 2.8, 0.7), trim)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("12151d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6a7080")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color("1a2030")
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	_add(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color("c8d0e0")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	_add(sun)

	_light(gym, "PillarLightW", Vector3(-2.4, 2.2, -1.4), Color("e8a04a"), 2.0, 7.0)
	_light(gym, "PillarLightE", Vector3(2.4, 2.2, -1.4), Color("e8a04a"), 2.0, 7.0)
	# Тёплый свет над площадкой: синий камень не съедает силуэты Рэя и манекена.
	_light(gym, "ArenaLight", Vector3(0, 2.6, 3.2), Color("e8c890"), 1.4, 9.0)


func _build_player() -> void:
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0, 3.6)
	_set_skins(player)
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
	cam.current = true
	cam.set_script(load("res://scripts/camera/diorama_camera.gd"))
	cam.set("target_path", NodePath("../Player"))
	_add(cam)


func _set_skins(player: Node) -> void:
	var skins: Array[Texture2D] = [
		load("res://assets/sprites/ray/ray_combat.png"),
		load("res://assets/sprites/velmor/velmor_combat.png"),
		load("res://assets/sprites/liara/liara_combat.png"),
	]
	player.set("debug_skins", skins)
	player.set("debug_skin_names", PackedStringArray(["Рэй", "Вельмор", "Лиара"]))


func _build_dummy() -> void:
	var dummy := CharacterBody3D.new()
	dummy.name = "Dummy"
	dummy.position = Vector3(0, 0, 0)
	dummy.set_script(load("res://scripts/debug/gym_dummy.gd"))
	_add(dummy)


func _build_striker() -> void:
	var striker := Node3D.new()
	striker.name = "Striker"
	striker.position = Vector3(-2.4, 0, 2.2)
	striker.set_script(load("res://scripts/debug/gym_striker.gd"))
	_add(striker)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	_add(layer)
	var scaler: Control = load("res://scripts/ui/ui_scaler.gd").new()
	scaler.name = "UIScaler"
	_add(scaler, layer)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_script(load("res://scripts/debug/gym_panel.gd"))
	_add(panel, scaler)
