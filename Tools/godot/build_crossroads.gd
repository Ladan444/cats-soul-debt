extends SceneTree
## Собирает сцену Перепутья и сохраняет в res://scenes/levels/crossroads.tscn.
## Запуск: Game/Godot_v4.7.2-stable_win64_console.exe --headless --path Game/CatsSoulDebt -s <абсолютный путь к этому файлу>
##
## CANON: «четыре дороги в тумане, столб с табличками, мёртвое дерево»; на перекрёстках хоронили тех,
## кого не принимали ни земля, ни церковь. Свет и палитра — [ПРЕДЛОЖЕНИЕ] (в PROJECT_BIBLE их не было):
## бледная луна сверху, серо-зелёный густой туман, пепельные дороги, чёрное дерево.
## Рэй появляется в конце южной дороги, Страж стоит у столба.

const OUT := "res://scenes/levels/crossroads.tscn"

var map_root: Node3D


func _initialize() -> void:
	map_root = Node3D.new()
	map_root.name = "Crossroads"
	map_root.set_script(load("res://scripts/levels/crossroads.gd"))

	_build_environment()
	_build_ground()
	_build_signpost()
	_build_tree_and_graves()
	_build_bounds()
	_build_actors()

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


func _mat(color: Color, roughness: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _box(parent: Node, node_name: String, pos: Vector3, size: Vector3, material: Material, rot := Vector3.ZERO, collide := false) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = rot
	_add(body, parent)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	_add(mi, body)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		_add(cs, body)
	return body


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.35, 0.33)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.6)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	# Туман по глубине: у перекрёстка воздух чистый, дороги уходят в сплошную пелену.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.3, 0.35, 0.33)
	env.fog_density = 1.0
	env.fog_depth_begin = 14.0
	env.fog_depth_end = 24.0
	env.fog_depth_curve = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.55
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	_add(we)
	# Бледная луна сверху-сзади: длинные тени дерева и столба тянутся к камере.
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.78, 0.84, 0.92)
	moon.light_energy = 0.7
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-55, 160, 0)
	_add(moon)


