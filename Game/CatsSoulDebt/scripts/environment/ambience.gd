class_name Ambience
extends Node3D
## Живые эффекты окружения (решение автора: «всё плоско» — нужны живая природа, свет и воздух, дым и огонь).
## Вокруг Рэя (частицы в мире, источник следует за ним): летящие листья, пух и пыльца, бабочки.
## По точкам уровня (пустышки fx-<вид>-NN из Blender): дым из труб, искры и отсвет горна, фонари,
## светлячки (опушка леса и ивы у воды); в мире вокруг Брода ещё фонари душ (фиолетовый свет и искры души),
## руны святилища, туман кладбища, брызги водопада, холодное дыхание пещеры.
## В подземелье (dungeon, Рубеж): пыль, видная только в свете факелов, сырая дымка у пола, капли с потолка
## (падают рядом с Рэем, разбиваются брызгами со звуком «drip»).
## Всё — пиксельные квадраты/спрайты с фильтром nearest, как остальная графика.

const LEAVES := preload("res://assets/textures/vfx/leaves_summer.png")
const FLUFF := preload("res://assets/textures/vfx/fluff.png")
const BUTTERFLY := preload("res://assets/textures/vfx/butterfly.png")
const LEAF_FRAMES := 16
const FLUFF_FRAMES := 4

@export var player_path: NodePath
## Где искать пустышки fx-* (геометрия уровня из glb).
@export var geometry_path: NodePath
## Под открытым небом — листья, пух и бабочки вокруг Рэя; в помещении (таверна) — нет.
@export var outdoor: bool = true
## Подземелье: пыль в свете, дымка у пола, капли.
@export var dungeon: bool = false
## Капли: раз в столько секунд (случайно в пределах), в радиусе вокруг Рэя.
@export var drip_interval := Vector2(0.5, 1.6)
@export var drip_radius := 7.0

var _player: Node3D
var _follow: Array[Node3D] = []
var _flicker: Array = []
var _butterfly_node: CPUParticles3D
var _night_flies: CPUParticles3D
var _drip_wait := 1.0
var _drip_mesh: QuadMesh


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	if outdoor:
		_follow.append(_leaves())
		_follow.append(_fluff())
		_butterfly_node = _butterflies()
		_follow.append(_butterfly_node)
		_night_flies = _night_fireflies()
		_night_flies.emitting = false
		_follow.append(_night_flies)
	if dungeon:
		_follow.append(_dust())
		_follow.append(_damp_mist())
		_drip_mesh = QuadMesh.new()
		_drip_mesh.size = Vector2(0.035, 0.11)
		var dm := _square_material(true, 1.2)
		dm.albedo_color = Color(0.75, 0.85, 1.0, 0.85)
		dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		_drip_mesh.material = dm
	var geo := get_node_or_null(geometry_path)
	if geo:
		for c in geo.get_children():
			var n := String(c.name)
			var p: Vector3 = (c as Node3D).global_position if c is Node3D else Vector3.ZERO
			if n.begins_with("fx-chimney"):
				_smoke(p)
			elif n.begins_with("fx-forge"):
				_forge(p)
			elif n.begins_with("fx-lantern"):
				_lantern(p)
			elif n.begins_with("fx-firefly"):
				_fireflies(p)
			elif n.begins_with("fx-torch"):
				_torch(p)
			elif n.begins_with("fx-fire"):
				_hearth(p)
			elif n.begins_with("fx-candle"):
				_candle(p)
			elif n.begins_with("fx-soul-lantern"):
				_soul_lantern(p)
			elif n.begins_with("fx-runes"):
				_runes(p)
			elif n.begins_with("fx-fog"):
				_ground_fog(p)
			elif n.begins_with("fx-waterfall"):
				_mist(p)
			elif n.begins_with("fx-cave"):
				_cave_breath(p)


