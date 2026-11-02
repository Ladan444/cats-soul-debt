extends Control
## Главное меню (UI_SPEC, раздел 5): деревянная вывеска с названием, пункты с «когтем»,
## выбор сложности для новой игры, авторы, настройки. Фон и рама — рисунки автора (menu_bg.png, menu_frame.png,
## холст 640×360; `Tools/ui_kit_pipeline.py extras`), название — текстом в табличке рамы.

## Новая игра начинается в таверне: Рэй просыпается в своей комнате (пролог Главы 1, CHAPTER1.md).
const GAME_SCENE := "res://scenes/levels/tavern.tscn"
const CLOTH := preload("res://assets/ui/menu_cloth.png")
const FRAME := preload("res://assets/ui/menu_frame.png")
const PAPER := preload("res://assets/ui/panel_torn.png")
const INK := Color("2a1e18")
const DIFF_TEXT := [
	"Потеря 50% гелиосов спуска при смерти.",
	"Потеря 75% гелиосов спуска при смерти.",
	"Потеря 90% гелиосов спуска при смерти.",
]

var _menu: VBoxContainer
var _difficulty: NinePatchRect
var _diff_hint: Label
var _credits: NinePatchRect
var _credits_scroll: ScrollContainer
var _settings: SettingsMenu
var _last_focus: Control
## Сцена меню 640×360 UI-пикселей (размер рисунка рамы): на другом размере холста стоит по центру, вокруг — ткань.
var _stage: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fit_scale.call_deferred()   # родитель (UIScaler) читает масштаб из настроек в своём _ready, который идёт после нашего
	Settings.changed.connect(func(key): if key == "ui_scale": _fit_scale())
	_build_sign()
	_build_menu()
	_difficulty = _build_difficulty()
	_credits = _build_credits()
	_settings = SettingsMenu.new()
	_settings.closed.connect(_back_to_menu)
	add_child(_settings)

	var version := Label.new()
	version.text = "Бета 0.0.3
Ladan444"
	version.add_theme_color_override("font_color", Color("8a7a60"))
	version.position = Vector2(34, 360 - 62)
	_stage.add_child(version)

	_focus_later(_menu.get_child(0))


## «Авторы»: вверх/вниз (стрелки, крестовина, стик) плавно прокручивают текст — по силе нажатия, каждый кадр
## (события стика приходят пачками, по шагу на событие прокрутка «прыгала»).
func _process(delta: float) -> void:
	if _credits and _credits.visible:
		var axis := Input.get_axis("ui_up", "ui_down")
		if absf(axis) > 0.2:
			_credits_scroll.scroll_vertical += int(signf(axis) * maxf(absf(axis) * 260.0 * delta, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_difficulty.visible or _credits.visible):
		_back_to_menu()
		get_viewport().set_input_as_handled()


## Меню рисуется на холсте 640×360 с целым масштабом на весь экран (на 1080p ×3, на 1440p ×4, на 4K ×6),
## независимо от «Масштаба интерфейса» из настроек — иначе рама и подписи на полном экране разъезжались.
func _fit_scale() -> void:
	var scaler := get_parent() as UIScaler
	if scaler:
		scaler.min_canvas = Vector2(640, 360)
		scaler.ui_scale = 99


func _build_sign() -> void:
	# Фон — тёмно-зелёная ткань на весь экран, рама автора — поверх, по центру холста.
	var cloth := TextureRect.new()
	cloth.texture = CLOTH
	cloth.stretch_mode = TextureRect.STRETCH_TILE
	cloth.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cloth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cloth)
	_stage = Control.new()
	_stage.size = Vector2(640, 360)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	resized.connect(_center_stage)
	_center_stage.call_deferred()
	# Рама — картинка 1920×1080 на холсте 640×360 (на 1080p один к одному) с линейным фильтром: чётче, чем сведённая к 640×360.
	var frame := TextureRect.new()
	frame.texture = FRAME
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = Vector2(640, 360)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(frame)
	# Название — английское, одной строкой в деревянной табличке рамы (по рисунку: x 109–528, y 29–69 холста над
	# эмблемой кошки); 16 px без сжатия интервала — 19 знаков = 304 px (24 px не влезает в табличку), буквы чёткие.
	var l := Label.new()
	l.text = "The Cat's Soul Debt"
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("e8c870"))
	l.add_theme_color_override("font_outline_color", Color("2e1d14"))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector2(109, 29)
	l.size = Vector2(419, 38)
	_stage.add_child(l)


func _center_stage() -> void:
	_stage.position = ((size - _stage.size) / 2.0).floor()


