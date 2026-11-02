extends Enemy
## Кобольд-разбойник «Крыс», банда «Рыжие упыри» (COMBAT_SPEC, раздел 3а). Стая 3–4 (одинаковый pack_id):
## — засада: стая спрятана, пока Рэй не подойдёт к любому из неё на ambush_radius, потом выскакивает
##   (первый удар — не раньше FIRST_STRIKE_DELAY);
## — окружение: каждый занимает своё место на круге вокруг Рэя (первое — за спиной), бьёт с места,
##   одновременно бьют не больше двух;
## — тактика стаи: +50 % урона за каждого другого кобольда рядом с Рэем с другой стороны (до +100 %);
## — при HP ≤ 30 % убегает и возвращается через FLEE_TIME, если стая ещё дерётся; последний — исчезает в дыму
##   без награды. Цифры — BALANCE.md 3.7.

const SHEET := preload("res://assets/sprites/kobold/kobold_combat.png")
const RING := 2.5
const REACH := 1.2
const WINDUP := 0.35
const STRIKE := 0.2
const RECOVER := 0.6
const FIRST_STRIKE_DELAY := 0.8
const FLEE_HP := 0.3
const FLEE_TIME := 6.0
const MAX_ATTACKERS := 2
## Тактика стаи: за каждого другого кобольда в PACK_RANGE от Рэя с другой стороны (угол > PACK_ANGLE) — +PACK_BONUS.
const PACK_RANGE := 3.0
const PACK_ANGLE := 60.0
const PACK_BONUS := 0.5
const PACK_MAX := 1.0

## Стая: кобольды с одинаковым pack_id засаживаются и окружают вместе.
@export var pack_id: String = "pack"
@export var ambush: bool = true
@export var ambush_radius: float = 6.0

var _hidden: bool = false
var _struck: bool = false
var _cooldown: float = 0.0
var _fled: bool = false


func _init() -> void:
	max_hp = 22.0
	attack_damage = 15.0
	move_speed = 3.2
	aggro_range = 10.0
	reward_min = 4
	reward_max = 7
	hit_radius = 0.35
	knockback_scale = 1.2
	wander_radius = 0.0
	hit_color = Color("c8743a")
	attack_sound = "enemy_swing"
	aggro_sound = "creature_growl"
	death_sound = "creature_death"


func _ready() -> void:
	super()
	add_to_group("kobolds")
	if ambush:
		_hide()


func _make_sprite() -> DirectionalSprite:
	var s := DirectionalSprite.new()
	s.texture = SHEET
	s.animations = [
		{"name": "idle", "frames": 4, "fps": 4.0, "loop": true},
		{"name": "walk", "frames": 4, "fps": 9.0, "loop": true},
		{"name": "attack", "frames": 4, "fps": 1.0, "loop": false},
		{"name": "death", "frames": 4, "fps": 8.0, "loop": false},
	]
	s.pixel_size = 0.025
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.position.y = 0.7
	return s


func is_alive() -> bool:
	return super() and not _hidden


func pack() -> Array:
	return get_tree().get_nodes_in_group("kobolds").filter(func(k): return k.pack_id == pack_id)


## В засаде тело остаётся на земле (иначе гравитация утянет его под рельеф), но сквозь него можно пройти,
## и удары его не видят (is_alive — false).
func _hide() -> void:
	_hidden = true
	sprite.visible = false
	$Collision.set_deferred("disabled", false)
	collision_layer = 0
	collision_mask = CombatFX.LAYER_WORLD


## Выскочить из засады (вся стая разом).
func reveal() -> void:
	if not _hidden or dead:
		return
	_hidden = false
	sprite.visible = true
	collision_layer = CombatFX.LAYER_ENEMY
	collision_mask = CombatFX.LAYER_WORLD | CombatFX.LAYER_PLAYER | CombatFX.LAYER_ENEMY
	CombatFX.burst(global_position + Vector3(0, 0.4, 0), Color("6a7a4a"), Vector3.ZERO, 14, 2.5, 6.0, 0.08, 0.5)
	_cooldown = FIRST_STRIKE_DELAY + randf_range(0.0, 0.4)
	set_state("chase")


## Урон удара с тактикой стаи.
func pack_damage() -> float:
	var mine := to_player().normalized()
	var allies := 0
	for k in pack():
		if k == self or not k.is_alive() or k.state == "flee":
			continue
		var v: Vector3 = (k as Node3D).global_position - player.global_position
		v.y = 0
		if v.length() > PACK_RANGE:
			continue
		# Союзник «с другой стороны»: направления от Рэя к нам расходятся больше чем на PACK_ANGLE.
		if (-mine).angle_to(v.normalized()) > deg_to_rad(PACK_ANGLE):
			allies += 1
	return attack_damage * (1.0 + minf(allies * PACK_BONUS, PACK_MAX))