func _process(delta: float) -> void:
	if dungeon and _player:
		_drip_wait -= delta
		if _drip_wait <= 0.0:
			_drip_wait = randf_range(drip_interval.x, drip_interval.y)
			_drip()
	if _player:
		for f in _follow:
			if not f.has_meta("follow_offset"):
				f.set_meta("follow_offset", f.position)
			f.global_position = _player.global_position + f.get_meta("follow_offset")
	var t := Time.get_ticks_msec() / 1000.0
	for item in _flicker:
		var light: OmniLight3D = item[0]
		light.light_energy = item[1] * (0.85 + 0.15 * sin(t * 13.0 + item[2]) + 0.08 * sin(t * 31.0 + item[2] * 2.0))


# --- Материалы ---------------------------------------------------------------------

## Пиксельный спрайт-частица: кадр из полосы выбирается случайно (anim_offset), цвет — от частицы.
func _sprite_material(tex: Texture2D, frames: int, unshaded := false, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.particles_anim_h_frames = frames
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = true
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(1, 0.9, 0.6)
		m.emission_energy_multiplier = glow
	return m


## Квадратик без текстуры (дым, искры, светлячки) — пиксельный, всегда к камере.
func _square_material(unshaded: bool, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_energy_multiplier = glow
	return m


func _quad(size: float, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q


func _particles(name_: String, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = name_
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.preprocess = lifetime
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


# --- Вокруг Рэя ----------------------------------------------------------------------

## Листья: срываются с высоты крон, падают медленно, кружась и покачиваясь.
func _leaves() -> CPUParticles3D:
	var p := _particles("Листья", 70, 8.0)
	p.mesh = _quad(0.4, _sprite_material(LEAVES, LEAF_FRAMES))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(12, 1.5, 8)
	p.position = Vector3(0, 5, 0)
	p.direction = Vector3(1, -0.2, 0.3)
	p.spread = 40.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.25, -0.55, 0.1)
	p.damping_min = 0.4
	p.damping_max = 0.8
	p.angular_velocity_min = -160.0
	p.angular_velocity_max = 160.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.1
	p.tangential_accel_min = -0.4
	p.tangential_accel_max = 0.4
	# Рисованная анимация «качания»: масштаб по времени жизни.
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.06, 1.0))
	fade.add_point(Vector2(0.9, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = fade
	return p


## Пух одуванчика, лепестки, пыльца — медленно дрейфуют над травой, поблёскивая на солнце.
func _fluff() -> CPUParticles3D:
	var p := _particles("Пух", 90, 8.0)
	p.mesh = _quad(0.4, _sprite_material(FLUFF, FLUFF_FRAMES, false, 0.25))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(11, 1.2, 8)
	p.position = Vector3(0, 1.4, 0)
	p.direction = Vector3(1, 0.15, 0.2)
	p.spread = 70.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.45
	p.gravity = Vector3(0.12, 0.02, 0.0)
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.15, 1.0))
	fade.add_point(Vector2(0.85, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = fade
	return p


## Бабочки: белые и жёлтые, порхают зигзагами (кадры взмаха + случайное ускорение).
func _butterflies() -> CPUParticles3D:
	var p := _particles("Бабочки", 9, 10.0)
	var m := _sprite_material(BUTTERFLY, 2)
	m.particles_anim_loop = true
	# Кадр 8 пикселей; бабочка чуть крупнее «честного» размера — иначе с высоты камеры её не видно.
	p.mesh = _quad(0.4, m)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(9, 0.6, 7)
	p.position = Vector3(0, 1.0, 0)
	p.direction = Vector3(1, 0.3, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.1
	p.gravity = Vector3.ZERO
	p.anim_speed_min = 9.0
	p.anim_speed_max = 12.0
	p.tangential_accel_min = -2.0
	p.tangential_accel_max = 2.0
	p.radial_accel_min = -0.4
	p.radial_accel_max = 0.4
	p.damping_min = 0.1
	p.damping_max = 0.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1))
	ramp.set_color(1, Color(1.0, 0.86, 0.32))
	p.color_initial_ramp = ramp
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.08, 1.0))
	fade.add_point(Vector2(0.92, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = fade
	return p


# --- По точкам уровня ----------------------------------------------------------------

## Дым из трубы: серые пиксельные клубы растут, светлеют и тают, ветер сносит на восток.
func _smoke(at: Vector3) -> void:
	var p := _particles("Дым", 22, 6.0)
	p.global_position = at + Vector3(0, 0.2, 0)
	p.mesh = _quad(0.5, _square_material(false))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.direction = Vector3(0, 1, 0)
	p.spread = 12.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.35, 0.15, -0.05)
	p.damping_min = 0.2
	p.damping_max = 0.3
	p.angle_max = 360.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 2.6))
	p.scale_amount_curve = grow
	var g := Gradient.new()
	g.set_color(0, Color(0.42, 0.40, 0.38, 0.75))
	g.set_color(1, Color(0.82, 0.80, 0.78, 0.0))
	p.color_ramp = g
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(8, 10, 6))


