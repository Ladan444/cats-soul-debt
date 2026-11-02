extends Enemy
## Голем-шахтёр — заколдованный баран (COMBAT_SPEC, раздел 3а). Крупный и тяжёлый: отброс почти не действует,
## обычные удары замах не сбивают — шатается, только получив POISE_SHARE здоровья за POISE_WINDOW секунд.
## Вблизи — широкий удар кайлом или удар по земле (волна вокруг, оглушает; метка круга заранее); издали —
## бросок валуна в место, где стоит Рэй (метка-тень). boss = true — мини-босс Заброшенной шахты: больше здоровья
## и урона, со второй половины здоровья удар по земле дважды подряд и обвал камней с потолка. Цифры — BALANCE.md 3.7.

const SHEET := preload("res://assets/sprites/mine_golem/mine_golem_combat.png")
const REACH := 2.4
const SWING_WINDUP := 0.8
const SWING := 0.3
const RECOVER := 1.0
const SLAM_WINDUP := 1.2
const SLAM_RADIUS := 3.0
const SLAM_COOLDOWN := 6.0
const THROW_LIFT := 1.0
const THROW_MIN := 5.0
const THROW_MAX := 10.0
const THROW_COOLDOWN := 5.0
const BOULDER_RADIUS := 1.5
const POISE_SHARE := 0.4
const POISE_WINDOW := 3.0
const STAGGER := 1.5
const ROCKFALL_EVERY := 4.0

@export var boss: bool = false

var _struck: bool = false
var _slam_cd: float = 2.0
var _throw_cd: float = 2.0
var _slams_left: int = 0
var _poise: Array = []  # [время, урон]
var _rockfall: float = ROCKFALL_EVERY
var _marker: Node3D


func _init() -> void:
	max_hp = 150.0
	attack_damage = 35.0
	move_speed = 1.3
	aggro_range = 10.0
	reward_min = 25
	reward_max = 35
	hit_radius = 0.8
	knockback_scale = 0.1
	wander_radius = 3.0
	hit_color = Color("8a8790")
	hit_sound = "hit_armor"
	attack_sound = "enemy_swing"
	aggro_sound = "soldier_moan"
	death_sound = "soldier_death"


func _ready() -> void:
	if boss:
		max_hp = 400.0
		attack_damage = 40.0
		reward_min = 120
		reward_max = 120
	super()


func _make_sprite() -> DirectionalSprite:
	var s := DirectionalSprite.new()
	s.texture = SHEET
	s.animations = [
		{"name": "idle", "frames": 4, "fps": 2.5, "loop": true},
		{"name": "walk", "frames": 4, "fps": 4.0, "loop": true},
		{"name": "attack", "frames": 4, "fps": 1.0, "loop": false},
		{"name": "slam", "frames": 4, "fps": 1.0, "loop": false},
		{"name": "throw", "frames": 4, "fps": 1.0, "loop": false},
		{"name": "death", "frames": 4, "fps": 6.0, "loop": false},
	]
	s.pixel_size = 0.025 * (1.25 if boss else 1.0)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.position.y = 1.25 * (1.25 if boss else 1.0)
	return s


func _phase_two() -> bool:
	return boss and hp <= max_hp * 0.5


