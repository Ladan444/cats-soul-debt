extends CharacterBody3D
## Рэй: движение в 2.5D (3D-мир, спрайт-билборд): ходьба, бег, рывок, анимации,
## бой по COMBAT_SPEC: комбо из трёх ударов, доводка на врага, скиллы душ, получение урона.

@export var walk_speed: float = 3.5
@export var run_speed: float = 6.0
@export var acceleration: float = 30.0
@export var dash_speed: float = 12.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.5
## Рывок тратит энергию души (UI_SPEC, раздел 2).
@export var dash_energy_cost: float = 15.0
## Удар: дальность (до края цели) и половина дуги в градусах; доводка на ближайшую цель.
@export var attack_reach: float = 1.3
@export var attack_half_angle: float = 55.0
@export var aim_assist_range: float = 2.5
## Неуязвимость после полученного удара, секунды.
@export var hurt_invulnerability: float = 0.7
## Отладка: облики, переключаемые в мастер-меню отладки (листы в формате DirectionalSprite).
@export var debug_skins: Array[Texture2D] = []
@export var debug_skin_names: PackedStringArray = []

## Комбо (COMBAT_SPEC, раздел 2): замах, активная фаза (тогда бьёт), восстановление — в секундах;
## множитель урона, шаг вперёд за активную фазу (м), отброс, тяжёлый ли удар.
const COMBO := [
	{"anim": "attack1", "windup": 0.12, "active": 0.08, "recover": 0.22, "mult": 1.0, "step": 0.3, "knock": 2.5, "heavy": false},
	{"anim": "attack2", "windup": 0.12, "active": 0.08, "recover": 0.22, "mult": 1.0, "step": 0.3, "knock": 2.5, "heavy": false},
	{"anim": "attack3", "windup": 0.22, "active": 0.10, "recover": 0.33, "mult": 1.8, "step": 0.4, "knock": 7.0, "heavy": true},
]
## Сколько секунд после удара следующее нажатие продолжает комбо.
const COMBO_WINDOW := 0.35
## Сколько миллисекунд помнится нажатие атаки, сделанное во время удара или рывка.
const QUEUE_MS := 450
## Урон без оружия.
const UNARMED_DAMAGE := 5.0
const HURT_STUN := 0.25
## Скиллы душ (COMBAT_SPEC, раздел 4).
const GHOST_STEP_LENGTH := 2.0
const ECHO_DELAY := 0.4
const ECHO_SHARE := 0.6
const MARK_RANGE := 6.0
const MARK_TIME := 5.0

var current_skin: int = 0
## Мастер-меню отладки: полёт сквозь стены (set_noclip).
var noclip: bool = false
var _step_time: float = 0.0
## Управление отключено (реплики, сценки): Рэй стоит, не бьёт и не применяет скиллы.
var input_locked: bool = false:
	set(value):
		if input_locked and not value:
			_unlock_frame = Engine.get_physics_frames()
		input_locked = value
## Такт физики, когда управление вернулось (конец реплики, снятие паузы): в следующем такте «только что
## нажатый» рывок — это та же клавиша, что закрыла окно (пробел — и ui_accept, и dash; B — ui_cancel и dash).
var _unlock_frame: int = -10
## Радиус для попаданий врагов (как у врагов).
var hit_radius: float = 0.35

@onready var sprite: DirectionalSprite = $Sprite3D

var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _facing: Vector3 = Vector3.BACK  # к камере

var _attack: int = -1  # индекс в COMBO, -1 — не бьёт
var _attack_time: float = 0.0
var _attack_dir: Vector3 = Vector3.BACK
var _attack_hit: bool = false
var _attack_mult: float = 1.0
var _queued: bool = false
var _queued_mouse: bool = false
var _queued_at: int = 0
var _combo_next: int = 0
var _combo_timer: float = 0.0

