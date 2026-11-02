class_name Book
extends CanvasLayer
## Книга Рэя (UI_SPEC, разделы 3–4): одна книга вместо меню персонажа и журнала.
## Слева закладки Рэя (Снаряжение, Предметы, Души, Ключевое), справа — журнала
## (Записи, Люди, Улики, Бестиарий). Игра на паузе, пока книга открыта.
## Tab / I / View — разделы Рэя (повторное нажатие закрывает книгу); M — карта во весь экран (решение автора
## 2026-10-22): в мире — карта мира с перемещениями (WorldMap), в остальных местах — карта места (LocationMap);
## Q/E или LB/RB — листать все закладки по кругу; Esc / B, крестик или касание мимо книги — закрыть.

## Книга нарисована автором целиком (book_frame.png) — страницы пустые, закладки отдельными язычками.
const FRAME := preload("res://assets/ui/book_frame.png")
const SECTIONS := [
	["Снаряжение", "sword"], ["Предметы", "flask"], ["Души", "soul"], ["Ключевое", "key"],
	["Записи", "quill"], ["Люди", "people"], ["Улики", "clue"], ["Бестиарий", "skull"],
]
## Первые RAY_SECTIONS закладок — Рэя (левый край), остальные — журнала (правый край).
const RAY_SECTIONS := 4
const SIZE := Vector2(512, 340)
const PAGE_L := Rect2(36, 22, 216, 271)
const PAGE_R := Rect2(263, 22, 224, 271)
## Где торчат язычки (верхний край, UI-пиксели от книги) — по рисунку автора.
const TABS_LEFT_Y := [37, 98, 161, 223]
const TABS_RIGHT_Y := [43, 107, 170, 233]
const TAB_LEFT_X := -46
const TAB_RIGHT_X := 491
const LIGHT := Color("e6d6b0")

## Карта текущей локации (карта места на M) и игрок — задаются сценой.
@export var map: JournalMap
@export var player_path: NodePath

## Открытый раздел (индекс в SECTIONS).
var section: int = 0
var _last_ray: int = 0
var _last_journal: int = RAY_SECTIONS
var _left: Control
var _right: Control
var _marks: Array[_Bookmark] = []
var _character: Node
var _journal: Node
var _location_map: CanvasLayer


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Фон — размытый и затемнённый кадр игры (как в паузе); весь игровой интерфейс на это время прячется.
	var dim := ColorRect.new()
	dim.color = Color.WHITE
	var blur := ShaderMaterial.new()
	blur.shader = preload("res://assets/ui/pause_blur.gdshader")
	dim.material = blur
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	var scaler := UIScaler.new()
	scaler.min_canvas = Vector2(SIZE.x + 40, 360)
	add_child(scaler)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scaler.add_child(root)

	_character = load("res://scripts/ui/book/character_pages.gd").new()
	_character.book = self
	add_child(_character)
	_journal = load("res://scripts/ui/book/journal_pages.gd").new()
	add_child(_journal)

	_build(root)
	_location_map = load("res://scripts/ui/location_map.gd").new()
	_location_map.name = "LocationMap"
	add_child(_location_map)
	visible = false


## _input, а не _unhandled_input: иначе Tab съедает навигация фокуса GUI (ui_focus_next).
func _input(event: InputEvent) -> void:
	if not visible and get_tree().get_first_node_in_group("scene_transition"):
		return  # смена сцены: книга и карта под затемнением не открываются
	if event.is_action_pressed("journal"):
		# Карта: из открытой книги — сразу на карту; под чужой паузой (меню, карта уже открыта) — не трогаем.
		if not visible and get_tree().paused:
			return
		close()
		open_map()
	elif event.is_action_pressed("inventory"):
		# Под чужой паузой (меню паузы, настройки) клавиши книги не трогаем — пусть идут дальше.
		if not visible and get_tree().paused:
			return
		_toggle(_last_ray)
	elif not visible:
		return
	elif event.is_action_pressed("ui_cancel"):
		if not _pages().handle_cancel():
			close()
	elif event.is_action_pressed("ui_tab_prev"):
		show_section(wrapi(section - 1, 0, SECTIONS.size()))
	elif event.is_action_pressed("ui_tab_next"):
		show_section(wrapi(section + 1, 0, SECTIONS.size()))
	else:
		return
	get_viewport().set_input_as_handled()


