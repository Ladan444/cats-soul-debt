extends CanvasLayer
## Экранные эффекты поверх 3D-мира (C06, C08, C13): один полноэкранный шейдер на слое 0 —
## ниже HUD (слой 1) и фоторежима (15), поэтому интерфейс не размывается и не зернится.
##
## Эффекты включаются только там, где есть игрок: в главном меню 3D-фон рисуется отдельно,
## и непрозрачный слой эффектов закрыл бы его чёрным прямоугольником.
##
## Ключи настроек: fx_tilt, fx_vignette, fx_grain, fx_chroma, fx_quality.
## Цветокор (grade) меняет только фоторежим — на игру он не влияет.

const SHADER := preload("res://assets/ui/screen_fx.gdshader")
const KEYS := ["fx_tilt", "fx_vignette", "fx_grain", "fx_chroma", "fx_quality"]
## Цветокоры фоторежима (C09): тон, насыщенность, контраст, подъём теней.
const GRADES := [
	{"name": "Обычный", "tint": Color(1, 1, 1), "sat": 1.0, "contrast": 1.0, "lift": 0.0},
	{"name": "Тёплый", "tint": Color(1.08, 1.0, 0.87), "sat": 1.12, "contrast": 1.06, "lift": 0.012},
	{"name": "Ночь", "tint": Color(0.85, 0.94, 1.14), "sat": 0.84, "contrast": 1.08, "lift": -0.012},
	{"name": "Рубеж", "tint": Color(0.93, 1.02, 0.99), "sat": 0.78, "contrast": 1.14, "lift": -0.006},
]

var _rect: ColorRect
var _mat: ShaderMaterial
var _time: float = 0.0
var _grade: int = 0
var _check: float = 0.0
var _enabled: bool = false


func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "ScreenFX"
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	add_child(_rect)
	if Settings:
		Settings.changed.connect(_on_setting_changed)
	_apply()


func _on_setting_changed(key: String) -> void:
	if key in KEYS:
		_apply()


## Пересобрать эффекты из настроек: на «слабом ПК» остаются только виньетка и часть блюра.
func _apply() -> void:
	var weak := int(Settings.get_value("fx_quality")) == 1
	var tilt := clampf(float(Settings.get_value("fx_tilt")), 0.0, 1.0)
	var vignette := clampf(float(Settings.get_value("fx_vignette")), 0.0, 1.0)
	var grain := clampf(float(Settings.get_value("fx_grain")), 0.0, 1.0)
	var chroma := clampf(float(Settings.get_value("fx_chroma")), 0.0, 1.0)
	if weak:
		tilt = 0.0
		grain = 0.0
		chroma = 0.0
		vignette *= 0.6
	_mat.set_shader_parameter("tilt_strength", tilt)
	_mat.set_shader_parameter("vignette_strength", vignette)
	_mat.set_shader_parameter("grain_strength", grain)
	_mat.set_shader_parameter("chroma_strength", chroma)
	_apply_grade()


## Цветокор фоторежима (C09): 0 — как в игре, дальше по списку GRADES.
func set_grade(index: int) -> void:
	_grade = clampi(index, 0, GRADES.size() - 1)
	_apply_grade()


func grade_count() -> int:
	return GRADES.size()


func grade_name(index: int) -> String:
	return str(GRADES[clampi(index, 0, GRADES.size() - 1)]["name"])


func _apply_grade() -> void:
	var g: Dictionary = GRADES[_grade]
	_mat.set_shader_parameter("grade_tint", g["tint"])
	_mat.set_shader_parameter("grade_saturation", g["sat"])
	_mat.set_shader_parameter("grade_contrast", g["contrast"])
	_mat.set_shader_parameter("grade_lift", g["lift"])


## Сильнее эффекты в фоторежиме не нужно: там на паузе и так видно всё.
func set_intensity(scale: float) -> void:
	_mat.set_shader_parameter("tilt_strength", clampf(float(Settings.get_value("fx_tilt")) * scale, 0.0, 1.0))


func is_active() -> bool:
	return _enabled


func _process(delta: float) -> void:
	_time += delta
	if _enabled:
		_mat.set_shader_parameter("time", _time)
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.25
	# Без игрока (главное меню) эффекты выключены: 3D-фон там рисуется своей сценой.
	var want := DisplayServer.get_name() != "headless" \
		and get_tree().get_first_node_in_group("player") != null
	if want != _enabled:
		_enabled = want
		_rect.visible = want