func _think(delta: float) -> Vector3:
	if not player_alive():
		if state != "idle":
			set_state("idle")
		sprite.play("idle")
		return Vector3.ZERO
	var to := to_player()
	var dist := to.length()
	_slam_cd -= delta
	_throw_cd -= delta
	if _phase_two() and state != "idle":
		_rockfall -= delta
		if _rockfall <= 0.0:
			_rockfall = ROCKFALL_EVERY
			_drop_rocks()
	match state:
		"idle":
			if dist < aggro_range:
				set_state("chase")
			else:
				var v := wander(delta, 0.5)
				sprite.play("walk" if v.length_squared() > 0.01 else "idle")
				return v
		"chase":
			if dist > aggro_range * 1.8 and not boss:
				set_state("idle")
				return Vector3.ZERO
			look_towards(to)
			if dist < SLAM_RADIUS - 0.5 and _slam_cd <= 0.0:
				_slams_left = 2 if _phase_two() else 1
				_start_slam()
			elif dist < REACH:
				_struck = false
				set_state("windup")
			elif dist >= THROW_MIN and dist <= THROW_MAX and _throw_cd <= 0.0:
				set_state("lift")
			else:
				sprite.play("walk")
				return path_direction(player.global_position, delta) * move_speed
		"windup":
			if state_time < SWING_WINDUP * 0.5:
				look_towards(to)
			sprite.show_frame("attack", 0)
			CombatFX.tint(sprite, Color("b070ff"), 0.15 + 0.2 * (0.5 + 0.5 * sin(state_time * 25.0)))
			if state_time >= SWING_WINDUP:
				CombatFX.tint(sprite, Color.WHITE, 0.0)
				set_state("swing")
		"swing":
			sprite.show_frame("attack", 1 if state_time < SWING * 0.5 else 2)
			if not _struck and state_time >= 0.06:
				_struck = true
				CombatFX.shake(0.3)
				if player in CombatFX.targets_in_arc(global_position, facing, REACH + 0.4, 90.0, "player"):
					player.take_hit({"damage": attack_damage, "dir": facing, "knockback": 7.0})
			if state_time >= SWING:
				set_state("recover")
		"slam_windup":
			sprite.show_frame("slam", 0 if state_time < SLAM_WINDUP * 0.6 else 1)
			if state_time >= SLAM_WINDUP:
				_slam()
				_slams_left -= 1
				if _slams_left > 0:
					_start_slam()
				else:
					_slam_cd = SLAM_COOLDOWN
					set_state("recover")
		"lift":
			look_towards(to)
			sprite.show_frame("throw", 0)
			if state_time >= THROW_LIFT:
				sprite.show_frame("throw", 1)
				var at: Vector3 = player.global_position
				Lobbed.throw(get_parent(), global_position + Vector3(0, 2.6, 0), Vector3(at.x, global_position.y, at.z),
					0.9, BOULDER_RADIUS, {"damage": attack_damage, "knockback": 6.0}, Color("6e6c74"), 0.45, 2.5)
				_throw_cd = THROW_COOLDOWN
				set_state("recover")
		"recover":
			sprite.show_frame("attack", 3)
			if state_time >= RECOVER:
				set_state("chase")
		"stagger":
			sprite.show_frame("attack", 3)
			if state_time >= STAGGER:
				set_state("chase")
	return Vector3.ZERO


## Подсветка замаха кайлом гаснет при любом выходе из него (удар по земле, бросок, стойкость).
func set_state(new_state: String) -> void:
	if state == "windup" and new_state != "windup":
		CombatFX.tint(sprite, Color.WHITE, 0.0)
	super(new_state)


func _start_slam() -> void:
	_struck = true
	set_state("slam_windup")
	_marker = Lobbed.ground_marker(get_parent(), global_position, SLAM_RADIUS, SLAM_WINDUP, Color("b070ff"))


## Удар по земле: волна вокруг — урон и оглушение всем, кто в круге (рывок/«Призрачный шаг» — неуязвимость).
func _slam() -> void:
	CombatFX.shake(0.7)
	Audio.play("break", global_position)
	for i in 3:
		var a := TAU * i / 3.0
		CombatFX.burst(global_position + Vector3(cos(a), 0.2, sin(a)) * 1.5, Color("8a7a6a"), Vector3(cos(a), 0, sin(a)), 14, 4.0, 8.0, 0.1, 0.6)
	var d := player.global_position - global_position
	if Vector2(d.x, d.z).length() <= SLAM_RADIUS + 0.3:
		player.take_hit({"damage": attack_damage * 0.85, "dir": Vector3(d.x, 0, d.z).normalized(), "knockback": 0.0, "stun": 1.0})


## Обвал (мини-босс, вторая фаза): три камня падают с потолка вокруг Рэя, места отмечены заранее.
func _drop_rocks() -> void:
	for i in 3:
		var off := Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0)) if i > 0 else Vector3.ZERO
		var at: Vector3 = player.global_position + off
		at.y = global_position.y
		Lobbed.throw(get_parent(), at + Vector3(0, 6.0, 0), at, 1.1, 1.0, {"damage": 25.0, "knockback": 3.0},
			Color("5e5a52"), 0.35, 0.0)


## Стойкость: замах не сбивается обычным ударом; набрав POISE_SHARE урона за POISE_WINDOW — шатается.
func _on_hurt(info: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_poise.append([now, float(info.get("damage", 0.0))])
	_poise = _poise.filter(func(p): return now - p[0] <= POISE_WINDOW)
	var sum := 0.0
	for p in _poise:
		sum += p[1]
	if state == "idle":
		set_state("chase")
	if sum >= max_hp * POISE_SHARE:
		_poise.clear()
		CombatFX.tint(sprite, Color.WHITE, 0.0)
		if _marker and is_instance_valid(_marker):
			_marker.queue_free()
		set_state("stagger")
		CombatFX.float_text(global_position + Vector3(0, 3.2, 0), "Шатается", Color("e6d6b0"))


func die() -> void:
	CombatFX.tint(sprite, Color.WHITE, 0.0)
	if _marker and is_instance_valid(_marker):
		_marker.queue_free()
	super()


func respawn() -> void:
	super()
	_slam_cd = 2.0
	_throw_cd = 2.0
	_poise.clear()
	_rockfall = ROCKFALL_EVERY
