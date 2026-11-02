extends Node
## Автозагрузка Cheats — «Мастер чит-дебаг меню» (решение автора): O на клавиатуре, R3 на геймпаде.
## Компактная панель поверх игры (игра на паузе, пока панель открыта). Блоки:
## 1) читы: бессмертие, сквозь стены, скорость игры ×1/×2/×5;
## 2) телепорт: главное меню, Ивовый Брод, Рубеж, тестовая карта, Перепутье;
## 3) задания (QuestState) и метки-заглушки жителей;
## 4) отладка вместо прежних клавиш F1–F10: облик, урон, смерть, гелиосы, новый спуск,
##    флажки «Хитбоксы», «FPS», «Лог ошибок», «Подсказка».

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const PLACES := [
	["Главное меню", MAIN_MENU], ["Таверна", "res://scenes/levels/tavern.tscn"],
	["Ивовый Брод", "res://scenes/levels/world.tscn"],
	["Рубеж, этаж 1", "res://scenes/levels/rubezh_f1.tscn"],
	["Перепутье", "res://scenes/levels/crossroads.tscn"],
]
const SKINS := ["Рэй", "Вельмор", "Лиара"]
const SPEEDS := [1.0, 2.0, 5.0]
const COL_TITLE := Color("e8c870")
const COL_TEXT := Color("e6d6b0")
const COL_DIM := Color("9a8a70")

## Метки-заглушки жителей/сундуков: в сборке для игроков скрыты, в редакторе видны.
var show_markers: bool = OS.has_feature("editor")
var god_mode: bool = false
var noclip: bool = false
var speed: float = 1.0
var show_fps: bool = false
var show_log: bool = false
var show_hint: bool = OS.has_feature("editor")

var errors: ErrorLog
var _layer: CanvasLayer
var _panel: PanelContainer
var _quest_box: VBoxContainer
var _speed_buttons: Array[Button] = []
var _clock_label: Label
var _music_label: Label
var _time_speed_buttons: Array[Button] = []
var _fps_label: Label
var _log_panel: PanelContainer
var _log_label: Label
var _was_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	errors = ErrorLog.new()
	OS.add_logger(errors)
	_build()
	QuestState.changed.connect(_refresh_quests)
	get_tree().node_added.connect(_on_node_added)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_menu"):
		toggle()
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	var open := not _panel.visible
	_panel.visible = open
	if open:
		_was_paused = get_tree().paused
		get_tree().paused = true
		_refresh_quests()
		_refresh_speed()
	else:
		get_tree().paused = _was_paused


func _process(_delta: float) -> void:
	if _clock_label and _panel.visible:
		_clock_label.text = "Сейчас %s (%s)   сутки — %d мин" % [TimeOfDay.clock(),
			"ночь" if TimeOfDay.is_night() else "день", int(TimeOfDay.DAY_MINUTES)]
	if _music_label and _panel.visible:
		var id: String = Audio.current_track()
		_music_label.text = "%s%s
%s" % ["(поверх) " if Audio.override != "" else "", id if id != "" else "—",
			Audio.track_title(id)]
	if _fps_label.visible:
		var scene := get_tree().current_scene
		_fps_label.text = "FPS %d   кадр %.1f мс   вызовов %d   %s" % [Engine.get_frames_per_second(),
			1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			scene.scene_file_path.get_file() if scene else ""]
	if _log_panel.visible:
		var lines := errors.snapshot()
		_log_label.text = "Ошибок и предупреждений: %d\n" % errors.count + "\n".join(lines.slice(maxi(0, lines.size() - 14)))


# --- Действия ------------------------------------------------------------------------

func player() -> Node3D:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Player") as Node3D if scene else null


func set_god(on: bool) -> void:
	god_mode = on
	PlayerState.god_mode = on


func set_noclip(on: bool) -> void:
	noclip = on
	var p := player()
	if p and p.has_method("set_noclip"):
		p.set_noclip(on)


func set_speed(value: float) -> void:
	speed = value
	CombatFX.base_time_scale = value
	_refresh_speed()


func set_markers(on: bool) -> void:
	show_markers = on
	for m in get_tree().get_nodes_in_group("level_markers"):
		m.visible = on


func teleport(path: String) -> void:
	_panel.visible = false
	get_tree().paused = false
	SaveGame.pending_position = null
	if path == MAIN_MENU:
		set_speed(1.0)
	get_tree().change_scene_to_file(path)


