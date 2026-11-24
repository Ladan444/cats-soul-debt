extends Enemy
## Манекен арены баланса M01 («гимн боя»): не двигается и не атакует, считает попадания и время,
## после смерти возрождается и сообщает замер. Отдельно от training_dummy: тот живёт в таверне
## и никогда не умирает, а здесь нужен цикл «убить — измерить — вернуть».

signal damaged(amount: float)
signal defeated(hits: int, seconds: float)

const SHEET := preload("res://assets/sprites/dummy/dummy.png")
## Пауза перед возвратом манекена, секунды.
const RESPAWN_DELAY := 1.0

## Сколько ударов Рэя выдержал манекен с прошлого сброса.
var hits: int = 0
var first_hit_at: float = -1.0
var _respawn_token: int = 0
var _wobble: Tween


func _init() -> void:
	max_hp = 50.0
	knockback_scale = 0.0
	hit_radius = 0.35
	hit_color = Color("c8a860")


func _ready() -> void:
	super()
	add_to_group("gym_dummy")
	# Манекен не должен попадать в общий список врагов и мешать проходу: он только цель.
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = CombatFX.LAYER_WORLD
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


## Новое здоровье манекена из пульта: сбрасывает и замер, и текущее состояние.
func configure(hp_value: float) -> void:
	max_hp = maxf(1.0, hp_value)
	reset_dummy()


## Вернуть манекен в строй, не меняя max_hp.
func reset_dummy() -> void:
	_respawn_token += 1
	hp = max_hp
	dead = false
	visible = true
	hits = 0
	first_hit_at = -1.0
	var col := get_node_or_null("Collision")
	if col:
		col.set_deferred("disabled", false)
	if sprite:
		sprite.position.x = 0.0


func take_hit(info: Dictionary) -> float:
	if dead:
		return 0.0
	var now := Time.get_ticks_msec() / 1000.0
	if first_hit_at < 0.0:
		first_hit_at = now
	var dealt := super(info)
	if dealt > 0.0:
		hits += 1
		damaged.emit(dealt)
		_wobble_from(info)
	if dead:
		defeated.emit(hits, maxf(now - first_hit_at, 0.0))
		_respawn_later(_respawn_token)
	return dealt


func _wobble_from(info: Dictionary) -> void:
	if _wobble:
		_wobble.kill()
	var side := signf(info.get("dir", Vector3.RIGHT).x)
	_wobble = create_tween()
	_wobble.tween_property(sprite, "position:x", 0.12 * side, 0.05)
	_wobble.tween_property(sprite, "position:x", -0.06 * side, 0.1)
	_wobble.tween_property(sprite, "position:x", 0.0, 0.12)


func _respawn_later(token: int) -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_inside_tree() or token != _respawn_token:
		return
	reset_dummy()