var _hurt_time: float = 0.0
var _invulnerable: float = 0.0
var _knock: Vector3 = Vector3.ZERO
var _ghost: bool = false
var _dead: bool = false
## Сколько ещё есть (еда, ItemData.use_time): Рэй идёт медленно и не бьёт; удар по нему или рывок — прерывают.
var _eat_left: float = 0.0
const EAT_SPEED := 0.4
## Состояния от ударов врагов (take_hit: slow, blind, stun — секунды): грязь квалда замедляет и слепит,
## удар голема по земле оглушает. Повторное попадание продлевает, а не усиливает.
var _slow_left: float = 0.0
var _blind_left: float = 0.0
var _blind_rect: ColorRect
const SLOW_FACTOR := 0.6
const BLIND_SHADER := """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.6, 1.0);
	float r = length(p);
	// Тёмная рамка с потёками грязи: обзор сужается к Рэю (он в центре кадра).
	float drip = 0.04 * sin(UV.x * 40.0) * step(0.5, 1.0 - UV.y);
	float a = smoothstep(0.42 - drip, 0.85, r) * strength;
	COLOR = vec4(0.16, 0.12, 0.07, a * 0.9);
}
"""


func _ready() -> void:
	add_to_group("player")
	collision_layer = CombatFX.LAYER_PLAYER
	collision_mask = CombatFX.LAYER_WORLD | CombatFX.LAYER_ENEMY
	CombatFX.setup_sprite(sprite)
	PlayerState.skill_used.connect(_on_skill_used)
	PlayerState.eating_started.connect(_on_eating_started)
	# Продолжение сохранённой игры: встаём туда, где сохранились.
	if SaveGame.pending_position != null:
		global_position = SaveGame.pending_position
		SaveGame.pending_position = null


func is_alive() -> bool:
	return not _dead


func is_attacking() -> bool:
	return _attack >= 0