## Горн кузницы: тёплый мерцающий отсвет и редкие искры, взлетающие и гаснущие.
func _forge(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.22)
	light.light_energy = 2.2
	light.omni_range = 5.0
	light.shadow_enabled = false
	add_child(light)
	light.global_position = at + Vector3(0, 0.8, 0)
	_flicker.append([light, 2.2, randf() * 10.0])
	var p := _particles("Искры", 16, 1.2)
	p.global_position = at + Vector3(0, 0.6, 0)
	p.mesh = _quad(0.06, _square_material(true, 3.0))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -2.0, 0)
	p.explosiveness = 0.2
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.5))
	g.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	p.color_ramp = g


## Фонарь у двери: кованый короб со светящимся окошком и тёплый свет (днём едва заметен).
func _lantern(at: Vector3) -> void:
	var glass := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.32, 0.22)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.78, 0.4)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.32)
	m.emission_energy_multiplier = 2.0
	box.material = m
	glass.mesh = box
	add_child(glass)
	glass.global_position = at
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.3, 0.06, 0.3)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.14, 0.13)
	cap_mesh.material = iron
	cap.mesh = cap_mesh
	add_child(cap)
	cap.global_position = at + Vector3(0, 0.19, 0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.38)
	light.light_energy = 1.2
	light.omni_range = 4.0
	add_child(light)
	light.global_position = at
	_flicker.append([light, 1.2, randf() * 10.0])


## Камин: сильный тёплый мерцающий свет, языки пламени (пиксельные квадраты) и искры вверх.
func _hearth(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.58, 0.26)
	light.light_energy = 3.0
	light.omni_range = 9.0
	light.shadow_enabled = true
	add_child(light)
	light.global_position = at + Vector3(0.4, 0.6, 0)
	_flicker.append([light, 3.0, randf() * 10.0])
	var flame := _particles("Пламя", 30, 0.7)
	flame.global_position = at
	flame.mesh = _quad(0.12, _square_material(true, 3.5))
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flame.emission_box_extents = Vector3(0.25, 0.05, 0.35)
	flame.direction = Vector3.UP
	flame.spread = 10.0
	flame.initial_velocity_min = 0.6
	flame.initial_velocity_max = 1.1
	flame.gravity = Vector3(0, 0.6, 0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.6), Color(1.0, 0.55, 0.15), Color(0.7, 0.15, 0.05, 0.0)])
	flame.color_ramp = g
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.2))
	flame.scale_amount_curve = shrink
	_forge_sparks(at + Vector3(0, 0.3, 0))


func _forge_sparks(at: Vector3) -> void:
	var p := _particles("Искры", 8, 1.6)
	p.global_position = at
	p.mesh = _quad(0.05, _square_material(true, 3.0))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -0.4, 0)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4))
	g.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	p.color_ramp = g