## Открыть книгу на разделе (по умолчанию — на последнем открытом).
func open(at: int = -1) -> void:
	if not visible and _blocked():
		return
	if not visible:
		Audio.play("book_open")
	_hide_game_ui(true)
	visible = true
	get_tree().paused = true
	show_section(section if at < 0 else at)


## Карта во весь экран: карта мира (если она есть в сцене), иначе — карта места.
func open_map() -> void:
	if _blocked():
		return
	var world := get_tree().get_first_node_in_group("world_map")
	if world:
		world.open_map()
	else:
		_location_map.open(map, get_node_or_null(player_path) as Node3D)


## Открыта ли карта места (для тестов и меню).
## Книга и карта не открываются при смене сцены (затемнение выше книги) и во время реплик: окно реплик
## лежит выше книги и перехватывало бы щелчки по ней.
func can_open() -> bool:
	return visible or not _blocked()


func _blocked() -> bool:
	if get_tree().get_first_node_in_group("scene_transition"):
		return true
	var p := get_node_or_null(player_path)
	return p != null and p.get("input_locked")


func is_map_open() -> bool:
	return _location_map.is_open()


## Открыть на последней закладке Рэя или журнала (кнопки HUD и паузы).
func open_half(journal: bool) -> void:
	open(_last_journal if journal else _last_ray)


## Открыть журнал на конкретной записи (ссылка из «Ключевого»).
func open_entry(id: StringName) -> void:
	_journal.pending_entry = id
	if visible:
		show_section(RAY_SECTIONS)
	else:
		open(RAY_SECTIONS)