## Место на круге вокруг Рэя: стая делит круг поровну, первое место — за спиной Рэя.
func _ring_point() -> Vector3:
	var fighters := pack().filter(func(k): return k.is_alive() and k.state != "flee")
	fighters.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	var i := maxi(fighters.find(self), 0)
	var back: Vector3 = -player.get("_facing") if player.get("_facing") != null else Vector3.BACK
	var angle := atan2(back.z, back.x) + TAU * i / maxf(fighters.size(), 1.0)
	return player.global_position + Vector3(cos(angle), 0, sin(angle)) * RING


func _attackers() -> int:
	return pack().filter(func(k): return k.state in ["windup", "strike"]).size()


func _think(delta: float) -> Vector3:
	if _hidden:
		if player_alive() and global_position.distance_to(player.global_position) < ambush_radius:
			for k in pack():
				k.reveal()
		return Vector3.ZERO
	if not player_alive():
		if state != "idle":
			set_state("idle")
		sprite.play("idle")
		return Vector3.ZERO
	var to := to_player()
	var dist := to.length()
	_cooldown -= delta
	match state:
		"idle":
			sprite.play("idle")
			if dist < aggro_range:
				set_state("chase")
		"chase":
			var spot := _ring_point()
			var to_spot := spot - global_position
			to_spot.y = 0
			look_towards(to)
			if _cooldown <= 0.0 and dist < REACH + 0.3 and _attackers() < MAX_ATTACKERS:
				_struck = false
				set_state("windup")
			elif to_spot.length() > 0.4:
				sprite.play("walk")
				# Обход по кругу: к своему месту, но не сквозь Рэя.
				var dir := path_direction(spot, delta)
				return dir * move_speed
			else:
				sprite.play("idle")
				# На месте — подшагнуть на удар.
				if _cooldown <= 0.0 and _attackers() < MAX_ATTACKERS:
					return to.normalized() * move_speed
		"windup":
			look_towards(to)
			sprite.show_frame("attack", 0)
			CombatFX.tint(sprite, Color("ffe080"), 0.25 + 0.25 * sin(state_time * 40.0))
			if state_time >= WINDUP:
				CombatFX.tint(sprite, Color.WHITE, 0.0)
				set_state("strike")
		"strike":
			sprite.show_frame("attack", 1 if state_time < STRIKE * 0.5 else 2)
			if not _struck and state_time >= 0.04:
				_struck = true
				if player in CombatFX.targets_in_arc(global_position, facing, REACH + 0.3, 60.0, "player"):
					player.take_hit({"damage": pack_damage(), "dir": facing, "knockback": 3.0})
			if state_time >= STRIKE:
				set_state("recover")
			elif state_time < 0.1:
				return facing * 4.0
		"recover":
			sprite.show_frame("attack", 3)
			if state_time >= RECOVER:
				_cooldown = randf_range(0.8, 1.6)
				set_state("chase")
		"flee":
			sprite.play("walk")
			var away := -to.normalized()
			look_towards(away)
			if state_time >= FLEE_TIME:
				if pack().any(func(k): return k != self and k.is_alive() and k.state != "flee"):
					set_state("chase")
				else:
					_vanish()
			return away * move_speed * 0.9
		"stagger":
			sprite.show_frame("attack", 3)
			if state_time >= 0.3:
				set_state("chase")
	return Vector3.ZERO


func _on_hurt(_info: Dictionary) -> void:
	CombatFX.tint(sprite, Color.WHITE, 0.0)
	if hp <= max_hp * FLEE_HP and not _fled:
		_fled = true
		set_state("flee")
		# Последний из стаи не бегает кругами — сразу дымовая шашка.
		if not pack().any(func(k): return k != self and k.is_alive() and k.state != "flee"):
			_vanish()
		return
	if state in ["windup", "chase", "idle"]:
		set_state("stagger")


## Дымовая шашка: исчезает без награды (до возрождения врагов после смерти Рэя).
func _vanish() -> void:
	CombatFX.burst(global_position + Vector3(0, 0.6, 0), Color("8a8a80"), Vector3.ZERO, 30, 2.0, 5.0, 0.14, 0.9)
	CombatFX.float_text(global_position + Vector3(0, 1.8, 0), "Сбежал", Color("c8c0b0"))
	dead = true
	visible = false
	$Collision.set_deferred("disabled", true)
	killed.emit(self)


func respawn() -> void:
	super()
	_fled = false
	_cooldown = 0.0
	if ambush:
		_hide()