## Настенный факел (Рубеж): язычок пламени из пиксельных квадратов, редкие искры, мерцающий свет без теней
## (тени даёт общий свет зала — иначе десятки теневых источников).
func _torch(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.28)
	light.light_energy = 1.3
	light.omni_range = 5.0
	add_child(light)
	light.global_position = at + Vector3(0, 0.25, 0)
	_flicker.append([light, 1.3, randf() * 10.0])
	var flame := _particles("Факел", 14, 0.5)
	flame.global_position = at
	flame.mesh = _quad(0.09, _square_material(true, 1.6))
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = 0.06
	flame.direction = Vector3.UP
	flame.spread = 12.0
	flame.initial_velocity_min = 0.4
	flame.initial_velocity_max = 0.8
	flame.gravity = Vector3(0, 0.5, 0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.82, 0.38), Color(1.0, 0.45, 0.1), Color(0.6, 0.12, 0.04, 0.0)])
	flame.color_ramp = g
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.25))
	flame.scale_amount_curve = shrink
	var sparks := _particles("Искры факела", 3, 1.4)
	sparks.global_position = at + Vector3(0, 0.15, 0)
	sparks.mesh = _quad(0.04, _square_material(true, 3.0))
	sparks.direction = Vector3.UP
	sparks.spread = 30.0
	sparks.initial_velocity_min = 0.5
	sparks.initial_velocity_max = 1.0
	sparks.gravity = Vector3(0, -0.3, 0)
	var sg := Gradient.new()
	sg.set_color(0, Color(1.0, 0.85, 0.4))
	sg.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	sparks.color_ramp = sg


## Свеча: маленький тёплый огонёк и слабый мерцающий свет.
func _candle(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.light_energy = 0.9
	light.omni_range = 3.2
	add_child(light)
	light.global_position = at + Vector3(0, 0.15, 0)
	_flicker.append([light, 0.9, randf() * 10.0])


## Светлячки: тёплые светящиеся точки, медленно блуждают и мерцают (в тени их видно, на солнце — едва).
func _fireflies(at: Vector3) -> void:
	var p := _particles("Светлячки", 14, 5.0)
	p.global_position = at + Vector3(0, 0.8, 0)
	p.mesh = _quad(0.07, _square_material(true, 4.0))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(5, 0.7, 5)
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.3
	p.gravity = Vector3.ZERO
	p.tangential_accel_min = -0.6
	p.tangential_accel_max = 0.6
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([Color(0.9, 1.0, 0.5, 0.0), Color(0.9, 1.0, 0.5, 1.0), Color(0.9, 1.0, 0.5, 0.2),
		Color(0.9, 1.0, 0.5, 1.0), Color(0.9, 1.0, 0.5, 0.3), Color(0.9, 1.0, 0.5, 0.0)])
	p.color_ramp = g
	p.visibility_aabb = AABB(Vector3(-7, -2, -7), Vector3(14, 5, 14))


# --- Мир вокруг Брода ----------------------------------------------------------------

## Свет, который гаснет вдали (в большом мире десятки источников).
func _far_light(at: Vector3, color: Color, energy: float, range_: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_
	light.distance_fade_enabled = true
	light.distance_fade_begin = 50.0
	light.distance_fade_length = 20.0
	add_child(light)
	light.global_position = at
	return light


## Фонарь душ (CANON): вокруг стекла кружат искры души. Свет даёт SoulLantern — только зажжённый.
func _soul_lantern(at: Vector3) -> void:
	var p := _particles("Искры души", 10, 3.0)
	p.global_position = at
	p.mesh = _quad(0.06, _square_material(true, 5.0))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.direction = Vector3(0, 1, 0)
	p.spread = 40.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.3
	p.gravity = Vector3(0, 0.15, 0)
	p.tangential_accel_min = -0.8
	p.tangential_accel_max = 0.8
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.7, 1.0, 1.0))
	g.set_color(1, Color(0.55, 0.32, 0.9, 0.0))
	p.color_ramp = g
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))