func _physics_process(delta: float) -> void:
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	_tick_invulnerability(delta)
	if noclip:
		_noclip_move()
		return
	if _dead:
		velocity = Vector3(0, velocity.y, 0)
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return
	if _eat_left > 0.0:
		_eat_left -= delta
		if _eat_left <= 0.0:
			PlayerState.finish_eating()
	_tick_statuses(delta)

	# С геймпада длина вектора < 1 при неполном наклоне стика — тогда Рэй идёт медленнее.
	var input := Vector2.ZERO if input_locked else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(input.x, 0.0, input.y)
	var running := Input.is_action_pressed("run") and not input_locked
	# Запомненное нажатие атаки живёт недолго — иначе удар «вылетает» через секунду после рывка.
	if _queued and Time.get_ticks_msec() - _queued_at > QUEUE_MS:
		_queued = false

	# Рывок прерывает любой удар (но не оглушение от удара по Рэю).
	if not input_locked and Engine.get_physics_frames() - _unlock_frame > 1 and Input.is_action_just_pressed("dash") and _dash_cooldown_left == 0.0 and _hurt_time <= 0.0 \
			and PlayerState.spend_energy(dash_energy_cost):
		_start_dash(direction.normalized() if direction.length_squared() > 0.0 else _facing, dash_duration)

	var horizontal: Vector3
	if _hurt_time > 0.0:
		_hurt_time -= delta
		horizontal = _knock
	elif _dash_time_left > 0.0:
		_dash_time_left -= delta
		horizontal = _dash_direction * dash_speed
		if _dash_time_left <= 0.0 and _ghost:
			_end_ghost()
	elif _attack >= 0:
		horizontal = _update_attack(delta)
	else:
		if direction.length_squared() > 0.0:
			_facing = direction.normalized()
		_combo_timer = maxf(_combo_timer - delta, 0.0)
		if _combo_timer == 0.0:
			_combo_next = 0
		var target := direction * (run_speed if running else walk_speed)
		if _eat_left > 0.0:
			target = direction * walk_speed * EAT_SPEED
			_queued = false
		if _slow_left > 0.0:
			target *= SLOW_FACTOR
		horizontal = Vector3(velocity.x, 0.0, velocity.z).move_toward(target, acceleration * delta)
		if _queued:
			_queued = false
			_start_attack(_combo_next, _queued_mouse)
	_knock = _knock.move_toward(Vector3.ZERO, 20.0 * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()

	if _attack < 0:
		_update_animation(running)
	_footsteps(delta, running)


## Шаги: темп по скорости, звук — по поверхности под ногами (Audio.surface_at).
func _footsteps(delta: float, running: bool) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.5 or not is_on_floor() or _dash_time_left > 0.0:
		_step_time = 0.0
		return
	_step_time -= delta
	if _step_time <= 0.0:
		_step_time = 0.27 if running else 0.4
		Audio.play(Audio.surface_at(get_world_3d(), global_position), global_position, 0.12)


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		_unlock_frame = Engine.get_physics_frames()


func _unhandled_input(event: InputEvent) -> void:
	if _dead or input_locked:
		return
	# Касание экрана эмулирует ЛКМ — это не удар: у касания свои кнопки (TouchControls).
	if event.is_action_pressed("attack") and not (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION):
		# Нажатие во время удара запоминается и продолжает комбо, когда удар можно сменить.
		_queued = true
		_queued_mouse = event is InputEventMouseButton
		_queued_at = Time.get_ticks_msec()
	for i in 4:
		if event.is_action_pressed("skill_%d" % (i + 1)):
			PlayerState.use_skill(i)
		elif event.is_action_pressed("item_%d" % (i + 1)):
			PlayerState.use_item(i)


## Облик (мастер-меню отладки): 0 — Рэй, 1 — Вельмор, 2 — Лиара.
func set_skin(i: int) -> void:
	if i >= 0 and i < debug_skins.size():
		sprite.texture = debug_skins[i]
		current_skin = i


## Сквозь стены (мастер-меню отладки): без столкновений и гравитации, быстрее; вверх/вниз — Пробел/Ctrl.
func set_noclip(on: bool) -> void:
	noclip = on
	collision_layer = 0 if on else CombatFX.LAYER_PLAYER
	collision_mask = 0 if on else CombatFX.LAYER_WORLD | CombatFX.LAYER_ENEMY
	velocity = Vector3.ZERO


func _noclip_move() -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed := run_speed * (4.0 if Input.is_action_pressed("run") else 2.0)
	var up := float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_CTRL))
	velocity = Vector3(input.x, up, input.y) * speed
	if input.length_squared() > 0.0:
		_facing = Vector3(input.x, 0, input.y).normalized()
	move_and_slide()
	_update_animation(false)


func _update_animation(running: bool) -> void:
	sprite.face(_facing)
	var speed := Vector2(velocity.x, velocity.z).length()
	if _dash_time_left > 0.0:
		sprite.play("dash")
	elif speed < 0.3:
		sprite.play("idle")
		sprite.speed_scale = 1.0
	elif running:
		sprite.play("run")
		sprite.speed_scale = clampf(speed / run_speed, 0.5, 1.2)
	else:
		sprite.play("walk")
		# Темп шагов следует за скоростью — ноги не «скользят» при неполном наклоне стика.
		sprite.speed_scale = clampf(speed / walk_speed, 0.5, 1.2)


# --- Удары ---------------------------------------------------------------------

func _start_attack(index: int, from_mouse: bool, mult: float = 1.0) -> void:
	var dir := _mouse_direction() if from_mouse else _facing
	# Доводка: если в широком секторе впереди есть цель — бьём точно в неё.
	var targets := CombatFX.targets_in_arc(global_position, dir, aim_assist_range, 70.0)
	if not targets.is_empty():
		var to: Vector3 = targets[0].global_position - global_position
		to.y = 0
		if to.length_squared() > 0.01:
			dir = to.normalized()
	_attack = index
	_attack_time = 0.0
	_attack_dir = dir
	_attack_hit = false
	_attack_mult = mult
	_queued = false
	_facing = dir
	sprite.face(dir)
	sprite.show_frame(COMBO[index]["anim"], 0)


