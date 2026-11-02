extends Enemy
## Тренировочное чучело в таверне (COMBAT_SPEC, раздел 3): не атакует, не умирает,
## показывает цифры урона — для проверки комбо и скиллов. Не возрождается вместе с врагами.

const SHEET := preload("res://assets/sprites/dummy/dummy.png")

var _wobble: Tween


func _init() -> void:
	max_hp = 1000000.0
	knockback_scale = 0.0
	hit_radius = 0.35
	hit_color = Color("c8a860")


func _ready() -> void:
	super()
	remove_from_group("enemies")
	collision_layer = CombatFX.LAYER_WORLD
	set_physics_process(false)


func _make_sprite() -> DirectionalSprite:
	var s := DirectionalSprite.new()
	s.texture = SHEET
	s.directions = 1
	s.animations = [{"name": "idle", "frames": 1, "fps": 1.0, "loop": true}]
	s.pixel_size = 0.025
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.position.y = 0.7
	return s


func take_hit(info: Dictionary) -> float:
	var dealt := super(info)
	hp = max_hp
	# Покачивается от удара в сторону удара.
	var side := signf(info.get("dir", Vector3.RIGHT).x)
	if _wobble:
		_wobble.kill()
	_wobble = create_tween()
	_wobble.tween_property(sprite, "position:x", 0.12 * side, 0.05)
	_wobble.tween_property(sprite, "position:x", -0.06 * side, 0.1)
	_wobble.tween_property(sprite, "position:x", 0.0, 0.12)
	return dealt