func _build_menu() -> void:
	_menu = VBoxContainer.new()
	_menu.position = Vector2(48, 158)
	_menu.add_theme_constant_override("separation", 4)
	_stage.add_child(_menu)
	if SaveGame.has_save():
		_item("Продолжить", func(): ChapterEndScreen.open(get_tree()) if ChapterEndScreen.save_is_finished() else SaveGame.load_and_continue())
	_item("Новая игра", func(): _open(_difficulty))
	var load := _item("Загрузить", func(): pass)
	load.disabled = true
	load.tooltip_text = "Список сохранений появится позже"
	_item("Настройки", func():
		_hide_panels()
		_menu.visible = false
		_settings.open())
	_item("Авторы", func(): _open(_credits))
	_item("Выход", func(): get_tree().quit())


func _item(text: String, action: Callable) -> ClawButton:
	var b := ClawButton.new(text)
	b.custom_minimum_size.x = 140
	b.pressed.connect(func():
		_last_focus = b
		action.call())
	_menu.add_child(b)
	return b


func _paper(panel_size: Vector2, title: String) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = PAPER
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		p.set(m, 14)
	p.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	p.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	p.size = panel_size
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.position = -panel_size / 2.0
	p.visible = false
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 12)
	t.size = Vector2(panel_size.x, 16)
	p.add_child(t)
	var close_btn := CloseButton.new()
	close_btn.position = Vector2(panel_size.x - 22, 8)
	close_btn.pressed.connect(_back_to_menu)
	p.add_child(close_btn)
	add_child(p)
	return p


func _build_difficulty() -> NinePatchRect:
	var p := _paper(Vector2(360, 150), "Новая игра")
	var box := VBoxContainer.new()
	box.position = Vector2(24, 40)
	box.add_theme_constant_override("separation", 3)
	p.add_child(box)
	for i in Settings.DIFFICULTIES.size():
		var b := ClawButton.new(Settings.DIFFICULTIES[i], true)
		b.custom_minimum_size.x = 200
		b.focus_entered.connect(func(): _diff_hint.text = DIFF_TEXT[i])
		b.pressed.connect(func(): SaveGame.new_game(i, GAME_SCENE))
		box.add_child(b)
	var back := ClawButton.new("Назад", true)
	back.pressed.connect(_back_to_menu)
	box.add_child(back)
	_diff_hint = Label.new()
	_diff_hint.add_theme_color_override("font_color", Color("4e6253"))
	_diff_hint.position = Vector2(24, 104)
	_diff_hint.size = Vector2(312, 10)
	p.add_child(_diff_hint)
	var note := Label.new()
	note.text = "Сложность можно сменить в настройках."
	note.add_theme_color_override("font_color", Color("8a7350"))
	note.position = Vector2(24, 120)
	p.add_child(note)
	return p


func _build_credits() -> NinePatchRect:
	var p := _paper(Vector2(360, 200), "Авторы")
	# Текст длинный (авторы музыки — лицензия CC-BY требует их указать) — в прокрутке; «Назад» под ней.
	var box := VBoxContainer.new()
	box.position = Vector2(20, 38)
	box.add_theme_constant_override("separation", 6)
	p.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(p.size.x - 32, p.size.y - 76)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_credits_scroll = scroll
	var text := Label.new()
	text.add_theme_color_override("font_color", INK)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.custom_minimum_size.x = p.size.x - 46
	text.text = ("Долг Кошачьей Души

"
		+ "Идея, мир, сюжет, арт-дирекшн — Ladan444
"
		+ "Код и инструменты — с помощью Claude
"
		+ "Шрифты Public Pixel и First Time Writing — GGBotNet (CC0)
"
		+ "Движок — Godot Engine

"
		+ "Музыка (OpenGameArt.org):
" + Audio.music_credits() + "

"
		+ "Звуки — Kenney (CC0), OpenGameArt.org
"
		+ "Модели — Quaternius (Medieval Village MegaKit, Ultimate Stylized Nature Pack), KayKit (CC0)")
	scroll.add_child(text)
	var back := ClawButton.new("Назад", true)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_back_to_menu)
	box.add_child(back)
	return p


func _open(panel: Control) -> void:
	_hide_panels()
	_menu.visible = false
	panel.visible = true
	# Первый пункт панели получает фокус.
	for child in panel.find_children("*", "Button", true, false):
		if child is ClawButton:
			_focus_later(child)
			break


func _hide_panels() -> void:
	_difficulty.visible = false
	_credits.visible = false


func _back_to_menu() -> void:
	_hide_panels()
	_menu.visible = true
	var target: Control = _last_focus if is_instance_valid(_last_focus) else _menu.get_child(0)
	_focus_later(target)


## Фокус в следующем кадре — но только если узел ещё в дереве (сцена могла смениться).
func _focus_later(target: Control) -> void:
	(func(): if is_instance_valid(target) and target.is_inside_tree(): target.grab_focus()).call_deferred()