## Ведёт текущий удар; возвращает скорость (шаг вперёд в активной фазе).
func _update_attack(delta: float) -> Vector3:
	var a: Dictionary = COMBO[_attack]
	_attack_time += delta
	var windup: float = a["windup"]
	var active_end: float = windup + a["active"]
	var total: float = active_end + a["recover"]
	var t := _attack_time
	var frame := 0 if t < windup else (1 if t < active_end else (2 if t < active_end + a["recover"] * 0.5 else 3))
	sprite.show_frame(a["anim"], frame)
	if not _attack_hit and t >= windup:
		_attack_hit = true
		Audio.play("swing", global_position)
		_strike(global_position, _attack_dir, a["mult"] * _attack_mult, a["knock"], a["heavy"])
		if a["heavy"]:
			CombatFX.shake(0.35)
			# Меч бьёт в землю — фонтанчик пыли и каменной крошки.
			CombatFX.burst(global_position + _attack_dir * 0.9 + Vector3(0, 0.05, 0), Color(0.72, 0.68, 0.6), Vector3.ZERO, 14, 3.0, 9.0, 0.08, 0.45)
	# Следующий удар комбо можно начать со второй половины восстановления.
	var last := _attack == COMBO.size() - 1
	if _queued and not last and t >= active_end + a["recover"] * 0.5:
		_start_attack(_attack + 1, _queued_mouse)
		return Vector3.ZERO
	if t >= total:
		_combo_next = 0 if last else _attack + 1
		_combo_timer = COMBO_WINDOW
		_attack = -1
		return Vector3.ZERO
	if t >= windup and t < active_end:
		return _attack_dir * (a["step"] / a["active"])
	return Vector3.ZERO


## Удар по сектору перед origin. Возвращает, по скольким целям попали.
func _strike(origin: Vector3, dir: Vector3, mult: float, knockback: float, heavy: bool) -> int:
	var base := maxf(PlayerState.damage_bonus, UNARMED_DAMAGE)
	var hits := 0
	for target in CombatFX.targets_in_arc(origin, dir, attack_reach, attack_half_angle):
		if target.take_hit({"damage": base * mult, "dir": dir, "knockback": knockback, "heavy": heavy}) > 0.0:
			hits += 1
	# Ложные стены и прочее, что ломается мечом (без доводки — тайник нужно найти самому).
	for target in CombatFX.targets_in_arc(origin, dir, attack_reach, attack_half_angle, "breakable"):
		if target.take_hit({"damage": base * mult, "dir": dir}) > 0.0:
			hits += 1
	if hits > 0:
		CombatFX.hit_stop(0.09 if heavy else 0.05)
	return hits


## Направление к точке на земле под курсором (атака мышью).
func _mouse_direction() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return _facing
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var n := cam.project_ray_normal(mp)
	if absf(n.y) < 0.001:
		return _facing
	var point := from + n * ((global_position.y - from.y) / n.y)
	var dir := point - global_position
	dir.y = 0
	return dir.normalized() if dir.length_squared() > 0.01 else _facing


func _cancel_attack() -> void:
	_attack = -1
	_queued = false


func _start_dash(dir: Vector3, duration: float) -> void:
	_stop_eating()
	_cancel_attack()
	_dash_time_left = duration
	_dash_cooldown_left = dash_cooldown
	_dash_direction = dir
	_facing = dir
	Audio.play("dash", global_position)
	# Пыль из-под лап — назад от рывка.
	CombatFX.burst(global_position + Vector3(0, 0.1, 0), Color(0.75, 0.7, 0.62, 0.8), -dir, 8, 2.0, 1.5, 0.08, 0.4)


# --- Получение урона, смерть --------------------------------------------------------

