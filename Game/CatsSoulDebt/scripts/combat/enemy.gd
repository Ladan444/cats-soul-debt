class_name Enemy
extends CharacterBody3D
## Основа врага (COMBAT_SPEC, раздел 3): здоровье, получение ударов, отброс, вспышка, цифры урона,
## «Метка часового», смерть с выпадением гелиосов и возрождение (после смерти Рэя).
## Тело, коллизию и спрайт враг собирает сам — в сцене достаточно узла со скриптом наследника.
## Наследники задают лист, анимации и поведение в _think().

signal killed(enemy: Enemy)

@export var max_hp: float = 50.0
@export var attack_damage: float = 10.0
@export var move_speed: float = 2.0
@export var aggro_range: float = 7.0
@export var reward_min: int = 0
@export var reward_max: int = 0
## Радиус тела: для коллизии и для попаданий (удар достаёт до края, а не до центра).
@export var hit_radius: float = 0.4
## Насколько враг поддаётся отбросу (1 — полностью).
@export var knockback_scale: float = 1.0
## Цвет брызг при попадании и смерти (вода, туман, солома).
@export var hit_color: Color = Color("d8d0c0")
## Область блуждания вокруг места появления (решение автора: потеряв Рэя, враг бродит по своей области,
## а не возвращается на точку). 0 — стоит на месте.
@export var wander_radius: float = 4.0
## Пауза между переходами, секунды (случайная в пределах).
@export var wander_pause: Vector2 = Vector2(1.5, 4.0)
## Звуки (имена Audio.SFX; пусто — без звука): удар по врагу, его атака (при входе в состояние из attack_states),
## «заметил Рэя» (выход из idle), смерть.
@export var hit_sound: String = "hit"
@export var attack_sound: String = ""
@export var aggro_sound: String = ""
@export var death_sound: String = ""
var attack_states: PackedStringArray = ["strike", "leap"]

var hp: float
var sprite: DirectionalSprite
var player: Node3D
var spawn_position: Vector3
var dead: bool = false
## Скорость отброса — гасится трением, складывается с собственным движением.
var knock: Vector3 = Vector3.ZERO
var state: String = "idle"
var state_time: float = 0.0
var facing: Vector3 = Vector3.RIGHT

var _mark_time: float = 0.0
var _mark_sprite: Sprite3D
var _agent: NavigationAgent3D
var _repath: float = 0.0
var _wander_target: Vector3 = Vector3.INF
var _wander_wait: float = 0.0
var _wander_stuck: float = 0.0


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("enemies")
	collision_layer = CombatFX.LAYER_ENEMY
	collision_mask = CombatFX.LAYER_WORLD | CombatFX.LAYER_PLAYER | CombatFX.LAYER_ENEMY
	spawn_position = global_position
	var shape := CapsuleShape3D.new()
	shape.radius = hit_radius
	shape.height = maxf(1.0, hit_radius * 2.0)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	cs.shape = shape
	cs.position.y = shape.height / 2.0
	add_child(cs)
	sprite = _make_sprite()
	sprite.name = "Sprite3D"
	add_child(sprite)
	CombatFX.setup_sprite(sprite)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.4
	_agent.target_desired_distance = 0.4
	_agent.radius = hit_radius
	add_child(_agent)
	hp = max_hp


## Наследник создаёт спрайт со своим листом и списком анимаций.
func _make_sprite() -> DirectionalSprite:
	return DirectionalSprite.new()


func is_alive() -> bool:
	return not dead and visible


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
	if _mark_time > 0.0:
		_mark_time -= delta
		if _mark_time <= 0.0:
			_clear_mark()
		elif _mark_sprite:
			_mark_sprite.position.y = sprite.position.y + 1.1 + sin(Time.get_ticks_msec() / 150.0) * 0.05
	if dead:
		return
	# Пока Рэй без управления (реплики находки, переход между локациями) — враги замирают: иначе засада
	# била бы его, стоящего с открытым окном реплик (душа Йорга в трапезной).
	if player and player.get("input_locked"):
		velocity = Vector3(0, velocity.y, 0)
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return
	state_time += delta
	var wish := _think(delta)
	knock = knock.move_toward(Vector3.ZERO, 18.0 * delta)
	velocity.x = wish.x + knock.x
	velocity.z = wish.z + knock.z
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()


