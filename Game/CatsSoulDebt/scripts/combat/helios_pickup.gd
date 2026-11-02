class_name HeliosPickup
extends Area3D
## Монета Гелиос на земле: выпадает из врагов, лежит на месте смерти Рэя (утерянная добыча).
## Подпрыгивает при выпадении, притягивается к Рэю вблизи, подбирается касанием.

const ICON := preload("res://assets/ui/icon_helios.png")
const MAGNET_RANGE := 1.6

var amount: int = 1
## Утерянная при смерти добыча: крупнее, светится фиолетовым и не исчезает.
var lost_pile: bool = false
## Номер отметки смерти в PlayerState.death_marks (у кучки утерянного) — при подборе обнуляется.
var mark_index: int = -1

var _sprite: Sprite3D
var _velocity: Vector3
var _landed: bool = false
var _ground_y: float = 0.0
var _time: float = 0.0
var _player: Node3D


## Бросает монету из точки at: короткий подскок в случайную сторону.
static func spawn(parent: Node, at: Vector3, value: int, pile: bool = false) -> HeliosPickup:
	var p := HeliosPickup.new()
	p.amount = value
	p.lost_pile = pile
	parent.add_child(p)
	p.global_position = at
	p._ground_y = p._find_ground(at)
	if not pile:
		var a := randf() * TAU
		p._velocity = Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 2.2) + Vector3(0, 3.2, 0)
	else:
		p._landed = true
		p.global_position.y = p._ground_y + 0.05
	return p


## Высота пола под точкой (луч сверху по миру): в мире земля не на нуле — монеты и кучки утерянного
## раньше ложались на y = 0,05 и оказывались под рельефом.
func _find_ground(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.2, 0), at - Vector3(0, 30, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else at.y


func _ready() -> void:
	add_to_group("helios_pickups")
	collision_layer = 0
	collision_mask = CombatFX.LAYER_PLAYER
	monitorable = false
	var shape := SphereShape3D.new()
	shape.radius = 0.45
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.3
	add_child(cs)
	_sprite = Sprite3D.new()
	_sprite.texture = ICON
	_sprite.pixel_size = 0.03 if lost_pile else 0.022
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = false
	_sprite.position.y = 0.2
	add_child(_sprite)
	if lost_pile:
		_sprite.modulate = Color(1.3, 1.1, 1.6)
		var light := OmniLight3D.new()
		light.light_color = Color(0.7, 0.5, 1.0)
		light.light_energy = 0.8
		light.omni_range = 2.0
		light.position.y = 0.5
		add_child(light)
		var label := Label3D.new()
		label.text = str(amount)
		label.font = CombatFX.FONT
		label.font_size = 16
		label.pixel_size = 0.012
		label.outline_size = 4
		label.outline_modulate = Color("1e1614")
		label.modulate = Color("c890ff")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		label.position.y = 0.7
		add_child(label)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_time += delta
	if not _landed:
		_velocity.y -= 12.0 * delta
		global_position += _velocity * delta
		if global_position.y <= _ground_y + 0.05:
			global_position.y = _ground_y + 0.05
			_landed = true
		return
	_sprite.position.y = 0.2 + sin(_time * 4.0) * 0.05
	# Рэй мог стоять на месте, пока монета летела, — тогда body_entered уже прошёл.
	for body in get_overlapping_bodies():
		_on_body_entered(body)
		if is_queued_for_deletion():
			return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player and _time > 0.4 and _player.has_method("is_alive") and _player.is_alive():
		var to := _player.global_position - global_position
		to.y = 0
		if to.length() < MAGNET_RANGE:
			global_position += to.normalized() * minf(to.length(), 6.0 * delta)


func _on_body_entered(body: Node3D) -> void:
	# Сигнал касания и проверка пересечений в _physics_process приходят в одном такте — без этой проверки
	# монета засчитывалась дважды (до конца кадра queue_free узел ещё жив).
	if is_queued_for_deletion():
		return
	if not body.is_in_group("player") or not _landed or (body.has_method("is_alive") and not body.is_alive()):
		return
	# Пересечения обновляются шагом физики позже телепорта: после возрождения Рэй ещё «стоит»
	# на месте смерти — проверяем настоящее расстояние.
	var d := body.global_position - global_position
	d.y = 0
	if d.length() > 0.9:
		return
	PlayerState.add_helios(amount)
	PlayerState.claim_death_mark(mark_index)
	Audio.play("coins", global_position)
	queue_free()