## Удар по Рэю. info: damage, dir, knockback. Возвращает нанесённый урон.
func take_hit(info: Dictionary) -> float:
	if _dead or _invulnerable > 0.0 or _ghost:
		return 0.0
	var amount: float = info.get("damage", 0.0)
	CombatFX.damage_number(global_position + Vector3(0, 1.5, 0), amount * 100.0 / (100.0 + PlayerState.defense), CombatFX.COLOR_PLAYER)
	CombatFX.shake(0.5)
	Audio.play("hurt", global_position)
	# Урон может убить — тогда DeathCycle уже перевёл Рэя в «мёртв».
	PlayerState.damage(amount, global_position)
	if _dead:
		return amount
	CombatFX.flash(sprite, Color("e04a3a"), 0.15)
	CombatFX.burst(global_position + Vector3(0, 0.8, 0), Color("e86a5a"), info.get("dir", Vector3.ZERO), 10, 3.5, 9.0, 0.07, 0.4)
	if _eat_left > 0.0:
		_stop_eating()
		CombatFX.float_text(global_position + Vector3(0, 2.2, 0), "Прервано", Color("e6d6b0"))
	_cancel_attack()
	_dash_time_left = 0.0
	var dir: Vector3 = info.get("dir", Vector3.ZERO)
	_knock = Vector3(dir.x, 0, dir.z).normalized() * float(info.get("knockback", 4.0))
	_hurt_time = HURT_STUN
	_invulnerable = hurt_invulnerability
	_apply_statuses(info)
	return amount


func _apply_statuses(info: Dictionary) -> void:
	if info.has("slow"):
		_slow_left = maxf(_slow_left, info["slow"])
	if info.has("blind"):
		_blind_left = maxf(_blind_left, info["blind"])
		if _blind_rect == null:
			var layer := CanvasLayer.new()
			layer.layer = 5
			add_child(layer)
			_blind_rect = ColorRect.new()
			_blind_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			_blind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var mat := ShaderMaterial.new()
			mat.shader = Shader.new()
			mat.shader.code = BLIND_SHADER
			_blind_rect.material = mat
			layer.add_child(_blind_rect)
	if info.has("stun"):
		# Оглушение — то же «оглушение от удара», только дольше и без отброса: ни шага, ни удара, ни рывка.
		_hurt_time = maxf(_hurt_time, info["stun"])
		_knock = Vector3.ZERO
		CombatFX.float_text(global_position + Vector3(0, 2.2, 0), "Оглушён", Color("e6d6b0"))


func _tick_statuses(delta: float) -> void:
	_slow_left = maxf(_slow_left - delta, 0.0)
	_blind_left = maxf(_blind_left - delta, 0.0)
	if _blind_rect:
		# Наплывает быстро, сходит за последние полсекунды.
		var want := clampf(_blind_left / 0.5, 0.0, 1.0)
		var mat := _blind_rect.material as ShaderMaterial
		var now := float(mat.get_shader_parameter("strength") if mat.get_shader_parameter("strength") != null else 0.0)
		mat.set_shader_parameter("strength", move_toward(now, want, delta * 4.0))


## Замедлен ли Рэй (для тестов и подсказок интерфейса).
func is_slowed() -> bool:
	return _slow_left > 0.0


func is_blinded() -> bool:
	return _blind_left > 0.0


## Неуязвимость после удара — Рэй мигает.
func _tick_invulnerability(delta: float) -> void:
	if _invulnerable <= 0.0:
		return
	_invulnerable -= delta
	sprite.visible = _invulnerable <= 0.0 or fmod(_invulnerable, 0.12) > 0.05


## Еда (PlayerState.start_use): Рэй ест use_time секунд, потом PlayerState.finish_eating лечит.
func _on_eating_started(item: ItemData) -> void:
	_eat_left = item.use_time
	_cancel_attack()
	CombatFX.float_text(global_position + Vector3(0, 2.2, 0), item.name, Color("e6d6b0"))


