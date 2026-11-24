extends Enemy
## Тварь Тихой Воды (COMBAT_SPEC, раздел 3): сгусток фиолетового тумана. Кружит на расстоянии,
## приседает (читаемо, 0,4 с) и прыгает на Рэя. Приземлившись, на миг растекается лужей —
## окно для ударов. Любое попадание сбивает её.

const SHEET := preload("res://assets/sprites/lake_creature/lake_creature_combat.png")
const SPRITE_Y := 0.7
const KEEP_DISTANCE := 3.5
const CROUCH := 0.4
const LEAP := 0.5
const LEAP_HEIGHT := 1.1
const MAX_LEAP := 5.0
const PUDDLE := 0.9
const STAGGER := 0.35

var _cooldown: float = 1.5
var _leap_from: Vector3
var _leap_to: Vector3
var _struck: bool = false
var _orbit_sign: float = 1.0


func _init() -> void:
	max_hp = 25.0
	attack_damage = 27.0
	move_speed = 3.5
	aggro_range = 8.0
	reward_min = 3
	reward_max = 5
	hit_radius = 0.55  # тело на листе ~1,3 м шириной
	knockback_scale = 1.0
	hit_color = Color("a070e0")
	aggro_sound = "creature_growl"
	attack_sound = "creature_leap"
	death_sound = "creature_death"


func _ready() -> void:
	super()
	_orbit_sign = 1.0 if randf() < 0.5 else -1.0


func _make_sprite() -> DirectionalSprite:
	var s := DirectionalSprite.new()
	s.texture = SHEET
	s.directions = 1
	s.animations = [
		{"name": "idle", "frames": 4, "fps": 6.0, "loop": true},
		{"name": "leap", "frames": 4, "fps": 1.0, "loop": false},
		{"name": "hurt", "frames": 2, "fps": 8.0, "loop": false},
		{"name": "death", "frames": 4, "fps": 8.0, "loop": false},
	]
	s.pixel_size = 0.025
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.position.y = SPRITE_Y
	return s


func _think(delta: float) -> Vector3:
	if not player_alive():
		_land_sprite()
		if state != "idle":
			set_state("idle")
		sprite.play("idle")
		return Vector3.ZERO
	var to := to_player()
	var dist := to.length()
	match state:
		"idle":
			sprite.play("idle")
			if dist < aggro_range:
				set_state("hover")
			else:
				return wander(delta, 0.5)
		"hover":
			sprite.play("idle")
			look_towards(to)
			_cooldown -= delta
			if dist > aggro_range * 1.8:
				set_state("idle")
			elif _cooldown <= 0.0 and dist < 6.0:
				set_state("crouch")
			else:
				# Держит дистанцию и кружит вокруг Рэя.
				var radial := to.normalized() * clampf(dist - KEEP_DISTANCE, -1.0, 1.0)
				var tangent := Vector3(-to.z, 0, to.x).normalized() * _orbit_sign * 0.5
				return (radial + tangent) * move_speed * 0.6
		"crouch":
			look_towards(to)
			sprite.show_frame("leap", 0)
			CombatFX.tint(sprite, Color("e0c0ff"), 0.15 + 0.3 * (0.5 + 0.5 * sin(state_time * 30.0)))
			if state_time >= CROUCH:
				CombatFX.tint(sprite, Color.WHITE, 0.0)
				_leap_from = global_position
				var jump := to
				if jump.length() > MAX_LEAP:
					jump = jump.normalized() * MAX_LEAP
				# Чуть дальше Рэя — чтобы отскок мимо был промахом, а не «прилипанием».
				_leap_to = global_position + jump + jump.normalized() * 0.6
				# Прыжок — напрямик, без навигации: точку приземления держим на полу (сетке), иначе Тварь
				# могла перемахнуть край пропасти или упереться в стену на лету.
				var map := _agent.get_navigation_map()
				if NavigationServer3D.map_get_iteration_id(map) != 0:
					var land := NavigationServer3D.map_get_closest_point(map, _leap_to)
					_leap_to = Vector3(land.x, global_position.y, land.z)
				_struck = false
				set_state("leap")
		"leap":
			var t := clampf(state_time / LEAP, 0.0, 1.0)
			# Кадр 2 листа зеркален кадру 1 (хвост перескакивал на другую сторону) — весь полёт один кадр.
			sprite.show_frame("leap", 1)
			sprite.position.y = SPRITE_Y + sin(t * PI) * LEAP_HEIGHT
			if not _struck and player in CombatFX.targets_in_arc(global_position, facing, 0.5, 180.0, "player"):
				_struck = true
				player.take_hit({"damage": attack_damage, "dir": facing, "knockback": 5.0, "mist": true})
			if t >= 1.0:
				_land_sprite()
				CombatFX.burst(global_position + Vector3(0, 0.1, 0), hit_color, Vector3.ZERO, 14, 2.5, 7.0, 0.08, 0.5)
				set_state("puddle")
			else:
				return (_leap_to - _leap_from) / LEAP * Vector3(1, 0, 1)
		"puddle":
			# Лужа — плоский кадр; круглый кадр 3 ряда прыжка — на миг при приземлении.
			if state_time < 0.12:
				sprite.show_frame("leap", 3)
			else:
				sprite.show_frame("hurt", 1)
			if state_time >= PUDDLE:
				_cooldown = randf_range(1.2, 2.2)
				_orbit_sign = -_orbit_sign
				set_state("hover")
		"stagger":
			if state_time >= STAGGER:
				_cooldown = maxf(_cooldown, 0.8)
				set_state("hover")
	return Vector3.ZERO


func _land_sprite() -> void:
	sprite.position.y = SPRITE_Y
	CombatFX.tint(sprite, Color.WHITE, 0.0)


func _on_hurt(_info: Dictionary) -> void:
	_land_sprite()
	set_state("stagger")
	sprite.play("hurt", true)


func die() -> void:
	_land_sprite()
	super()


func respawn() -> void:
	super()
	_land_sprite()
	_cooldown = 1.5
