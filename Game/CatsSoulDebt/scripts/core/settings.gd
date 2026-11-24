extends Node
## Настройки игры (автозагрузка Settings): хранение в user://settings.cfg (у тестов — своя папка, user_files.gd) и применение.
## Состав — UI_SPEC, раздел 5. Переназначение клавиш пока не делаем (решение автора).

signal changed(key: String)

const UserFiles := preload("res://scripts/core/user_files.gd")
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const WINDOW_MODES := ["Оконный", "Без рамки", "Полный экран"]
const DIFFICULTIES := ["Легко", "Нормально", "Сложно"]
const AUDIO_BUSES := ["Music", "SFX", "Ambient", "Voice"]
## «Ограничение кадров»: индекс настройки max_fps → кадров в секунду (0 — без ограничения). Работает всегда,
## независимо от VSync (драйвер/оконный режим его иногда игнорируют — видеокарта тогда грузится на 100 %).
const FPS_LIMITS := [30, 60, 120, 144, 0]
const FPS_LIMIT_NAMES := ["30", "60", "120", "144", "Без ограничения"]
## Кадры в фоне (окно потеряло фокус или свёрнуто).
const BACKGROUND_FPS := 15

const DEFAULTS := {
	"resolution": 2,
	"window_mode": 0,
	"vsync": true,
	"max_fps": 1,
	"ui_scale": 3,
	"brightness": 1.0,
	"master_volume": 0.8,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"ambient_volume": 0.7,
	"voice_volume": 0.8,
	"difficulty": 1,
	"camera_shake": 1.0,
	"glitch_strength": 1.0,
	"text_speed": 1.0,
	"touch_controls": 0,
	"tutorial_hints": true,
	# Камера-диорама (C01): три независимых рычага — наклон в градусах, высота (подъём над
	# расчётной точкой, метры) и приближение (дистанция, метры). Камера смотрит на цель,
	# поэтому подъём поднимает взгляд, а не уводит Рэя из кадра.
	"camera_pitch": 39.0,
	"camera_height": 0.0,
	"camera_distance": 14.2,
	"camera_fov": 30.0,
	"camera_smooth": 5.0,
	"camera_preset": 0,
	# Миниатюра и экранные эффекты (C06–C08, C13): 0…1.
	"miniature": 0.8,
	"fx_tilt": 0.45,
	"fx_vignette": 0.25,
	"fx_grain": 0.15,
	"fx_chroma": 0.1,
	"glow_strength": 1.0,
	"fx_bloom": 0.35,
	"fx_dust": 0.5,
	"fx_quality": 0,
}
## Экранный джойстик и кнопки: сами при касании экрана / всегда / никогда.
const TOUCH_MODES := ["Авто", "Всегда", "Выкл"]
## Пресеты камеры (C02): «Свои» — индекс 0, значения задают ползунки.
const CAMERA_PRESETS := [
	{"name": "Свои", "pitch": 39.0, "height": 0.0, "distance": 14.2, "fov": 30.0},
	{"name": "Диорама", "pitch": 39.0, "height": 0.0, "distance": 14.2, "fov": 30.0},
	{"name": "Ближе", "pitch": 34.0, "height": 0.0, "distance": 10.5, "fov": 32.0},
	{"name": "Сверху", "pitch": 58.0, "height": 1.5, "distance": 13.0, "fov": 30.0},
	{"name": "Кинематограф", "pitch": 30.0, "height": 0.0, "distance": 17.5, "fov": 22.0},
]
const CAMERA_PRESET_KEYS := ["camera_pitch", "camera_height", "camera_distance", "camera_fov"]
## Качество эффектов (C13): 0 — полные, 1 — слабый ПК (без DOF, зерна, хроматики).
const FX_QUALITY_NAMES := ["Полные", "Слабый ПК"]

## Задаётся один раз при запуске, дальше как константа.
var PATH: String = UserFiles.path("settings.cfg")
var values: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	_ensure_audio_buses()
	load_settings()
	apply_all()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	_apply(key)
	changed.emit(key)


func reset_to_defaults() -> void:
	values = DEFAULTS.duplicate()
	apply_all()
	for key in values:
		changed.emit(key)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in DEFAULTS:
		values[key] = cfg.get_value("settings", key, DEFAULTS[key])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in values:
		cfg.set_value("settings", key, values[key])
	cfg.save(PATH)


func apply_all() -> void:
	for key in values:
		_apply(key)


func _apply(key: String) -> void:
	var v: Variant = values[key]
	match key:
		"window_mode", "resolution":
			_apply_window()
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			_apply_fps_limit()
		"master_volume":
			_set_bus_volume("Master", v)
		"music_volume":
			_set_bus_volume("Music", v)
		"sfx_volume":
			_set_bus_volume("SFX", v)
		"ambient_volume":
			_set_bus_volume("Ambient", v)
		"voice_volume":
			_set_bus_volume("Voice", v)
		"difficulty":
			PlayerState.difficulty = v
		# ui_scale и brightness читают сами UIScaler и AtmosphereBlender (сигнал changed);
		# camera_* и miniature читает diorama_camera.gd, fx_* — автозагрузка ScreenFX,
		# glow_strength — AtmosphereBlender (всё по сигналу changed).


## Пресет камеры (C02): пишет наклон/дистанцию/FOV и запоминает выбранный пункт.
func apply_camera_preset(i: int) -> void:
	i = clampi(i, 0, CAMERA_PRESETS.size() - 1)
	var p: Dictionary = CAMERA_PRESETS[i]
	set_value("camera_pitch", float(p["pitch"]))
	set_value("camera_height", float(p["height"]))
	set_value("camera_distance", float(p["distance"]))
	set_value("camera_fov", float(p["fov"]))
	set_value("camera_preset", i)


var _in_background := false


func _apply_fps_limit() -> void:
	if _in_background:
		Engine.max_fps = BACKGROUND_FPS
	else:
		Engine.max_fps = FPS_LIMITS[clampi(int(values.get("max_fps", 1)), 0, FPS_LIMITS.size() - 1)]


## В фоне игра не должна жечь видеокарту: кадры режутся до BACKGROUND_FPS, при возврате — настройка.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_in_background = true
			_apply_fps_limit()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_in_background = false
			_apply_fps_limit()


func _apply_window() -> void:
	# В headless-режиме (тесты, сборка сцен) окна нет.
	if DisplayServer.get_name() == "headless":
		return
	match int(values["window_mode"]):
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			_set_window_size()
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			_set_window_size()
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _set_window_size() -> void:
	var size: Vector2i = RESOLUTIONS[clampi(int(values["resolution"]), 0, RESOLUTIONS.size() - 1)]
	var screen := DisplayServer.screen_get_size()
	size = size.min(screen)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(DisplayServer.screen_get_position() + (screen - size) / 2)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)


## Шины Music/SFX/Ambient/Voice создаются заранее — звука в игре пока нет.
func _ensure_audio_buses() -> void:
	for bus_name in AUDIO_BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
