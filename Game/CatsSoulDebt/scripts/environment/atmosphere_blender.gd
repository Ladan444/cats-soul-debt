class_name AtmosphereBlender
extends WorldEnvironment
## Плавно смешивает атмосферу зон по положению цели (игрока) вдоль оси X.

@export var target_path: NodePath
## Пресеты по возрастанию start_x.
@export var presets: Array[AtmospherePreset] = []
## Ширина полосы перехода на каждой границе, в метрах.
@export var blend_width: float = 6.0

## Поправки времени суток (ставит DayNightCycle): множители цвета неба, тумана и рассеянного света.
var sky_tint := Color.WHITE
var fog_tint := Color.WHITE
var ambient_tint := Color.WHITE
var ambient_mult := 1.0
var glow_mult := 1.0

var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_apply(_target.global_position.x if _target else 0.0)


func _process(_delta: float) -> void:
	if _target:
		_apply(_target.global_position.x)


func _apply(x: float) -> void:
	if presets.is_empty() or environment == null:
		return
	var p := presets[0]
	var bg := p.background_color
	var ambient := p.ambient_color
	var ambient_energy := p.ambient_energy
	var fog := p.fog_color
	var fog_density := p.fog_density
	var glow := p.glow_intensity
	var saturation := p.saturation
	var exposure := p.exposure
	for i in range(1, presets.size()):
		var n := presets[i]
		var t := smoothstep(n.start_x - blend_width * 0.5, n.start_x + blend_width * 0.5, x)
		bg = bg.lerp(n.background_color, t)
		ambient = ambient.lerp(n.ambient_color, t)
		ambient_energy = lerpf(ambient_energy, n.ambient_energy, t)
		fog = fog.lerp(n.fog_color, t)
		fog_density = lerpf(fog_density, n.fog_density, t)
		glow = lerpf(glow, n.glow_intensity, t)
		saturation = lerpf(saturation, n.saturation, t)
		exposure = lerpf(exposure, n.exposure, t)

	environment.background_color = bg * sky_tint
	environment.ambient_light_color = ambient * ambient_tint
	environment.ambient_light_energy = ambient_energy * ambient_mult
	environment.fog_light_color = fog * fog_tint
	environment.fog_density = fog_density
	environment.glow_intensity = glow * glow_mult
	environment.adjustment_saturation = saturation
	environment.tonemap_exposure = exposure
	# Настройка «Яркость».
	environment.adjustment_brightness = Settings.get_value("brightness")


## Пресет зоны, в которой сейчас цель.
func current_preset() -> AtmospherePreset:
	var result: AtmospherePreset = null
	if _target:
		for p in presets:
			if result == null or _target.global_position.x >= p.start_x:
				result = p
	return result


## Название зоны, в которой сейчас цель (для отладки и HUD).
func current_zone_name() -> String:
	var p := current_preset()
	return p.zone_name if p else ""