## Руны святилища: бирюзовое свечение, медленный пульс и пылинки над кругом.
func _runes(at: Vector3) -> void:
	_flicker.append([_far_light(at + Vector3(0, 0.6, 0), Color(0.4, 0.95, 0.9), 1.2, 7.0), 1.2, randf() * 10.0])
	var p := _particles("Пыль рун", 16, 4.0)
	p.global_position = at + Vector3(0, 0.3, 0)
	p.mesh = _quad(0.05, _square_material(true, 4.0))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2, 0.1, 2)
	p.direction = Vector3(0, 1, 0)
	p.spread = 10.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.4
	p.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 1.0, 0.95, 0.9))
	g.set_color(1, Color(0.4, 0.9, 0.9, 0.0))
	p.color_ramp = g
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))


## Туман кладбища: мягкие круглые клочья (радиальная текстура — квадраты читались плоскими листами)
## ползут низко над землёй и медленно растут.
func _ground_fog(at: Vector3) -> void:
	var p := _particles("Туман", 36, 12.0)
	p.global_position = at + Vector3(0, 0.5, 0)
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 32
	soft.height = 32
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 1))
	sg.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = sg
	var m := _square_material(false)
	m.albedo_texture = soft
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	p.mesh = _quad(4.0, m)
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 1.4))
	p.scale_amount_curve = grow
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(30, 0.3, 30)
	p.direction = Vector3(1, 0, 0.3)
	p.spread = 30.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.4
	p.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	g.colors = PackedColorArray([Color(0.8, 0.82, 0.85, 0.0), Color(0.8, 0.82, 0.85, 0.28),
		Color(0.8, 0.82, 0.85, 0.24), Color(0.8, 0.82, 0.85, 0.0)])
	p.color_ramp = g
	p.visibility_aabb = AABB(Vector3(-36, -1, -36), Vector3(72, 4, 72))


## Водопад: белые брызги и водяная пыль у подножия.
func _mist(at: Vector3) -> void:
	var p := _particles("Брызги", 40, 2.0)
	p.global_position = at
	p.mesh = _quad(0.35, _square_material(false))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.2
	p.direction = Vector3(0, 1, 0)
	p.spread = 60.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -0.6, 0)
	var g := Gradient.new()
	g.set_color(0, Color(0.92, 0.96, 1.0, 0.7))
	g.set_color(1, Color(0.92, 0.96, 1.0, 0.0))
	p.color_ramp = g
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))


## Вход в пещеру: слабый холодный свет из глубины и редкий пар.
func _cave_breath(at: Vector3) -> void:
	_far_light(at, Color(0.55, 0.7, 0.95), 0.8, 8.0)
	var p := _particles("Пар пещеры", 8, 5.0)
	p.global_position = at
	p.mesh = _quad(0.8, _square_material(false))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.0
	p.direction = Vector3(0, 0.5, 1)
	p.spread = 25.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.4
	p.gravity = Vector3(0, 0.1, 0)
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.82, 0.9, 0.35))
	g.set_color(1, Color(0.75, 0.82, 0.9, 0.0))
	p.color_ramp = g
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))


## Ночь (0…1, от DayNightCycle): бабочки прячутся, вокруг Рэя — светлячки.
func set_night(amount: float) -> void:
	if _butterfly_node:
		_butterfly_node.emitting = amount < 0.5
	if _night_flies:
		_night_flies.emitting = amount > 0.5


