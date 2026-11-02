extends Camera3D
## Камера «диорамы»: фиксированный наклон, узкий FOV, плавно следует за целью.
## Тряска (shake) — сдвигом кадра h_offset/v_offset, слежение за целью она не трогает.

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(0.0, 9.0, 11.0)
@export var follow_speed: float = 5.0
## Наибольший сдвиг кадра при тряске, метры.
@export var shake_amplitude: float = 0.35

var _target: Node3D
var _trauma: float = 0.0
var _shake_time: float = 0.0


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target:
		global_position = _target.global_position + offset
		look_at(_target.global_position, Vector3.UP)


## Добавляет тряску: strength 0..1, затухает примерно за полсекунды.
func shake(strength: float) -> void:
	_trauma = clampf(_trauma + strength, 0.0, 1.0)


## Мгновенно перенести камеру к цели (после возрождения).
func snap_to_target() -> void:
	if _target:
		global_position = _target.global_position + offset


func _process(delta: float) -> void:
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
