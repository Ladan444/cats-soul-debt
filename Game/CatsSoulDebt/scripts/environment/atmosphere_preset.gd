class_name AtmospherePreset
extends Resource
## Атмосфера одной зоны (палитры — по PROJECT_BIBLE). Смешивается AtmosphereBlender.

@export var zone_name: String = ""
## Зона-хаб (таверна): хотбар HUD прячется.
@export var hub: bool = false
## Координата X, с которой начинается зона (переход центрирован на этой границе).
@export var start_x: float = 0.0
@export var background_color: Color = Color.BLACK
@export var ambient_color: Color = Color.WHITE
@export var ambient_energy: float = 0.3
@export var fog_color: Color = Color.GRAY
@export var fog_density: float = 0.02
@export var glow_intensity: float = 1.0
@export var saturation: float = 1.0
@export var exposure: float = 1.0
