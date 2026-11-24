extends Camera3D
## Камера «диорамы»: наклон, дистанция, FOV и сглаживание — из настроек (C01, пресеты — C02),
## плавно следует за целью. Тряска (shake) — сдвигом кадра h_offset/v_offset, слежение она не трогает.
##
## Миниатюра (C07): near+far DOF живёт в CameraAttributesPractical — чем выше «Сила миниатюры»,
## тем уже резкая полоса вокруг цели. Пылинки в свете (C10) — мелкие частицы перед камерой.

@export var target_path: NodePath
## Запасной offset, если настройки ещё не прочитаны (сцена без автозагрузки).
@export var offset: Vector3 = Vector3(0.0, 9.0, 11.0)
@export var follow_speed: float = 5.0
## Наибольший сдвиг кадра при тряске, метры.
@export var shake_amplitude: float = 0.35

## Ключи настроек, после которых камера пересобирает себя.
const SETTING_KEYS := ["camera_pitch", "camera_height", "camera_distance", "camera_fov",
	"camera_smooth", "miniature", "fx_quality", "fx_dust"]
const DUST_AMOUNT := 90

var _target: Node3D
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _pitch: float = 39.0
var _dof: CameraAttributesPractical
var _dust: GPUParticles3D
var _toast: Label
var _toast_left: float = 0.0
## Сколько висит название вида после переключения V.
const TOAST_TIME := 1.6


func _ready() -> void:
	# Камера живёт и на паузе: в настройках ползунки должны сразу показывать новый вид.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_target = get_node_or_null(target_path) as Node3D
	_apply_settings()
	if Settings:
		Settings.changed.connect(_on_setting_changed)
	snap_to_target()


## V — следующий вид камеры по кругу (пресеты 1…N, «Свои» пропускаем).
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or not event.is_action_pressed("camera_view"):
		return
	var next := int(Settings.get_value("camera_preset")) + 1
	if next >= Settings.CAMERA_PRESETS.size() or next < 1:
		next = 1
	Settings.apply_camera_preset(next)
	_show_toast("Вид: " + str(Settings.CAMERA_PRESETS[next]["name"]))
	get_viewport().set_input_as_handled()


func _show_toast(text: String) -> void:
	if _toast == null:
		_make_toast()
	_toast.text = text
	_toast.visible = true
	_toast_left = TOAST_TIME


## Плашка с названием вида: холст UIScaler, чтобы совпадать с остальным интерфейсом.
func _make_toast() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CameraToast"
	layer.layer = 5
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var scaler := UIScaler.new()
	scaler.min_canvas = Vector2(320, 200)
	layer.add_child(scaler)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scaler.add_child(canvas)
	_toast = Label.new()
	_toast.position = Vector2(0, 26)
	_toast.size = Vector2(640, 12)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Color("e8d8b0"))
	_toast.add_theme_color_override("font_outline_color", Color("1a1208"))
	_toast.add_theme_constant_override("outline_size", 3)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	canvas.add_child(_toast)


func _on_setting_changed(key: String) -> void:
	if key in SETTING_KEYS:
		_apply_settings()


## Наклон, высота и приближение из настроек → offset; заодно поворот, FOV, сглаживание, DOF и пылинки.
func _apply_settings() -> void:
	_pitch = clampf(float(Settings.get_value("camera_pitch")), 10.0, 85.0)
	var distance := clampf(float(Settings.get_value("camera_distance")), 4.0, 40.0)
	# Высота — добавка к подъёму от наклона: поднимает камеру, не сдвигая её назад.
	var height := clampf(float(Settings.get_value("camera_height")), -4.0, 12.0)
	follow_speed = clampf(float(Settings.get_value("camera_smooth")), 0.5, 20.0)
	fov = clampf(float(Settings.get_value("camera_fov")), 10.0, 90.0)
	var rad := deg_to_rad(_pitch)
	offset = Vector3(0.0, sin(rad) * distance + height, cos(rad) * distance)
	_aim_at_target()
	_apply_dof(distance)
	_apply_dust()


## Камера всегда смотрит в точку цели: высота меняет угол взгляда, а не уводит Рэя вниз из кадра.
func _aim_at_target() -> void:
	var flat := Vector2(offset.x, offset.z).length()
	rotation = Vector3(-atan2(offset.y, maxf(flat, 0.001)), 0.0, 0.0)


## Глубина резкости «миниатюра»: резкая полоса вокруг цели, размытие к камере и вдаль.
func _apply_dof(distance: float) -> void:
	var weak := int(Settings.get_value("fx_quality")) == 1
	var strength := clampf(float(Settings.get_value("miniature")), 0.0, 1.0)
	if weak:
		strength = 0.0
	if _dof == null:
		_dof = CameraAttributesPractical.new()
		attributes = _dof
	var on := strength > 0.01
	_dof.dof_blur_near_enabled = on
	_dof.dof_blur_far_enabled = on
	if not on:
		_dof.dof_blur_amount = 0.0
		return
	# Полоса резкости: 7,5 м на слабой миниатюре и 3 м на полной.
	var band := lerpf(7.5, 3.0, strength)
	_dof.dof_blur_near_distance = maxf(distance - band, 1.0)
	_dof.dof_blur_near_transition = band * 0.9
	_dof.dof_blur_far_distance = distance + band * 1.2
	_dof.dof_blur_far_transition = band * 1.4
	_dof.dof_blur_amount = 0.03 + 0.07 * strength


## Пылинки в воздухе (C10): маленькие светящиеся точки перед камерой, живут в мире.
func _apply_dust() -> void:
	var amount := clampf(float(Settings.get_value("fx_dust")), 0.0, 1.0)
	if Engine.get_main_loop() == null or DisplayServer.get_name() == "headless":
		return
	if _dust == null:
		_dust = _make_dust()
		add_child(_dust)
	_dust.visible = amount > 0.01
	_dust.amount_ratio = amount


func _make_dust() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Dust"
	particles.amount = DUST_AMOUNT
	particles.lifetime = 14.0
	particles.preprocess = 4.0
	particles.local_coords = false
	particles.position = Vector3(0.0, 0.0, -14.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(13.0, 5.0, 13.0)
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.12
	process.gravity = Vector3(0.0, -0.02, 0.0)
	process.scale_min = 0.4
	process.scale_max = 1.0
	process.color = Color(1.0, 0.94, 0.78, 1.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.turbulence_noise_scale = 6.0
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.93, 0.75, 0.3)
	mat.disable_receive_shadows = true
	quad.material = mat
	particles.draw_pass_1 = quad
	return particles


## Добавляет тряску: strength 0..1, затухает примерно за полсекунды.
func shake(strength: float) -> void:
	_trauma = clampf(_trauma + strength, 0.0, 1.0)


## Мгновенно перенести камеру к цели (после возрождения).
func snap_to_target() -> void:
	if _target:
		global_position = _target.global_position + offset
		_aim_at_target()


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0 and _toast:
			_toast.visible = false
	if _trauma <= 0.0:
		h_offset = 0.0
		v_offset = 0.0
		return
	# Реальное время: тряска идёт и во время стоп-кадра.
	var real := delta / maxf(Engine.time_scale, 0.001)
	_shake_time += real
	_trauma = maxf(_trauma - real * 2.0, 0.0)
	var power := _trauma * _trauma * shake_amplitude
	h_offset = power * sin(_shake_time * 47.0)
	v_offset = power * sin(_shake_time * 61.0 + 1.3)


func _physics_process(delta: float) -> void:
	if not _target:
		return
	var desired := _target.global_position + offset
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