## Ночные светлячки вокруг Рэя (зелёно-жёлтые огоньки, мигают).
func _night_fireflies() -> CPUParticles3D:
	var p := _particles("Светлячки ночью", 26, 5.0)
	p.mesh = _quad(0.07, _square_material(true, 5.0))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(10, 1.0, 8)
	p.position = Vector3(0, 0.9, 0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.3
	p.gravity = Vector3.ZERO
	p.tangential_accel_min = -0.6
	p.tangential_accel_max = 0.6
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([Color(0.9, 1.0, 0.5, 0.0), Color(0.9, 1.0, 0.5, 1.0), Color(0.9, 1.0, 0.5, 0.2),
		Color(0.9, 1.0, 0.5, 1.0), Color(0.9, 1.0, 0.5, 0.3), Color(0.9, 1.0, 0.5, 0.0)])
	p.color_ramp = g
	p.visibility_aabb = AABB(Vector3(-12, -2, -10), Vector3(24, 5, 20))
	return p


# --- Подземелье ----------------------------------------------------------------------

## Пыль: мелкие светлые пылинки медленно плавают в воздухе; материал с освещением — видны там, где их задевает
## свет факела, в полутьме едва заметны (так и читаются «лучи»).
func _dust() -> CPUParticles3D:
	var p := _particles("Пыль", 140, 9.0)
	p.mesh = _quad(0.045, _square_material(false, 0.35))   # слабое свечение: чуть видна и в полутьме
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(8, 1.6, 7)
	p.position = Vector3(0, 1.8, 0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.08
	p.gravity = Vector3(0, -0.01, 0)
	p.tangential_accel_min = -0.05
	p.tangential_accel_max = 0.05
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.93, 0.8, 0.0), Color(1.0, 0.93, 0.8, 0.9), Color(1.0, 0.93, 0.8, 0.9),
		Color(1.0, 0.93, 0.8, 0.0)])
	p.color_ramp = g
	p.visibility_aabb = AABB(Vector3(-10, -3, -9), Vector3(20, 7, 18))
	return p


## Сырая дымка у пола: редкие мягкие клочья низко над камнем (текстура как у тумана кладбища, но бледнее).
func _damp_mist() -> CPUParticles3D:
	var p := _particles("Дымка", 18, 10.0)
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 32
	soft.height = 32
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 1))
	sg.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = sg
	var m := _square_material(false)
	m.albedo_texture = soft
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	p.mesh = _quad(3.2, m)
	p.position = Vector3(0, 0.25, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(9, 0.1, 8)
	p.direction = Vector3(1, 0, 0.2)
	p.spread = 40.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.15
	p.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(0.62, 0.7, 0.72, 0.0), Color(0.62, 0.7, 0.72, 0.2), Color(0.62, 0.7, 0.72, 0.0)])
	p.color_ramp = g
	p.visibility_aabb = AABB(Vector3(-12, -1, -11), Vector3(24, 3, 22))
	return p


## Капля: точка рядом с Рэем, пол — лучом сверху; капля падает с 3,5 м, у пола — брызги и звук.
func _drip() -> void:
	var a := randf() * TAU
	var r := sqrt(randf()) * drip_radius
	var at := _player.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 3.0, 0), at - Vector3(0, 3.0, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	# Только ровный пол на уровне Рэя (не верх стены и не дно пропасти).
	if hit.is_empty() or hit.normal.y < 0.7 or absf(hit.position.y - _player.global_position.y) > 1.5:
		return
	var floor_at: Vector3 = hit.position
	var drop := MeshInstance3D.new()
	drop.mesh = _drip_mesh
	drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drop)
	drop.global_position = floor_at + Vector3(0, 3.5, 0)
	var t := create_tween()
	t.tween_property(drop, "global_position", floor_at + Vector3(0, 0.05, 0), 0.8).set_trans(Tween.TRANS_QUAD) 		.set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		CombatFX.burst(floor_at + Vector3(0, 0.05, 0), Color(0.75, 0.85, 1.0), Vector3.ZERO, 5, 1.2, 4.0, 0.03, 0.3)
		Audio.play("drip", floor_at, 0.15)
		drop.queue_free())