## Поведение: возвращает желаемую скорость по XZ. Переопределяется.
func _think(_delta: float) -> Vector3:
	return Vector3.ZERO


## Направление движения к цели в обход препятствий (по навигационной сетке сцены).
## Если сетки нет или путь не найден — напрямик.
func path_direction(target: Vector3, delta: float) -> Vector3:
	var direct := target - global_position
	direct.y = 0
	if NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) == 0:
		return direct.normalized()
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.25
		# Сетка запекается с шагом по высоте и может лежать выше ступней (в Рубеже — на 0,5 м). Агент
		# сравнивает расстояние до точки пути в 3D и без поправки «не доходит» до неё — враг дёргается на месте.
		# Считаем каждый раз: при появлении враг ещё падает на пол, и разница тогда неверная.
		if is_on_floor():
			var on_mesh := NavigationServer3D.map_get_closest_point(_agent.get_navigation_map(), global_position)
			_agent.path_height_offset = on_mesh.y - global_position.y
		_agent.target_position = target
	if _agent.is_navigation_finished():
		return direct.normalized()
	var next := _agent.get_next_path_position() - global_position
	next.y = 0
	# В проёме открытой двери сетки нет (мостик NavigationLink3D), и путь начинается с её края позади.
	# Если эта точка близко позади, а следующая — впереди, идём к следующей, а не разворачиваемся.
	var path := _agent.get_current_navigation_path()
	var i := _agent.get_current_navigation_path_index()
	if i + 1 < path.size() and next.length() < 0.8:
		var after := path[i + 1] - global_position
		after.y = 0
		if next.dot(after) < 0.0:
			next = after
	return next.normalized() if next.length_squared() > 0.0001 else direct.normalized()


## Блуждание по области вокруг места появления: идёт к случайной точке (на навигационной сетке),
## постояв, выбирает следующую. Если оказался за пределами области (ушёл в погоне) — первым делом
## возвращается в неё, но не на исходную точку. Возвращает желаемую скорость (speed — доля move_speed).
func wander(delta: float, speed: float = 0.6) -> Vector3:
	if wander_radius <= 0.0:
		return Vector3.ZERO
	if _wander_target == Vector3.INF:
		if _wander_wait > 0.0:
			_wander_wait -= delta
			return Vector3.ZERO
		_wander_target = _pick_wander_point()
		_wander_stuck = 0.0
	var to := _wander_target - global_position
	to.y = 0
	_wander_stuck += delta
	# Дошёл или упёрся (точку не достать) — постоять и выбрать новую.
	if to.length() < 0.5 or _wander_stuck > 8.0:
		_wander_target = Vector3.INF
		_wander_wait = randf_range(wander_pause.x, wander_pause.y)
		return Vector3.ZERO
	var dir := path_direction(_wander_target, delta)
	look_towards(dir)
	return dir * move_speed * speed


func is_wandering() -> bool:
	return _wander_target != Vector3.INF


func _pick_wander_point() -> Vector3:
	var a := randf() * TAU
	var r := wander_radius * sqrt(randf())
	var p := spawn_position + Vector3(cos(a) * r, 0, sin(a) * r)
	var map := _agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) != 0:
		var snapped := NavigationServer3D.map_get_closest_point(map, p)
		# Ближайшая точка сетки не должна уводить за пределы области.
		if Vector2(snapped.x - spawn_position.x, snapped.z - spawn_position.z).length() <= wander_radius + 0.5:
			p = snapped
		else:
			p = spawn_position
	return p


func set_state(new_state: String) -> void:
	# Погоня и бой прерывают блуждание: после них точка выбирается заново (область — от места появления).
	if new_state != "idle":
		_wander_target = Vector3.INF
	if state == "idle" and new_state != "idle" and aggro_sound != "" and not dead:
		Audio.play(aggro_sound, global_position)
	if new_state in attack_states and attack_sound != "":
		Audio.play(attack_sound, global_position)
	state = new_state
	state_time = 0.0


func player_alive() -> bool:
	return player != null and is_instance_valid(player) and player.has_method("is_alive") and player.is_alive()


func to_player() -> Vector3:
	var v := player.global_position - global_position
	v.y = 0
	return v


