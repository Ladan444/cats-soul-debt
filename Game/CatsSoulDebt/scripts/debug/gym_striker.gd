extends Node3D
## Источник ударов по Рэю на арене баланса M01: руна бьёт с заданным интервалом и уроном.
## Считает только дошедшие удары (неуязвимость Рэя уважается), а смертельный удар не наносит:
## вместо этого показывает номер удара и через паузу восстанавливает HP. Так плейтест
## не трогает реальную смерть, счётчик смертей и потерю гелиосов.

signal struck(hit_number: int, amount: float)
signal lethal(hit_number: int)
signal run_reset()

## Урон одного удара (до защиты Рэя), как у врага.
@export var damage: float = 20.0
## Секунды между ударами.
@export var interval: float = 1.2
## Бить автоматически; по умолчанию выключено, чтобы не мешать замеру DPS.
@export var auto: bool = false

## Сколько ударов дошло с прошлого сброса.
var hits: int = 0
var _timer: float = 0.0
var _pause: float = 0.0
var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _pulse_tween: Tween


func _ready() -> void:
	add_to_group("gym_striker")
	_build_visual()


func _process(delta: float) -> void:
	if _pause > 0.0:
		_pause = maxf(_pause - delta, 0.0)
		if _pause == 0.0:
			_restart_after_lethal()
		return
	if not auto:
		return
	_timer += delta
	if _timer >= interval:
		_timer = 0.0
		strike()


## Один удар по Рэю. Возвращает true, если удар дошёл.
func strike() -> bool:
	if _pause > 0.0:
		return false
	var player_node := get_tree().get_first_node_in_group("player")
	if player_node == null or not player_node.has_method("take_hit") or PlayerState.hp <= 0.0:
		return false
	var effective := damage * 100.0 / (100.0 + PlayerState.defense)
	if PlayerState.hp - effective <= 0.0:
		hits += 1
		lethal.emit(hits)
		_pulse(Color("e04a3a"))
		_pause = 2.0
		return false
	var player := player_node as Node3D
	var dir := player.global_position - global_position
	dir.y = 0.0
	var dealt: float = player_node.call("take_hit", {
		"damage": damage,
		"dir": dir.normalized() if dir.length_squared() > 0.001 else Vector3.BACK,
		"knockback": 0.0,
	})
	if dealt <= 0.0:
		return false
	hits += 1
	struck.emit(hits, dealt)
	_pulse(Color("e8a04a"))
	return true


## Сброс замера: полное HP Рэя, счётчик с нуля, пауза снята.
func reset_run() -> void:
	_pause = 0.0
	_timer = 0.0
	hits = 0
	PlayerState.heal(PlayerState.max_hp)
	run_reset.emit()


func _restart_after_lethal() -> void:
	PlayerState.heal(PlayerState.max_hp)
	hits = 0
	_timer = 0.0
	run_reset.emit()


## Оценка «сколько ударов выдержит Рэй» при текущих цифрах, без реального боя.
func hits_to_die() -> int:
	var effective := damage * 100.0 / (100.0 + PlayerState.defense)
	return int(ceil(PlayerState.max_hp / maxf(effective, 0.01)))


func _build_visual() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.32
	mesh.outer_radius = 0.46
	mesh.rings = 16
	mesh.ring_segments = 8
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color("e8a04a")
	_mat.emission_enabled = true
	_mat.emission = Color("e8a04a")
	_mat.emission_energy_multiplier = 3.0
	_ring = MeshInstance3D.new()
	_ring.name = "Rune"
	_ring.mesh = mesh
	_ring.material_override = _mat
	_ring.position.y = 0.1
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.position.y = 0.7
	_light.omni_range = 4.0
	_light.light_color = Color("e8a04a")
	_light.light_energy = 1.0
	add_child(_light)


func _pulse(color: Color) -> void:
	if _mat:
		_mat.emission = color
		_mat.albedo_color = color
	if _pulse_tween:
		_pulse_tween.kill()
	_ring.scale = Vector3.ONE
	_pulse_tween = create_tween()
	_pulse_tween.set_parallel(true)
	_pulse_tween.tween_property(_ring, "scale", Vector3(1.5, 1.5, 1.5), 0.08)
	_pulse_tween.tween_property(_light, "light_energy", 3.0, 0.08)
	_pulse_tween.chain().tween_property(_ring, "scale", Vector3.ONE, 0.22)
	_pulse_tween.parallel().tween_property(_light, "light_energy", 1.0, 0.22)