func _build_ground() -> void:
	var g := Node3D.new()
	g.name = "Ground"
	_add(g)
	_box(g, "Earth", Vector3(0, -0.1, 0), Vector3(40, 0.2, 40), _mat(Color("2a2723")), Vector3.ZERO, true)
	var road := _mat(Color("5a554c"))
	# Четыре дороги — крест, уходящий в туман.
	_box(g, "RoadNS", Vector3(0, 0.005, 0), Vector3(2.6, 0.01, 40), road)
	_box(g, "RoadEW", Vector3(0, 0.006, 0), Vector3(40, 0.01, 2.6), road)
	# Колея и камни по краям дорог.
	var stone := _mat(Color("6a665e"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 26:
		var along := rng.randf_range(-16, 16)
		var side := 1.5 * (1.0 if rng.randf() < 0.5 else -1.0)
		var pos := Vector3(side + rng.randf_range(-0.2, 0.2), 0.06, along) if i % 2 == 0 else Vector3(along, 0.06, side + rng.randf_range(-0.2, 0.2))
		if pos.length() < 2.5:
			continue
		var s := rng.randf_range(0.12, 0.3)
		_box(g, "Stone%d" % i, pos, Vector3(s, s * 0.6, s * 0.8), stone, Vector3(0, rng.randf_range(0, 90), 0))


func _build_signpost() -> void:
	var g := Node3D.new()
	g.name = "Signpost"
	g.position = Vector3(1.9, 0, -1.9)
	_add(g)
	var wood := _mat(Color("4a3a2c"))
	var board := _mat(Color("8a7a62"))
	_box(g, "Post", Vector3(0, 1.4, 0), Vector3(0.16, 2.8, 0.16), wood, Vector3.ZERO, true)
	# Таблички на четыре стороны; четвёртая стёрта — туда дороги нет.
	var signs := [["Брод", 0.0, 2.45], ["Рубеж", 90.0, 2.2], ["Тихая Вода", 180.0, 1.95], ["", 270.0, 1.7]]
	for i in signs.size():
		var yaw: float = signs[i][1]
		var dir := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
		var b := _box(g, "Board%d" % i, Vector3(0, signs[i][2], 0) + dir * 0.5, Vector3(0.9, 0.2, 0.05), board, Vector3(0, yaw + 90.0, -4.0 + i * 3.0))
		if signs[i][0] != "":
			var label := Label3D.new()
			label.name = "Text"
			label.text = signs[i][0]
			label.font = load("res://assets/fonts/public_pixel/PublicPixel.ttf")
			label.font_size = 16
			label.pixel_size = 0.008
			label.modulate = Color("2a1e18")
			label.outline_size = 0
			label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			label.position = Vector3(0, 0, 0.03)
			_add(label, b)


func _build_tree_and_graves() -> void:
	var g := Node3D.new()
	g.name = "DeadTree"
	g.position = Vector3(-3.4, 0, -3.2)
	_add(g)
	var bark := _mat(Color("161412"))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.32
	trunk.height = 3.4
	trunk.material = bark
	var mi := MeshInstance3D.new()
	mi.name = "Trunk"
	mi.mesh = trunk
	mi.position.y = 1.7
	_add(mi, g)
	# Голые ветви — наклонённые бруски.
	var branches := [[Vector3(0.4, 2.6, 0), Vector3(0, 0, -50), 1.4], [Vector3(-0.45, 2.3, 0.1), Vector3(0, 20, 55), 1.2],
		[Vector3(0.1, 3.2, -0.2), Vector3(-30, 0, -15), 1.0], [Vector3(-0.3, 3.0, 0.3), Vector3(25, 0, 35), 0.9],
		[Vector3(0.7, 3.0, 0.1), Vector3(0, 0, -75), 0.7]]
	for i in branches.size():
		_box(g, "Branch%d" % i, branches[i][0], Vector3(0.09, branches[i][2], 0.09), bark, branches[i][1])
	var body := StaticBody3D.new()
	body.name = "TrunkBody"
	_add(body, g)
	var shape := CylinderShape3D.new()
	shape.radius = 0.32
	shape.height = 3.4
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 1.7
	_add(cs, body)
	# Безымянные могилы у дорог: холмики и покосившиеся колышки.
	var mound := _mat(Color("312c27"))
	var stake := _mat(Color("3e342a"))
	var graves := [Vector3(-3.2, 0, 2.6), Vector3(3.4, 0, 3.0), Vector3(-5.0, 0, -0.2), Vector3(4.6, 0, -3.6), Vector3(-1.8, 0, -5.2)]
	for i in graves.size():
		_box(map_root, "Mound%d" % i, graves[i] + Vector3(0, 0.08, 0), Vector3(0.8, 0.16, 1.5), mound, Vector3(0, 15.0 * i, 0))
		_box(map_root, "Stake%d" % i, graves[i] + Vector3(0, 0.35, -0.75), Vector3(0.07, 0.7, 0.07), stake, Vector3(8.0 - 4.0 * i, 0, 6.0 - 3.0 * i))


func _build_bounds() -> void:
	# Невидимые стены на краю тумана — дальше дороги «никуда не ведут».
	for wall in [[Vector3(0, 1.5, -11), Vector3(24, 3, 0.4)], [Vector3(0, 1.5, 11), Vector3(24, 3, 0.4)],
			[Vector3(-11, 1.5, 0), Vector3(0.4, 3, 24)], [Vector3(11, 1.5, 0), Vector3(0.4, 3, 24)]]:
		var body := StaticBody3D.new()
		body.name = "Bound"
		body.position = wall[0]
		_add(body)
		var shape := BoxShape3D.new()
		shape.size = wall[1]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		_add(cs, body)


func _build_actors() -> void:
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0, 8.5)
	_add(player)

	var guardian := Node3D.new()
	guardian.name = "Guardian"
	guardian.position = Vector3(1.0, 0, -0.9)
	_add(guardian)
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	sprite.texture = load("res://assets/sprites/guardian/guardian_placeholder.png")
	sprite.hframes = 4
	sprite.pixel_size = 0.025
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.position.y = 0.7
	_add(sprite, guardian)
	var body := StaticBody3D.new()
	body.name = "Body"
	_add(body, guardian)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.2
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.6
	_add(cs, body)
	# Тусклый свет у ног Стража — фигура читается в тумане.
	var glow := OmniLight3D.new()
	glow.name = "GuardianGlow"
	glow.light_color = Color(0.75, 0.95, 0.7)
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	glow.position = Vector3(0.2, 1.4, 0.6)
	_add(glow, guardian)

	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 15.0
	attrs.dof_blur_far_transition = 6.0
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

	var dialogue := CanvasLayer.new()
	dialogue.name = "DialogueBox"
	dialogue.set_script(load("res://scripts/ui/dialogue_box.gd"))
	_add(dialogue)
	var pause := CanvasLayer.new()
	pause.name = "PauseMenu"
	pause.set_script(load("res://scripts/ui/pause_menu.gd"))
	_add(pause)

	map_root.set("player_path", NodePath("Player"))
	map_root.set("guardian_path", NodePath("Guardian"))
	map_root.set("dialogue_path", NodePath("DialogueBox"))
