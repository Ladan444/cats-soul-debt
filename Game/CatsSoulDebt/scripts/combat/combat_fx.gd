extends Node
## Автозагрузка CombatFX: общий «отклик» боя (COMBAT_SPEC, раздел 1) и поиск целей удара.
## Стоп-кадр, тряска камеры (сила — настройка «Тряска камеры»), вспышка, пиксельные цифры урона.

## Слои столкновений (битовые значения): мир, Рэй, враги.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const FONT := preload("res://assets/fonts/public_pixel/PublicPixel.ttf")
const SPRITE_SHADER := preload("res://assets/shaders/sprite_character.gdshader")
const COLOR_DAMAGE := Color("f4f2ec")
const COLOR_HEAVY := Color("e8c870")
const COLOR_PLAYER := Color("e86a5a")

var _stop_depth: int = 0
## Обычная скорость игры (мастер-меню отладки: ×1, ×2, ×5) — к ней возвращается стоп-кадр.
var base_time_scale: float = 1.0:
	set(value):
		base_time_scale = value
		if _stop_depth == 0:
			Engine.time_scale = value


## Стоп-кадр: мир почти замирает на duration секунд реального времени.
func hit_stop(duration: float) -> void:
	_stop_depth += 1
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	_stop_depth -= 1
	if _stop_depth == 0:
		Engine.time_scale = base_time_scale


## Тряска камеры: strength 0..1 (умножается на настройку игрока).
func shake(strength: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method("shake"):
		cam.shake(strength * float(Settings.get_value("camera_shake")))


## Материал персонажа (assets/shaders/sprite_character.gdshader): вспышка и призрачность.
## Встроенный материал Sprite3D заменяется, лист передаётся в шейдер и обновляется при смене.
func setup_sprite(sprite: Sprite3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SPRITE_SHADER
	mat.set_shader_parameter("sprite_texture", sprite.texture)
	sprite.material_override = mat
	sprite.texture_changed.connect(func(): mat.set_shader_parameter("sprite_texture", sprite.texture))


## Короткая вспышка спрайта цветом color (белая — попадание, красная — урон по Рэю).
func flash(sprite: Sprite3D, color: Color = Color.WHITE, duration: float = 0.1) -> void:
	if sprite == null or not (sprite.material_override is ShaderMaterial):
		return
	var mat: ShaderMaterial = sprite.material_override
	mat.set_shader_parameter("flash_color", color)
	mat.set_shader_parameter("flash", 1.0)
	var t := sprite.create_tween()
	t.set_ignore_time_scale(true)  # вспышка видна и во время стоп-кадра
	t.tween_interval(duration * 0.6)
	t.tween_method(func(v: float): mat.set_shader_parameter("flash", v), 1.0, 0.0, duration * 0.4)


## Постоянная заливка цветом (замах врага): amount 0..1, 0 — снять.
func tint(sprite: Sprite3D, color: Color, amount: float) -> void:
	if sprite and sprite.material_override is ShaderMaterial:
		sprite.material_override.set_shader_parameter("flash_color", color)
		sprite.material_override.set_shader_parameter("flash", amount)


## Призрачность спрайта 0..1 («Призрачный шаг»).
func set_ghost(sprite: Sprite3D, amount: float) -> void:
	if sprite and sprite.material_override is ShaderMaterial:
		sprite.material_override.set_shader_parameter("ghost", amount)


## Пиксельная цифра урона над целью: всплывает и гаснет.
func damage_number(at: Vector3, amount: float, color: Color = COLOR_DAMAGE) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var l := Label3D.new()
	l.text = str(int(round(amount)))
	l.font = FONT
	l.font_size = 16
	l.pixel_size = 0.014
	l.modulate = color
	l.outline_modulate = Color("1e1614")
	l.outline_size = 4
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	scene.add_child(l)
	l.global_position = at + Vector3(randf_range(-0.2, 0.2), 0, 0)
	var t := l.create_tween()
	t.tween_property(l, "global_position:y", at.y + 0.7, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.4)
	t.tween_callback(l.queue_free)


## Надпись над предметом («Ключ от оружейной», «+2 настойки»): всплывает и через пару секунд гаснет.
func float_text(at: Vector3, text: String, color: Color = Color("e8c870")) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font = FONT
	l.font_size = 16
	l.pixel_size = 0.011
	l.modulate = color
	l.outline_modulate = Color("1e1614")
	l.outline_size = 4
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	scene.add_child(l)
	l.global_position = at
	var t := l.create_tween()
	t.tween_property(l, "global_position:y", at.y + 0.6, 1.8).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(1.4)
	t.tween_callback(l.queue_free)


## Вспышка пиксельных частиц: квадратики без сглаживания разлетаются от at в сторону dir
## (нулевой dir — во все стороны) и падают. Искры попаданий, брызги, пыль.
func burst(at: Vector3, color: Color, dir: Vector3 = Vector3.ZERO, amount: int = 10,
		speed: float = 3.5, gravity: float = 9.0, size: float = 0.07, lifetime: float = 0.35) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = lifetime
	p.local_coords = false
	var flat := Vector3(dir.x, 0.35, dir.z)
	p.direction = flat.normalized() if dir != Vector3.ZERO else Vector3.UP
	p.spread = 55.0 if dir != Vector3.ZERO else 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	p.color_ramp = fade
	scene.add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(lifetime + 0.2).timeout.connect(p.queue_free)


## Цели в секторе: живые узлы группы group в радиусе reach (плюс их радиус) и в пределах
## half_angle градусов от dir. Ближние — первыми.
func targets_in_arc(origin: Vector3, dir: Vector3, reach: float, half_angle: float, group: String = "damageable") -> Array:
	var result := []
	var flat_dir := Vector3(dir.x, 0, dir.z).normalized()
	for n in get_tree().get_nodes_in_group(group):
		if not (n is Node3D) or not n.is_inside_tree() or (n.has_method("is_alive") and not n.is_alive()):
			continue
		var to: Vector3 = n.global_position - origin
		to.y = 0
		var radius: float = n.get("hit_radius") if n.get("hit_radius") != null else 0.4
		var dist := to.length()
		if dist > reach + radius:
			continue
		if dist > 0.3 and rad_to_deg(flat_dir.angle_to(to.normalized())) > half_angle:
			continue
		result.append(n)
	result.sort_custom(func(a, b): return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	return result


## Ближайшая цель в радиусе reach (для доводки удара и «Метки часового»).
func nearest(origin: Vector3, reach: float, group: String = "damageable") -> Node3D:
	var all := targets_in_arc(origin, Vector3.FORWARD, reach, 180.0, group)
	return all[0] if not all.is_empty() else null