## Игровой интерфейс (HUD, экранные кнопки) на время книги прячется.
func _hide_game_ui(hide: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for n in ["HUD", "TouchControls"]:
		var layer := scene.get_node_or_null(n) as CanvasLayer
		if layer:
			layer.visible = not hide


func close() -> void:
	if not visible:
		return
	_pages().handle_cancel()
	visible = false
	_hide_game_ui(false)
	Audio.play("book_close")
	get_tree().paused = false
	get_viewport().gui_release_focus()


func show_section(i: int) -> void:
	_pages().handle_cancel()
	if visible and i != section:
		Audio.play("page")
	section = i
	if i < RAY_SECTIONS:
		_last_ray = i
	else:
		_last_journal = i
	for m in _marks:
		m.active = m.index == i
	for page in [_left, _right]:
		for c in page.get_children():
			page.remove_child(c)
			c.queue_free()
	if i < RAY_SECTIONS:
		_character.build(i, _left, _right)
	else:
		_journal.map = map
		_journal.player = get_node_or_null(player_path) as Node3D
		_journal.build(i - RAY_SECTIONS, _left, _right)


func is_ray_section(i: int) -> bool:
	return i < RAY_SECTIONS


## Клавиша раздела: открыть книгу; если она уже открыта на этой половине — закрыть, иначе перелистнуть.
func _toggle(target: int) -> void:
	if not visible:
		open(target)
	elif is_ray_section(section) == is_ray_section(target):
		close()
	else:
		show_section(target)


func _pages() -> Node:
	return _character if is_ray_section(section) else _journal


# --- Построение ----------------------------------------------------------------

func _build(root: Control) -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_CENTER)
	holder.position = (-SIZE / 2.0).floor() - Vector2(0, 8)   # книга чуть выше центра: под ней подсказки клавиш
	holder.size = SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)

	# Закладки добавляются первыми — их корешки уходят под обложку.
	for i in SECTIONS.size():
		var m := _Bookmark.new()
		m.index = i
		m.left_side = i < RAY_SECTIONS
		var row := i if m.left_side else i - RAY_SECTIONS
		m.base_position = Vector2(TAB_LEFT_X if m.left_side else TAB_RIGHT_X, (TABS_LEFT_Y if m.left_side else TABS_RIGHT_Y)[row])
		m.icon_tex = load("res://assets/ui/tabicon_%s.png" % SECTIONS[i][1])
		m.tooltip_text = SECTIONS[i][0]
		m.pressed.connect(show_section.bind(i))
		holder.add_child(m)
		_marks.append(m)

	var cover := TextureRect.new()
	cover.texture = FRAME
	cover.stretch_mode = TextureRect.STRETCH_KEEP
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.size = SIZE
	holder.add_child(cover)
	_left = Control.new()
	_left.position = PAGE_L.position
	_left.size = PAGE_L.size
	cover.add_child(_left)
	_right = Control.new()
	_right.position = PAGE_R.position
	_right.size = PAGE_R.size
	cover.add_child(_right)
	# Язычки лежат поверх кромки, как на рисунке автора.
	for m in _marks:
		holder.move_child(m, -1)

	var close_btn := CloseButton.new()
	close_btn.position = Vector2(472, 17)
	close_btn.pressed.connect(close)
	holder.add_child(close_btn)

	# Подсказка внизу обложки: картинки клавиш, меняются вместе с устройством.
	var hint := HBoxContainer.new()
	hint.position = Vector2(8, SIZE.y + 1)   # под книгой, левее ленточки
	hint.add_theme_constant_override("separation", 3)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(hint)
	hint.add_child(KeyGlyph.new(&"ui_tab_prev"))
	hint.add_child(KeyGlyph.new(&"ui_tab_next"))
	hint.add_child(_hint_label("закладки"))
	hint.add_child(_spacer(10))
	hint.add_child(KeyGlyph.new(&"ui_accept"))
	hint.add_child(_hint_label("выбрать"))
	hint.add_child(_spacer(10))
	hint.add_child(KeyGlyph.new(&"ui_cancel"))
	hint.add_child(_hint_label("закрыть"))


func _hint_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", LIGHT)
	l.add_theme_color_override("font_outline_color", Color("2a1416"))
	l.add_theme_constant_override("outline_size", 2)
	return l


func _spacer(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = w
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _patch(tex: Texture2D, margin: int) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = tex
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		p.set(m, margin)
	return p


## Язычок-закладка с рисунка автора (слева — 4, справа — 4) с иконкой раздела; открытый — зелёный и выдвинут на 3 пикселя.
class _Bookmark extends Button:
	const TEX_L := preload("res://assets/ui/tab_left.png")
	const TEX_L_ACTIVE := preload("res://assets/ui/tab_left_active.png")
	const TEX_R := preload("res://assets/ui/tab_right.png")
	const TEX_R_ACTIVE := preload("res://assets/ui/tab_right_active.png")

	var index: int = 0
	var left_side: bool = false
	var base_position: Vector2
	var icon_tex: Texture2D
	var active: bool = false:
		set(value):
			active = value
			_place()

	func _tex() -> Texture2D:
		if left_side:
			return TEX_L_ACTIVE if active else TEX_L
		return TEX_R_ACTIVE if active else TEX_R

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		custom_minimum_size = _tex().get_size()
		size = custom_minimum_size
		mouse_entered.connect(_place)
		mouse_exited.connect(_place)
		_place()

	func _place() -> void:
		var out := 3.0 if active or is_hovered() else 0.0
		position = base_position + Vector2(-out if left_side else out, 0)
		queue_redraw()

	func _draw() -> void:
		var tex := _tex()
		draw_texture(tex, Vector2.ZERO)
		if icon_tex:
			var c := Vector2(37.0 if left_side else 31.0, tex.get_height() / 2.0 + 1)
			draw_texture(icon_tex, (c - icon_tex.get_size() / 2.0).floor(), Color.WHITE if active or is_hovered() else Color(1, 1, 1, 0.88))
