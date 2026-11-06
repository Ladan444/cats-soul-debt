extends Enemy
## Квалд (COMBAT_SPEC, раздел 3а): лягушка с копьём и щитом, посты у воды по 3 и больше.
## Щит спереди режет урон до 30 %, тяжёлый 3-й удар комбо выбивает его — квалд открыт. Копьё — длинный
## выпад. С 4–8 м кидает грязь дугой (Lobbed): попадание замедляет и слепит Рэя. В строю: ближний к Рэю
## держит щит и колет, остальные держатся за ним и кидают грязь. Цифры — BALANCE.md 3.7.

const SHEET := preload("res://assets/sprites/kvald/kvald_combat.png")
const REACH := 1.8
const WINDUP := 0.5
const STRIKE := 0.25
const RECOVER := 0.8
const THROW_WINDUP := 0.6
const THROW_COOLDOWN := 5.0
const THROW_MIN := 4.0
const THROW_MAX := 8.0
const GUARD_BROKEN := 1.2
## Щит — сектор перед квалдом (половина угла, градусы) и доля урона, что проходит сквозь него.
const SHIELD_HALF_ANGLE := 60.0
const SHIELD_PASS := 0.3
const MUD_INFO := {"damage": 8.0, "knockback": 1.5, "slow": 3.0, "blind": 3.0}

var _struck: bool = false
var _throw_cd: float = 0.0


func _init() -> void:
	max_hp = 35.0
	attack_damage = 28.0
	move_speed = 1.8
	aggro_range = 9.0
	reward_min = 5
	reward_max = 8
	hit_radius = 0.45
	knockback_scale = 0.5
	wander_radius = 2.0
	hit_color = Color("6a8a4a")
	hit_sound = "hit"
	attack_sound = "enemy_swing"
	aggro_sound = "creature_growl"
	death_sound = "creature_death"


func _ready() -> void:
	super()
	_throw_cd = randf_range(1.0, 3.0)


func _make_sprite() -> DirectionalSprite:
	var s := DirectionalSprite.new()
	s.texture = SHEET
	s.animations = [
		{"name": "idle", "frames": 4, "fps": 3.0, "loop": true},
		{"name": "walk", "frames": 4, "fps": 6.0, "loop": true},
		{"name": "attack", "frames": 4, "fps": 1.0, "loop": false},
		{"name": "throw", "frames": 4, "fps": 1.0, "loop": false},
		{"name": "death", "frames": 4, "fps": 8.0, "loop": false},
	]
	s.pixel_size = 0.025
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.position.y = 0.9
	return s


## Ближе всех к Рэю из живых квалдов поста (в 10 м) — он «щит» строя, остальные кидают грязь.
func _is_front() -> bool:
	var mine := global_position.distance_to(player.global_position)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e.get_script() == get_script() and e.is_alive() \
				and (e as Node3D).global_position.distance_to(global_position) < 10.0 \
				and (e as Node3D).global_position.distance_to(player.global_position) < mine:
			return false
	return true