## Прервать еду — предмет не тратится.
func _stop_eating() -> void:
	_eat_left = 0.0
	PlayerState.cancel_eating()


## Сцена сменилась посреди еды — иначе PlayerState считал бы, что Рэй всё ещё ест, и не давал есть снова.
func _exit_tree() -> void:
	if _eat_left > 0.0:
		_stop_eating()


## Смерть и возрождение ведёт DeathCycle.
func set_dead(value: bool) -> void:
	_dead = value
	_stop_eating()
	_slow_left = 0.0
	_blind_left = 0.0
	_cancel_attack()
	_end_ghost()
	_dash_time_left = 0.0
	_hurt_time = 0.0
	_knock = Vector3.ZERO
	velocity = Vector3.ZERO
	sprite.visible = true
	sprite.modulate = Color(0.5, 0.4, 0.6) if value else Color.WHITE
	if not value:
		_invulnerable = 1.0  # пара секунд передышки после возрождения
		sprite.play("idle", true)


# --- Скиллы душ ------------------------------------------------------------------------

func _on_skill_used(index: int) -> void:
	var skill: SkillData = PlayerState.hotbar_skills[index]
	if skill == null or _dead or input_locked:
		return
	match String(skill.id):
		"ghost_step":
			# Длинный рывок сквозь врагов, неуязвимость, Рэй полупрозрачен.
			var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			var dir := Vector3(input.x, 0, input.y)
			_start_dash(dir.normalized() if dir.length_squared() > 0.0 else _facing, dash_duration * GHOST_STEP_LENGTH)
			_hurt_time = 0.0
			_ghost = true
			collision_mask = CombatFX.LAYER_WORLD
			CombatFX.set_ghost(sprite, 1.0)
		"echo_strike":
			# Удар, который через 0,4 с повторяет призрачное эхо на том же месте.
			_dash_time_left = 0.0
			if _ghost:
				_end_ghost()   # иначе после «Призрачного шага» Рэй оставался неуязвимым навсегда
			_start_attack(1, false)
			var origin := global_position + _attack_dir * 0.2
			var dir := _attack_dir
			var flip := sprite.flip_h
			var frame := sprite.frame_of("attack2", 1)
			get_tree().create_timer(ECHO_DELAY, false).timeout.connect(func():   # на паузе эхо ждёт
				if not is_inside_tree() or _dead:
					return
				_spawn_echo_ghost(origin, flip, frame)
				_strike(origin, dir, ECHO_SHARE, 2.0, false))
		"watch_mark":
			var target := CombatFX.nearest(global_position, MARK_RANGE, "enemies")
			if target == null:
				target = CombatFX.nearest(global_position, MARK_RANGE)
			if target and target.has_method("mark"):
				target.mark(MARK_TIME)


func _end_ghost() -> void:
	if not _ghost:
		return
	_ghost = false
	collision_mask = CombatFX.LAYER_WORLD | CombatFX.LAYER_ENEMY
	CombatFX.set_ghost(sprite, 0.0)


## Призрачный силуэт удара на месте «Эха удара».
func _spawn_echo_ghost(origin: Vector3, flip: bool, frame: int) -> void:
	var ghost := Sprite3D.new()
	ghost.texture = sprite.texture
	ghost.hframes = sprite.hframes
	ghost.vframes = sprite.vframes
	ghost.frame = frame
	ghost.pixel_size = sprite.pixel_size
	ghost.billboard = sprite.billboard
	ghost.texture_filter = sprite.texture_filter
	ghost.flip_h = flip
	ghost.shaded = false
	ghost.modulate = Color(0.6, 1.4, 1.6, 0.6)
	get_parent().add_child(ghost)
	ghost.global_position = origin + Vector3(0, sprite.position.y, 0)
	var t := ghost.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, 0.35)
	t.tween_callback(ghost.queue_free)
