extends Node
## Смена дня и ночи в сцене под открытым небом (по автозагрузке TimeOfDay):
## солнце идёт по дуге с востока на запад и меняет цвет (тёплый рассвет, белый полдень, рыжий закат),
## ночью вместо него — холодная луна; небо, туман и рассеянный свет подкрашиваются через AtmosphereBlender;
## ночью вокруг Рэя — светлячки (Ambience.set_night). Ключевые часы — KEYS, между ними — плавно.

@export var sun_path: NodePath
@export var atmosphere_path: NodePath
@export var ambience_path: NodePath
## Азимут солнца в полдень (градусы поворота по Y) — как стояло солнце сцены.
@export var noon_yaw: float = -30.0

## Час → [цвет света, яркость, небо, туман, рассеянный цвет, множитель рассеянного, glow].
const KEYS := [
	[0.0, Color(0.55, 0.64, 0.95), 0.32, Color(0.10, 0.13, 0.26), Color(0.22, 0.26, 0.42), Color(0.55, 0.62, 0.95), 0.55, 1.6],
	[4.5, Color(0.55, 0.64, 0.95), 0.30, Color(0.14, 0.15, 0.30), Color(0.25, 0.27, 0.42), Color(0.6, 0.62, 0.9), 0.55, 1.5],
	[5.4, Color(1.0, 0.66, 0.52), 0.6, Color(0.88, 0.68, 0.66), Color(0.86, 0.74, 0.72), Color(0.92, 0.82, 0.8), 0.75, 1.15],
	[7.0, Color(1.0, 0.86, 0.68), 1.1, Color(1.0, 0.92, 0.85), Color(1.0, 0.95, 0.9), Color(1.0, 0.95, 0.9), 0.95, 1.0],
	[13.0, Color(1.0, 0.94, 0.82), 1.35, Color.WHITE, Color.WHITE, Color.WHITE, 1.0, 1.0],
	[18.0, Color(1.0, 0.82, 0.6), 1.15, Color(1.0, 0.9, 0.8), Color(1.0, 0.92, 0.85), Color(1.0, 0.92, 0.85), 0.95, 1.05],
	[20.3, Color(1.0, 0.64, 0.46), 0.7, Color(0.92, 0.66, 0.6), Color(0.9, 0.74, 0.7), Color(0.92, 0.82, 0.8), 0.75, 1.2],
	[21.5, Color(0.55, 0.64, 0.95), 0.32, Color(0.12, 0.14, 0.28), Color(0.24, 0.27, 0.42), Color(0.55, 0.62, 0.95), 0.55, 1.6],
	[24.0, Color(0.55, 0.64, 0.95), 0.32, Color(0.10, 0.13, 0.26), Color(0.22, 0.26, 0.42), Color(0.55, 0.62, 0.95), 0.55, 1.6],
]

var _sun: DirectionalLight3D
var _atmo: Node
var _ambience: Node


func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_atmo = get_node_or_null(atmosphere_path)
	if _atmo:
		_atmo.process_mode = Node.PROCESS_MODE_ALWAYS
	_ambience = get_node_or_null(ambience_path)


func _process(_delta: float) -> void:
	var h: float = TimeOfDay.hour
	var k := 0
	while k < KEYS.size() - 2 and h >= KEYS[k + 1][0]:
		k += 1
	var a: Array = KEYS[k]
	var b: Array = KEYS[k + 1]
	var t := smoothstep(0.0, 1.0, (h - a[0]) / maxf(b[0] - a[0], 0.001))
	var day: float = TimeOfDay.daylight()
	if _sun:
		_sun.light_color = (a[1] as Color).lerp(b[1], t)
		_sun.light_energy = lerpf(a[2], b[2], t)
		# Днём — солнце по дуге (6:00 восток, 13:00 зенит, 20:00 запад); ночью — луна высоко с юго-запада.
		var arc := clampf((h - 5.0) / 16.0, 0.0, 1.0)
		var sun_pitch := -lerpf(8.0, 58.0, sin(arc * PI))
		var sun_yaw := noon_yaw + lerpf(70.0, -70.0, arc)
		var moon := Vector3(-48.0, noon_yaw + 150.0, 0.0)
		_sun.rotation_degrees = moon.lerp(Vector3(sun_pitch, sun_yaw, 0.0), day)
		_sun.shadow_opacity = lerpf(0.55, 1.0, day)
	if _atmo:
		_atmo.set("sky_tint", (a[3] as Color).lerp(b[3], t))
		_atmo.set("fog_tint", (a[4] as Color).lerp(b[4], t))
		_atmo.set("ambient_tint", (a[5] as Color).lerp(b[5], t))
		_atmo.set("ambient_mult", lerpf(a[6], b[6], t))
		_atmo.set("glow_mult", lerpf(a[7], b[7], t))
	if _ambience and _ambience.has_method("set_night"):
		_ambience.set_night(1.0 - day)
