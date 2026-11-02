extends Camera3D
## Камера главного меню: медленно плывёт вокруг исходной точки, глядя на цель.

@export var look_target: Vector3 = Vector3.ZERO
@export var sway: Vector3 = Vector3(1.6, 0.35, 0.6)
@export var speed: float = 0.07

var _origin: Vector3
var _time: float = 0.0


func _ready() -> void:
	_origin = position


func _process(delta: float) -> void:
	_time += delta * speed * TAU
	position = _origin + Vector3(sin(_time) * sway.x, sin(_time * 1.7) * sway.y, cos(_time * 0.8) * sway.z)
	look_at(look_target, Vector3.UP)