func _think(delta: float) -> Vector3:
	if not player_alive():
		if state != "idle":
			set_state("idle")
		sprite.play("idle")
		return Vector3.ZERO
	var to := to_player()
	var dist := to.length()
	_throw_cd -= delta
	match state:
		"idle":
			if dist < aggro_range:
				set_state("chase")
			else:
				var v := wander(delta, 0.5)
				sprite.play("walk" if v.length_squared() > 0.01 else "idle")
				return v
		"chase":
			if dist > aggro_range * 1.6:
				set_state("idle")
				return Vector3.ZERO
			look_towards(to)
			var front := _is_front()
			if dist < REACH and front:
				_struck = false
				set_state("windup")
			elif _throw_cd <= 0.0 and dist >= THROW_MIN and dist <= THROW_MAX:
				set_state("throw")
			else:
				# Строй: передний идёт на Рэя, задние держатся на дистанции броска.
				var speed := 1.0
				if not front:
					if dist < THROW_MIN:
						speed = -0.7
					elif dist < THROW_MAX - 1.0:
						sprite.play("idle")
						return Vector3.ZERO
				sprite.play("walk")
				return path_direction(player.global_position, delta) * move_speed * speed
		"windup":
			if state_time < WINDUP * 0.5:
				look_towards(to)
			sprite.show_frame("attack", 0)
			CombatFX.tint(sprite, Color("e8f0a0"), 0.2 + 0.3 * (0.5 + 0.5 * sin(state_time * 30.0)))
			if state_time >= WINDUP:
				CombatFX.tint(sprite, Color.WHITE, 0.0)
				set_state("strike")
		"strike":
			sprite.show_frame("attack", 1 if state_time < STRIKE * 0.5 else 2)
			if not _struck and state_time >= 0.05:
				_struck = true
				if player in CombatFX.targets_in_arc(global_position, facing, REACH + 0.4, 40.0, "player"):
					player.take_hit({"damage": attack_damage, "dir": facing, "knockback": 5.0})
			if state_time >= STRIKE:
				set_state("recover")
			elif state_time < 0.12:
				return facing * 2.0
		"recover":
			sprite.show_frame("attack", 3)
			if state_time >= RECOVER:
				set_state("chase")
		"throw":
			look_towards(to)
			sprite.show_frame("throw", 0)
			if state_time >= THROW_WINDUP:
				_throw_mud()
				_throw_cd = THROW_COOLDOWN + randf_range(-0.5, 1.0)
				set_state("thrown")
		"thrown":
			# Сам бросок виден: кадры 1–2 листа, потом обычная пауза.
			sprite.show_frame("throw", 1 if state_time < 0.2 else 2)
			if state_time >= 0.4:
				set_state("recover")
		"broken":
			# Щит выбит — открыт со всех сторон.
			sprite.show_frame("attack", 3)
			if state_time >= GUARD_BROKEN:
				set_state("chase")
	return Vector3.ZERO


func _throw_mud() -> void:
	var from := global_position + Vector3(0, 1.4, 0)
	var at: Vector3 = player.global_position
	Lobbed.throw(get_parent(), from, Vector3(at.x, global_position.y, at.z), 0.75, 0.7, MUD_INFO, Color("5c4630"), 0.18, 1.8)
	Audio.play("swing", global_position)


## Удар спереди принимает щит (30 % урона), кроме тяжёлого — тот выбивает щит. Сзади и сбоку — полный.
func take_hit(info: Dictionary) -> float:
	if dead:
		return 0.0
	var dir: Vector3 = info.get("dir", Vector3.ZERO)
	var from_front := Vector3(-dir.x, 0, -dir.z).normalized().dot(facing) > cos(deg_to_rad(SHIELD_HALF_ANGLE))
	if from_front and state != "broken" and state != "idle":
		if info.get("heavy", false):
			set_state("broken")
			CombatFX.float_text(global_position + Vector3(0, 2.2, 0), "Щит выбит", Color("e6d6b0"))
		else:
			info = info.duplicate()
			info["damage"] = float(info.get("damage", 0.0)) * SHIELD_PASS
			info["knockback"] = float(info.get("knockback", 2.0)) * 0.3
			Audio.play("hit_armor", global_position)
			CombatFX.burst(global_position + Vector3(0, 1.0, 0) + facing * 0.4, Color("fff0b0"), -dir, 10, 4.0, 6.0, 0.05, 0.25)
	return super(info)


func _on_hurt(_info: Dictionary) -> void:
	if state == "idle":
		set_state("chase")


func set_state(new_state: String) -> void:
	# Подсветка замаха гаснет при любом выходе из него (щит выбит, смерть Рэя).
	if state == "windup" and new_state != "windup":
		CombatFX.tint(sprite, Color.WHITE, 0.0)
	super(new_state)


func die() -> void:
	CombatFX.tint(sprite, Color.WHITE, 0.0)
	super()


func respawn() -> void:
	super()
	_throw_cd = randf_range(1.0, 3.0)
