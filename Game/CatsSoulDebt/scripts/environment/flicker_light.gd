extends Light3D
## Мерцание огня: свечи, камин, факелы.

@export var strength: float = 0.25
@export var speed: float = 6.0

var _base_energy: float
var _noise := FastNoiseLite.new()
var _time: float


func _ready() -> void:
	_base_energy = light_energy
	_noise.seed = randi()
	_noise.frequency = 1.0
	_time = randf() * 100.0


func _process(delta: float) -> void:
	_time += delta * speed
	light_energy = _base_energy * (1.0 + _noise.get_noise_1d(_time) * strength)