func look_towards(dir: Vector3) -> void:
	if dir.length_squared() > 0.0001:
		facing = Vector3(dir.x, 0, dir.z).normalized()
		sprite.face(facing)


## Удар по врагу. info: damage, dir (направление удара), knockback, heavy (тяжёлый — сбивает замах).
## Возвращает нанесённый урон (с учётом метки) — 0, если не попали.
func take_hit(info: Dictionary) -> float:
	if dead:
		return 0.0
	var amount: float = info.get("damage", 0.0)
	var color := CombatFX.COLOR_HEAVY if info.get("heavy", false) else CombatFX.COLOR_DAMAGE
	if _mark_time > 0.0:
		amount *= 2.0
		color = Color("c890ff")
		_clear_mark()
	hp -= amount
	Audio.play(hit_sound, global_position)
	if info.get("heavy", false):
		Audio.play("hit_heavy", global_position)
	var dir: Vector3 = info.get("dir", Vector3.ZERO)
	knock += Vector3(dir.x, 0, dir.z).normalized() * float(info.get("knockback", 2.0)) * knockback_scale
	CombatFX.flash(sprite, Color.WHITE)
	CombatFX.damage_number(global_position + Vector3(0, sprite.position.y + 0.6, 0), amount, color)
	# Искры от клинка и брызги «тела» — в сторону удара.
	var hit_point := global_position + Vector3(0, sprite.position.y, 0) - Vector3(dir.x, 0, dir.z).normalized() * hit_radius * 0.5
	CombatFX.burst(hit_point, Color("fff4d0"), dir, 6 if not info.get("heavy", false) else 12, 4.5, 6.0, 0.05, 0.2)
	CombatFX.burst(hit_point, hit_color, dir, 8, 3.0, 10.0, 0.08, 0.45)
	if hp <= 0.0:
		die()
	else:
		_on_hurt(info)
	return amount


## Реакция на удар (оглушение и т. п.). Переопределяется.
func _on_hurt(_info: Dictionary) -> void:
	pass


func die() -> void:
	dead = true
	hp = 0.0
	knock = Vector3.ZERO
	velocity = Vector3.ZERO
	$Collision.set_deferred("disabled", true)
	_clear_mark()
	if death_sound != "":
		Audio.play(death_sound, global_position)
	CombatFX.burst(global_position + Vector3(0, 0.5, 0), hit_color, Vector3.ZERO, 24, 3.5, 8.0, 0.09, 0.7)
	_drop_reward()
	if sprite.has_animation("death"):
		sprite.play("death", true)
		await sprite.animation_finished
		await get_tree().create_timer(0.3).timeout
	if dead:
		visible = false
	killed.emit(self)


func _drop_reward() -> void:
	var total := randi_range(reward_min, reward_max)
	if total <= 0:
		return
	# Две-три монеты разлетаются вокруг.
	var coins := clampi(total / 4, 1, 3)
	for i in coins:
		var share := total / coins + (total % coins if i == 0 else 0)
		HeliosPickup.spawn(get_parent(), global_position + Vector3(0, 0.3, 0), share)


## Возвращение на место (после смерти Рэя враги появляются снова).
func respawn() -> void:
	dead = false
	visible = true
	hp = max_hp
	knock = Vector3.ZERO
	velocity = Vector3.ZERO
	global_position = spawn_position
	$Collision.set_deferred("disabled", false)
	_clear_mark()
	CombatFX.tint(sprite, Color.WHITE, 0.0)
	_wander_target = Vector3.INF
	_wander_wait = randf_range(wander_pause.x, wander_pause.y)
	set_state("idle")
	sprite.play("idle", true)


## «Метка часового»: следующее попадание по врагу ×2.
func mark(duration: float) -> void:
	_mark_time = duration
	if _mark_sprite == null:
		_mark_sprite = Sprite3D.new()
		_mark_sprite.texture = load("res://assets/ui/spark_full.png")
		_mark_sprite.modulate = Color(0.85, 0.55, 1.0)
		_mark_sprite.shaded = false
		_mark_sprite.pixel_size = 0.035
		_mark_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_mark_sprite.no_depth_test = true
		_mark_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		add_child(_mark_sprite)
	_mark_sprite.visible = true


func _clear_mark() -> void:
	_mark_time = 0.0
	if _mark_sprite:
		_mark_sprite.visible = false
