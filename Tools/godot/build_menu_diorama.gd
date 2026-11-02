extends SceneTree
## Собирает диораму главного меню (UI_SPEC, раздел 5): ночной Каменный Рубеж над озером,
## таверна Ивового Брода со светящимся окном, причал с фонарями душ. Блокаут из примитивов.
## Запуск: Game/Godot_v4.7.2-stable_win64_console.exe --headless --path Game/CatsSoulDebt -s Tools/godot/build_menu_diorama.gd

const OUT := "res://scenes/levels/menu_diorama.tscn"

var map_root: Node3D


func _initialize() -> void:
	map_root = Node3D.new()
	map_root.name = "MenuDiorama"
	_environment()
	_lake()
	_fortress()
	_tavern()
	_pier()
	_camera()
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


func _mat(color: Color, roughness := 0.9, metallic := 0.0) -> StandardMaterial3D:
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


func _box(node_name: String, pos: Vector3, size: Vector3, material: Material, parent: Node = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	_add(mi, parent)
	return mi


func _light(node_name: String, pos: Vector3, color: Color, energy: float, light_range: float, flicker := 0.0, parent: Node = null) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = node_name
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	if flicker > 0.0:
		l.set_script(load("res://scripts/environment/flicker_light.gd"))
		l.set("strength", flicker)
	_add(l, parent)
	return l


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("06070f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.3, 0.5)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.2
	env.glow_bloom = 0.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.1, 0.2)
	env.fog_density = 0.018
	env.ssr_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(we)

	# Лунный свет: холодный, слабый, без теней.
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.6, 0.9)
	moon.light_energy = 0.35
	moon.rotation_degrees = Vector3(-35, 30, 0)
	_add(moon)
	# Луна на небе.
	var disc := MeshInstance3D.new()
	disc.name = "MoonDisc"
	var sphere := SphereMesh.new()
	sphere.radius = 1.6
	sphere.height = 3.2
	sphere.material = _emissive(Color(0.85, 0.88, 1.0), 2.0)
	disc.mesh = sphere
	disc.position = Vector3(14, 16, -40)
	_add(disc)


func _lake() -> void:
	_box("Lake", Vector3(0, -0.3, -10), Vector3(90, 0.2, 40), _mat(Color("161a2e"), 0.03, 0.85))
	_box("Shore", Vector3(0, -0.15, 6), Vector3(90, 0.3, 10), _mat(Color("2a2a30")))


func _fortress() -> void:
	# Каменный Рубеж на дальнем берегу: стена, башни с зубцами, ворота, редкие холодные огни.
	var g := Node3D.new()
	g.name = "Rubezh"
	_add(g)
	var stone := _mat(Color("2c3038"))
	var dark := _mat(Color("1c1f26"))
	_box("Cliff", Vector3(0, 1.5, -26), Vector3(50, 4, 6), dark, g)
	_box("Wall", Vector3(0, 5.5, -26), Vector3(30, 5, 2), stone, g)
	for i in 8:
		_box("Merlon%d" % i, Vector3(-13 + i * 3.7, 8.4, -26), Vector3(1.4, 0.8, 2), stone, g)
	for x in [-15.0, 15.0, -5.0, 5.0]:
		var h := 11.0 if absf(x) > 10 else 9.0
		_box("Tower%d" % int(x), Vector3(x, 3.5 + h / 2.0, -26), Vector3(3.2, h, 3.2), stone, g)
		for k in 3:
			_box("TowerMerlon%d_%d" % [int(x), k], Vector3(x - 1.1 + k * 1.1, 3.5 + h + 0.4, -26), Vector3(0.6, 0.8, 3.2), stone, g)
	_box("Gate", Vector3(0, 4.6, -24.95), Vector3(3, 3.2, 0.1), _mat(Color("0c0d10")), g)
	for p in [Vector3(-15, 10, -24.3), Vector3(5, 9, -24.3), Vector3(-5, 7, -24.9)]:
		_box("Window", p, Vector3(0.5, 0.8, 0.1), _emissive(Color(0.55, 0.7, 1.0), 4.0), g)
		_light("ColdLight", p + Vector3(0, 0, 1), Color(0.55, 0.7, 1.0), 1.5, 8.0, 0.1)


func _tavern() -> void:
	# Таверна Ивового Брода на ближнем берегу: дом, красная черепица, тёплое мерцающее окно.
	var g := Node3D.new()
	g.name = "Tavern"
	g.position = Vector3(-6.5, 0, 0.5)
	g.rotation_degrees = Vector3(0, 28, 0)
	_add(g)
	_box("House", Vector3(0, 1.5, 0), Vector3(5, 3, 4), _mat(Color("4a3424")), g)
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var prism := PrismMesh.new()
	prism.size = Vector3(5.6, 2, 4.4)
	prism.material = _mat(Color("7a2a24"))
	roof.mesh = prism
	roof.position = Vector3(0, 4, 0)
	_add(roof, g)
	_box("Chimney", Vector3(1.6, 4.6, -0.8), Vector3(0.6, 1.6, 0.6), _mat(Color("5a4a40")), g)
	for x in [-1.3, 1.3]:
		_box("Window", Vector3(x, 1.6, 2.01), Vector3(0.9, 0.9, 0.05), _emissive(Color(1.0, 0.62, 0.28), 5.0), g)
	_box("Door", Vector3(0, 0.8, 2.01), Vector3(0.9, 1.6, 0.05), _mat(Color("2e1d14")), g)
	_light("WindowLight", Vector3(-1.3, 1.7, 2.8), Color(1.0, 0.6, 0.3), 3.0, 8.0, 0.25, g)
	_light("WindowLight2", Vector3(1.3, 1.7, 2.8), Color(1.0, 0.6, 0.3), 2.0, 6.0, 0.25, g)


func _pier() -> void:
	var wood := _mat(Color("3a2e2a"))
	_box("Pier", Vector3(3, -0.05, -3), Vector3(2.2, 0.2, 10), wood)
	for i in 3:
		var p := Vector3(3 + (1.0 if i % 2 == 0 else -1.0), 0, 0.5 - i * 3.5)
		_box("LanternPost%d" % i, p + Vector3(0, 0.6, 0), Vector3(0.12, 1.2, 0.12), wood)
		_box("LanternGlow%d" % i, p + Vector3(0, 1.3, 0), Vector3(0.25, 0.3, 0.25), _emissive(Color(0.75, 0.6, 1.0), 4.0))
		_light("LanternLight%d" % i, p + Vector3(0, 1.4, 0), Color(0.7, 0.55, 1.0), 1.8, 6.0, 0.1)


func _camera() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 40.0
	var pos := Vector3(2, 4.5, 14)
	var target := Vector3(0, 3, -12)
	cam.transform = Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)
	cam.set_script(load("res://scripts/camera/menu_camera.gd"))
	cam.set("look_target", target)
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = 6.0
	attrs.dof_blur_near_transition = 3.0
	attrs.dof_blur_amount = 0.08
	cam.attributes = attrs
	_add(cam)
