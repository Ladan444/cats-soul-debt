extends PanelContainer
## Пульт арены баланса M01 («гимн боя»): живая настройка цифр и замер.
## Слева от пульта — Рэй, манекен и руна-источник ударов. Здесь только интерфейс:
## ползунки пишут в PlayerState/манекен/руну, а DPS и время добивания считаются по попаданиям.

const DPS_WINDOW := 5.0
const BURST_WINDOW := 1.5

var _player: Node3D
var _dummy
var _striker

var _hp_label: Label
var _dummy_label: Label
var _hits_label: Label
var _survive_label: Label
var _dps_label: Label
var _burst_label: Label
var _ttk_label: Label

var _hit_times: Array[float] = []
var _hit_amounts: Array[float] = []
var _first_hit_at: float = -1.0
var _lethal_shown: bool = false
var _dps_value: float = 0.0
var _burst_value: float = 0.0


func _ready() -> void:
	theme = load("res://assets/ui/theme.tres")
	custom_minimum_size = Vector2(232, 352)
	# Правый верхний угол: пульт остаётся на экране при любом соотношении сторон.
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -236
	offset_top = 4
	offset_right = -4
	offset_bottom = 356
	_player = get_tree().get_first_node_in_group("player")
	_dummy = get_tree().get_first_node_in_group("gym_dummy")
	_striker = get_tree().get_first_node_in_group("gym_striker")
	_build_ui()
	_connect_nodes()
	_refresh_all()


func _build_ui() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)

	var title := _label("M01 · Бой", 16)
	v.add_child(title)

	_add_slider(v, "PlayerHPSlider", "HP Рэя", 40.0, 300.0, 5.0, PlayerState.max_hp, "%d", _on_player_hp)
	_add_slider(v, "PlayerDamageSlider", "Урон Рэя", 5.0, 40.0, 1.0, PlayerState.damage_bonus, "%d", _on_player_damage)
	_add_slider(v, "InvulnSlider", "Неуязвимость", 0.0, 2.0, 0.05, _player.get("hurt_invulnerability") if _player else 0.7, "%.2f", _on_invuln)
	_add_slider(v, "EnemyDamageSlider", "Урон врага", 5.0, 60.0, 1.0, _striker.damage if _striker else 20.0, "%d", _on_enemy_damage)
	_add_slider(v, "IntervalSlider", "Интервал удара", 0.4, 3.0, 0.1, _striker.interval if _striker else 1.2, "%.1f", _on_interval)
	_add_slider(v, "DummyHPSlider", "HP манекена", 20.0, 400.0, 10.0, _dummy.max_hp if _dummy else 50.0, "%d", _on_dummy_hp)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 1)
	v.add_child(grid)
	_hp_label = _label("", 8)
	_dummy_label = _label("", 8)
	_hits_label = _label("", 8)
	_survive_label = _label("", 8)
	_dps_label = _label("", 8)
	_burst_label = _label("", 8)
	for l in [_hp_label, _dummy_label, _hits_label, _survive_label, _dps_label, _burst_label]:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		grid.add_child(l)

	_ttk_label = _label("", 8)
	_ttk_label.clip_text = true
	v.add_child(_ttk_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	var reset := Button.new()
	reset.text = "Сброс"
	reset.add_theme_font_size_override("font_size", 8)
	reset.pressed.connect(_reset_all)
	row.add_child(reset)
	var hit := Button.new()
	hit.text = "Бить"
	hit.add_theme_font_size_override("font_size", 8)
	hit.pressed.connect(_manual_strike)
	row.add_child(hit)
	var auto := CheckBox.new()
	auto.text = "Авто"
	auto.add_theme_font_size_override("font_size", 8)
	auto.button_pressed = _striker.auto if _striker else true
	auto.toggled.connect(_on_auto)
	row.add_child(auto)

	var hint := _label("WASD · ЛКМ · Пробел", 8)
	hint.add_theme_color_override("font_color", Color("9a8a70"))
	v.add_child(hint)
	var hint2 := _label("Shift — бег", 8)
	hint2.add_theme_color_override("font_color", Color("9a8a70"))
	v.add_child(hint2)
	var hint3 := _label("Esc — выход", 8)
	hint3.add_theme_color_override("font_color", Color("9a8a70"))
	v.add_child(hint3)


func _add_slider(parent: VBoxContainer, id: String, caption: String, min_v: float, max_v: float, step: float, value: float, fmt: String, callback: Callable) -> void:
	var label := _label("%s: %s" % [caption, fmt % value], 8)
	label.clip_text = true
	parent.add_child(label)
	var slider := HSlider.new()
	slider.name = id
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 12)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slider)
	slider.value_changed.connect(func(v: float): label.text = "%s: %s" % [caption, fmt % v])
	slider.value_changed.connect(callback)


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _connect_nodes() -> void:
	PlayerState.hp_changed.connect(_on_hp_changed)
	if _dummy:
		_dummy.damaged.connect(_on_dummy_damaged)
		_dummy.defeated.connect(_on_dummy_defeated)
	if _striker:
		_striker.struck.connect(_on_struck)
		_striker.lethal.connect(_on_lethal)
		_striker.run_reset.connect(_on_run_reset)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _process(_delta: float) -> void:
	if _dummy == null or not is_instance_valid(_dummy):
		return
	var now := _now()
	_trim(now)
	_dps_value = _window_rate(DPS_WINDOW, now)
	_burst_value = _window_rate(BURST_WINDOW, now)
	_dps_label.text = "DPS: %.1f" % _dps_value
	_burst_label.text = "Пик: %.1f" % _burst_value
	_dummy_label.text = "Манекен: %d" % int(ceil(maxf(_dummy.hp, 0.0)))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _trim(now: float) -> void:
	while not _hit_times.is_empty() and now - _hit_times[0] > DPS_WINDOW:
		_hit_times.pop_front()
		_hit_amounts.pop_front()
	if _hit_times.is_empty():
		_first_hit_at = -1.0