## Перезагрузить текущую сцену, сохранив место Рэя (нужно, чтобы хитбоксы появились/исчезли).
func reload_here() -> void:
	var p := player()
	var scene := get_tree().current_scene
	if scene == null:
		return
	SaveGame.pending_position = p.global_position if p else null
	_panel.visible = false
	get_tree().paused = false
	get_tree().change_scene_to_file(scene.scene_file_path)


## Новые узлы сцены получают текущие настройки читов (Рэй после перехода, метки).
func _on_node_added(node: Node) -> void:
	if node.name == "Player" and node.has_method("set_noclip") and noclip:
		node.set_noclip.call_deferred(true)


# --- Интерфейс ---------------------------------------------------------------------

## Простой тёмный фон для отладочных панелей (не зависит от рамок игрового интерфейса).
func _debug_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.05, 0.92)
	sb.border_color = Color("5c3a2a")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(5)
	return sb


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	var scaler := UIScaler.new()
	scaler.min_canvas = Vector2(400, 300)
	_layer.add_child(scaler)

	_fps_label = _label("", 8, COL_TEXT)
	_fps_label.position = Vector2(6, 30)
	_fps_label.visible = show_fps
	scaler.add_child(_fps_label)

	_log_panel = PanelContainer.new()
	_log_panel.position = Vector2(6, 42)
	_log_panel.custom_minimum_size = Vector2(300, 0)
	_log_panel.visible = show_log
	_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_panel.add_theme_stylebox_override("panel", _debug_style())
	_log_label = _label("", 8, Color("f0b0a0"))
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.custom_minimum_size = Vector2(290, 0)
	_log_panel.add_child(_log_label)
	scaler.add_child(_log_panel)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", _debug_style())
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -214
	_panel.offset_right = -4
	# Если содержимое шире — панель растёт влево, а не уходит за край экрана.
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_top = 4
	_panel.offset_bottom = -4
	scaler.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	scroll.add_child(v)

	var head := HBoxContainer.new()
	var title := _label("Мастер-меню отладки", 8, COL_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := CloseButton.new()
	close.pressed.connect(toggle)
	head.add_child(close)
	v.add_child(head)
	v.add_child(_label("O / R3 — закрыть", 8, COL_DIM))

	_section(v, "Читы")
	v.add_child(_check("Бессмертие", god_mode, set_god))
	v.add_child(_check("Сквозь стены", noclip, set_noclip))
	v.add_child(_label("  Пробел/Ctrl — вверх/вниз", 8, COL_DIM))
	var speeds := HBoxContainer.new()
	speeds.add_child(_label("Скорость игры", 8, COL_TEXT))
	for s in SPEEDS:
		var b := _button("×%d" % int(s), func(): set_speed(s))
		b.toggle_mode = true
		_speed_buttons.append(b)
		speeds.add_child(b)
	v.add_child(speeds)

	_section(v, "Время суток")
	_clock_label = _label("", 8, COL_TEXT)
	v.add_child(_clock_label)
	var hours := HBoxContainer.new()
	for h in [0, 6, 12, 18]:
		hours.add_child(_button("%02d:00" % h, func(): TimeOfDay.set_hour(h)))
	hours.add_child(_button("−1 ч", func(): TimeOfDay.set_hour(TimeOfDay.hour - 1.0)))
	hours.add_child(_button("+1 ч", func(): TimeOfDay.set_hour(TimeOfDay.hour + 1.0)))
	v.add_child(hours)
	var tspeed := HBoxContainer.new()
	tspeed.add_child(_label("Ход времени", 8, COL_TEXT))
	for s in [1.0, 10.0, 60.0]:
		var b := _button("×%d" % int(s), func():
			TimeOfDay.speed = s
			_refresh_time())
		b.toggle_mode = true
		_time_speed_buttons.append(b)
		tspeed.add_child(b)
	v.add_child(tspeed)
	v.add_child(_check("Время стоит", TimeOfDay.paused, func(on): TimeOfDay.paused = on))
	_refresh_time()

	# Прослушать кандидатов: ◀ ▶ — все дорожки по кругу поверх музыки сцены; «По сцене» — вернуть день/ночь/бой.
	_section(v, "Музыка")
	_music_label = _label("", 8, COL_TEXT)
	v.add_child(_music_label)
	var music := HBoxContainer.new()
	music.add_child(_button("◀", func(): _cycle_music(-1)))
	music.add_child(_button("▶", func(): _cycle_music(1)))
	music.add_child(_button("По сцене", func(): Audio.override = ""))
	music.add_child(_button("Тишина", func(): Audio.override = "-"))
	v.add_child(music)

	_section(v, "Телепорт")
	var grid := GridContainer.new()
	grid.columns = 2
	for place in PLACES:
		grid.add_child(_button(place[0], func(): teleport(place[1])))
	v.add_child(grid)

	_section(v, "Задания и жители")
	_quest_box = VBoxContainer.new()
	v.add_child(_quest_box)
	v.add_child(_check("Метки-заглушки жителей", show_markers, set_markers))

	_section(v, "Отладка")
	var skins := HBoxContainer.new()
	skins.add_child(_label("Облик", 8, COL_TEXT))
	for i in SKINS.size():
		skins.add_child(_button(SKINS[i], func():
			var p := player()
			if p and p.has_method("set_skin"):
				p.set_skin(i)))
	v.add_child(skins)
	var acts := GridContainer.new()
	acts.columns = 2
	acts.add_child(_button("Урон 15", func():
		var p := player()
		var was := PlayerState.god_mode
		PlayerState.god_mode = false
		PlayerState.damage(15.0, p.global_position if p else Vector3.INF)
		PlayerState.god_mode = was))
	acts.add_child(_button("Смерть", func():
		var p := player()
		PlayerState.die(p.global_position if p else Vector3.INF)))
	acts.add_child(_button("+25 гелиосов", func(): PlayerState.add_helios(25)))
	acts.add_child(_button("Новый спуск", func(): PlayerState.start_descent()))
	acts.add_child(_button("Полное здоровье", func(): PlayerState.heal(PlayerState.max_hp)))
	acts.add_child(_button("Очистить лог", func(): errors.clear()))
	v.add_child(acts)
	v.add_child(_check("Хитбоксы (перезагрузка)", get_tree().debug_collisions_hint, func(on):
		get_tree().debug_collisions_hint = on
		reload_here()))
	v.add_child(_check("FPS", show_fps, func(on):
		show_fps = on
		_fps_label.visible = on))
	v.add_child(_check("Лог ошибок", show_log, func(on):
		show_log = on
		_log_panel.visible = on))
	v.add_child(_check("Подсказка управления", show_hint, func(on):
		show_hint = on))


func _refresh_quests() -> void:
	for c in _quest_box.get_children():
		c.queue_free()
	if QuestState.active.is_empty():
		_quest_box.add_child(_label("Активных заданий нет", 8, COL_DIM))
	for id in QuestState.active:
		var name_l := _label(QuestState.title(id), 8, COL_TEXT)
		_quest_box.add_child(name_l)
		var steps: Array = QuestState.steps(id)
		var step_l := _label("Шаг %d/%d: %s" % [mini(QuestState.active[id] + 1, steps.size()), steps.size(),
			QuestState.current_step_text(id)], 8, COL_DIM)
		step_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		step_l.custom_minimum_size = Vector2(196, 0)
		_quest_box.add_child(step_l)
		var row := HBoxContainer.new()
		row.add_child(_button("Завершить шаг", func(): QuestState.complete_step(id)))
		row.add_child(_button("Сбросить", func(): QuestState.reset_quest(id)))
		_quest_box.add_child(row)
	if not QuestState.active.has("chapter1"):
		_quest_box.add_child(_button("Начать «Главу 1»", func(): QuestState.start("chapter1")))


func _cycle_music(step: int) -> void:
	# Отсчёт — от выбранной поверх дорожки (current_track обновляется раз в 0,5 с: быстрые щелчки терялись);
	# из тишины ▶ — первая дорожка, ◀ — последняя.
	var ids: Array = Audio.TRACKS.keys()
	var from: String = Audio.override if Audio.override != "" else Audio.current_track()
	var i := ids.find(from)
	if i < 0:
		i = -1 if step > 0 else ids.size()
	Audio.override = ids[posmod(i + step, ids.size())]


func _refresh_time() -> void:
	var speeds := [1.0, 10.0, 60.0]
	for i in _time_speed_buttons.size():
		_time_speed_buttons[i].button_pressed = is_equal_approx(speeds[i], TimeOfDay.speed)


func _refresh_speed() -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(is_equal_approx(SPEEDS[i], speed))


func _section(parent: Control, text: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	parent.add_child(_label(text, 8, COL_TITLE))


func _check(text: String, value: bool, callback: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 8)
	c.toggled.connect(callback)
	c.focus_mode = Control.FOCUS_ALL
	return c


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 8)
	b.pressed.connect(callback)
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("1e1614"))
	l.add_theme_constant_override("outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
