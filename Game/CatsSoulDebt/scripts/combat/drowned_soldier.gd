extends Enemy
## Утопший солдат (COMBAT_SPEC, раздел 3): медленно бредёт к Рэю, на дистанции удара — долгий
## заметный замах (глаза вспыхивают фиолетовым), рубящий удар с выпадом, потом долго открыт.
## Обычные удары Рэя замах не сбивают — только тяжёлый финальный. Без Рэя бродит по своей области (Enemy.wander).

const SHEET := preload("res://assets/sprites/drowned/drowned_combat.png")
const WINDUP := 0.6
const STRIKE := 0.3
const RECOVER := 1.0
const STAGGER := 0.45
const REACH := 1.5
const LUNGE_SPEED := 2.5

var _struck: bool = false


func _init() -> void:
	max_hp = 45.0
	attack_damage = 30.0
	move_speed = 1.6
	aggro_range = 9.0
	reward_min = 8
	reward_max = 12
	hit_radius = 0.4
	knockback_scale = 0.45
	hit_color = Color("5a7a86")
	hit_sound = "hit_armor"
	attack_sound = "enemy_swing"
	aggro_sound = "soldier_moan"
	death_sound = "soldier_death"


func _ready() -> void:
	super()
	# Лист тёмный: на тёмном полу Рубежа сливался с ним. Свой свет и холодный контур — отсвет Тихой Воды.
	var mat := sprite.material_override as ShaderMaterial
	mat.set_shader_parameter("self_light", 0.55)
	mat.set_shader_parameter("rim", 0.55)


func _make_sprite() -> DirectionalSprite:
	var s := DirectionalSprite.new()
	s.texture = SHEET
	s.animations = [
		{"name": "idle", "frames": 4, "fps": 3.0, "loop": true},
		{"name": "walk", "frames": 4, "fps": 5.0, "loop": true},
		{"name": "attack", "frames": 4, "fps": 1.0, "loop": false},
		{"name": "death", "frames": 4, "fps": 8.0, "loop": false},
	]
	_setup_sprite(s, 0.9)
	return s


static func _setup_sprite(s: Sprite3D, y: float) -> void:
	s.pixel_size = 0.025
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.position.y = y


func _think(delta: float) -> Vector3:
	if not player_alive():
		if state != "idle":
			_reset_tint()
			set_state("idle")
		sprite.play("idle")
		return Vector3.ZERO
	var to := to_player()
	var dist := to.length()
	match state:
		"idle":
			if dist < aggro_range:
				set_state("chase")
			else:
				var v := wander(delta)
				sprite.play("walk" if v.length_squared() > 0.01 else "idle")
				return v
		"chase":
			sprite.play("walk")
			if dist > aggro_range * 1.6:
				set_state("idle")
			elif dist < REACH:
				look_towards(to)
				set_state("windup")
				_struck = false
			else:
				var dir := path_direction(player.global_position, delta)
				look_towards(dir)
				return dir * move_speed
		"windup":
			# Первую половину замаха ещё доворачивается к Рэю — потом удар уже не отменить.
			if state_time < WINDUP * 0.5:
				look_towards(to)
			sprite.show_frame("attack", 0)
			# Замах читаемый: солдат пульсирует фиолетовым светом Тихой Воды.
			var pulse := 0.5 + 0.5 * sin(state_time * 30.0)
			CombatFX.tint(sprite, Color("b070ff"), 0.15 + pulse * 0.35)
			if state_time >= WINDUP:
				_reset_tint()
				set_state("strike")
		"strike":
			sprite.show_frame("attack", 1 if state_time < STRIKE * 0.4 else 2)
			if not _struck and state_time >= 0.06:
				_struck = true
				_hit_player()
			if state_time >= STRIKE:
				set_state("recover")
			elif state_time < 0.15:
				return facing * LUNGE_SPEED
		"recover":
			sprite.show_frame("attack", 3)
			if state_time >= RECOVER:
				set_state("chase")
		"stagger":
			sprite.show_frame("attack", 0)
			if state_time >= STAGGER:
				set_state("chase")
	return Vector3.ZERO


func _hit_player() -> void:
	if player in CombatFX.targets_in_arc(global_position, facing, REACH + 0.4, 70.0, "player"):
		player.take_hit({"damage": attack_damage, "dir": facing, "knockback": 6.0, "mist": true})


func _on_hurt(info: Dictionary) -> void:
	if state == "idle":
		set_state("chase")
	if info.get("heavy", false) and state in ["windup", "strike", "chase"]:
		_reset_tint()
		set_state("stagger")


func _reset_tint() -> void:
	CombatFX.tint(sprite, Color.WHITE, 0.0)


func die() -> void:
	_reset_tint()
	super()