## Скорость урона в окне: сумма попаданий / реально прошедшее время (не больше окна).
func _window_rate(window: float, now: float) -> float:
	if _hit_times.is_empty():
		return 0.0
	var sum := 0.0
	for i in _hit_times.size():
		if now - _hit_times[i] <= window:
			sum += _hit_amounts[i]
	var span := minf(window, maxf(0.25, now - _first_hit_at))
	return sum / span


func _refresh_all() -> void:
	_on_hp_changed(PlayerState.hp, PlayerState.max_hp)
	_update_survive_estimate()
	_dps_label.text = "DPS: 0.0"
	_burst_label.text = "Пик: 0.0"
	_ttk_label.text = "Убит: —"
	if _dummy:
		_dummy_label.text = "Манекен: %d" % int(ceil(maxf(_dummy.hp, 0.0)))
	else:
		_dummy_label.text = "Манекен: —"


func _manual_strike() -> void:
	if _striker:
		_striker.strike()


func _on_hp_changed(hp: float, max_hp: float) -> void:
	_hp_label.text = "HP: %d/%d" % [int(ceil(maxf(hp, 0.0))), int(max_hp)]
	if not _lethal_shown:
		_update_survive_estimate()


func _on_player_hp(value: float) -> void:
	PlayerState.max_hp = value
	PlayerState.hp = value
	PlayerState.hp_changed.emit(PlayerState.hp, PlayerState.max_hp)
	if _striker:
		_striker.reset_run()
	_lethal_shown = false
	_update_survive_estimate()


func _on_player_damage(value: float) -> void:
	PlayerState.damage_bonus = value


func _on_invuln(value: float) -> void:
	if _player:
		_player.set("hurt_invulnerability", value)


func _on_enemy_damage(value: float) -> void:
	if _striker == null:
		return
	_striker.damage = value
	_striker.reset_run()
	_lethal_shown = false
	_update_survive_estimate()


func _on_interval(value: float) -> void:
	if _striker:
		_striker.interval = value


func _on_dummy_hp(value: float) -> void:
	if _dummy:
		_dummy.configure(value)
	_clear_damage()
	_ttk_label.text = "Убит: —"


func _on_auto(on: bool) -> void:
	if _striker:
		_striker.auto = on


func _on_dummy_damaged(amount: float) -> void:
	var now := _now()
	if _first_hit_at < 0.0:
		_first_hit_at = now
	_hit_times.append(now)
	_hit_amounts.append(amount)


func _on_dummy_defeated(hits: int, seconds: float) -> void:
	_ttk_label.text = "Убит: %d уд. / %.1f с" % [hits, seconds]


func _on_struck(hit_number: int, _amount: float) -> void:
	_hits_label.text = "Удары: %d" % hit_number
	_survive_label.text = "Жив: %d" % int(ceil(maxf(PlayerState.hp, 0.0)))
	_lethal_shown = false


func _on_lethal(hit_number: int) -> void:
	_hits_label.text = "Удары: %d" % hit_number
	_survive_label.text = "Смерть: %d-й" % hit_number
	_lethal_shown = true


func _on_run_reset() -> void:
	_hits_label.text = "Удары: 0"
	_lethal_shown = false
	_update_survive_estimate()


func _update_survive_estimate() -> void:
	if _striker == null:
		_survive_label.text = "Выдержит: —"
		return
	_survive_label.text = "Выдержит: %d" % _striker.hits_to_die()


func _reset_all() -> void:
	if _striker:
		_striker.reset_run()
	if _dummy:
		_dummy.reset_dummy()
	_clear_damage()
	_lethal_shown = false
	_ttk_label.text = "Убит: —"
	_update_survive_estimate()


func _clear_damage() -> void:
	_hit_times.clear()
	_hit_amounts.clear()
	_first_hit_at = -1.0
	_dps_value = 0.0
	_burst_value = 0.0


## Для автотеста: текущие показания пульта.
func dps_value() -> float:
	return _dps_value


func burst_value() -> float:
	return _burst_value
