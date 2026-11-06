class_name DialogueBox
extends CanvasLayer
## Окно реплик: рваный пергамент внизу экрана, табличка с именем говорящего, текст печатается
## по буквам (скорость — настройка «Скорость текста»). Далее — Enter/пробел/A, «Действие», клик или касание:
## первое нажатие допечатывает реплику, следующее — переходит к следующей. Пока окно открыто, Рэй стоит.
## Первое применение — Страж Перекрёстка; задел для системы диалогов (Эпик 4.2).

signal finished
## Ответ на вопрос ask(): номер выбранного варианта.
signal chosen(index: int)

const PAPER := preload("res://assets/ui/panel_torn.png")
const WOOD := preload("res://assets/ui/panel_wood.png")
const INK := Color("2a1e18")
const PANEL := Vector2(420, 84)
## Нижний отступ окна реплик: поднято над хотбаром (иначе он перекрывал нижний край окна).
const BOTTOM_GAP := 76
const CHARS_PER_SECOND := 40.0

var _panel: NinePatchRect
var _name_plate: NinePatchRect
var _name: Label
var _text: Label
var _more: _MoreMark
var _catcher: Control
var _lines: PackedStringArray = []
var _line: int = 0
var _shown: float = 0.0
var _active: bool = false
## Варианты ответа (ask): кнопки под текстом; пусто — обычные реплики.
var _choices: VBoxContainer
var _options: PackedStringArray = []
var _pick: int = 0


func _ready() -> void:
	layer = 18
	var scaler := UIScaler.new()
	add_child(scaler)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scaler.add_child(root)
	# Клик или касание в любом месте экрана — «далее».
	_catcher = Control.new()
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catcher.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			advance()
			_catcher.accept_event())
	root.add_child(_catcher)

	_panel = _patch(PAPER, 14)
	_panel.size = PANEL
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.position = Vector2(-PANEL.x / 2.0, -PANEL.y - BOTTOM_GAP)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)
	_text = Label.new()
	_text.position = Vector2(22, 22)   # рамка панели 14 px + воздух
	_text.size = Vector2(PANEL.x - 44, PANEL.y - 40)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text.add_theme_color_override("font_color", INK)
	_text.add_theme_constant_override("outline_size", 0)
	_text.add_theme_constant_override("line_spacing", 3)
	_panel.add_child(_text)
	_more = _MoreMark.new()
	_more.position = Vector2(PANEL.x - 28, PANEL.y - 24)
	_panel.add_child(_more)

	_name_plate = _patch(WOOD, 12)
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_name_plate)
	_name = Label.new()
	_name.add_theme_color_override("font_color", Color("e8c870"))
	_name.add_theme_color_override("font_outline_color", Color("2e1d14"))
	_name.add_theme_constant_override("outline_size", 2)
	_name.position = Vector2(8, 4)
	_name_plate.add_child(_name)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 1)
	_choices.position = Vector2(PANEL.x - 190, PANEL.y + 2)
	_choices.visible = false
	_panel.add_child(_choices)
	visible = false


func is_active() -> bool:
	return _active


## Показать реплики speaker по очереди; по последней — сигнал finished.
func play(speaker: String, lines: PackedStringArray) -> void:
	_lines = lines
	_line = 0
	_active = true
	visible = true
	_name.text = speaker
	_name.reset_size()
	_name_plate.size = Vector2(_name.size.x + 16, 18)
	_name_plate.position = Vector2(10, -12)
	_show_line()


## Вопрос с вариантами ответа: реплика question, затем выбор (стрелки/стик и «далее», клик, касание).
## По выбору — сигнал chosen(номер).
func ask(speaker: String, question: String, options: PackedStringArray) -> void:
	_options = options
	_pick = 0
	play(speaker, PackedStringArray([question]))


func _show_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()
	for i in _options.size():
		var b := Button.new()
		b.text = _options[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(170, 14)
		b.add_theme_font_size_override("font_size", 8)
		b.pressed.connect(_choose.bind(i))
		b.mouse_entered.connect(func(): _pick = i; _mark_pick())
		_choices.add_child(b)
	_choices.visible = true
	_mark_pick()


func _mark_pick() -> void:
	for i in _choices.get_child_count():
		var b := _choices.get_child(i) as Button
		b.text = ("> " if i == _pick else "  ") + _options[i]


func _choose(i: int) -> void:
	_options = PackedStringArray()
	_choices.visible = false
	_active = false
	visible = false
	# Сначала finished, потом chosen: по выбору обычно сразу начинается новая реплика (Npc.say), и её
	# обработчик finished не должен сработать от этого же вопроса — иначе ответ проскакивал непоказанным.
	finished.emit()
	chosen.emit(i)


## Далее: допечатать текущую реплику или перейти к следующей.
func advance() -> void:
	if not _active:
		return
	if _text.visible_ratio < 1.0:
		_text.visible_ratio = 1.0
		_shown = float(_text.text.length())
		return
	if not _options.is_empty():
		if _choices.visible:
			_choose(_pick)
		return
	_line += 1
	if _line >= _lines.size():
		_active = false
		visible = false
		finished.emit()
	else:
		_show_line()


func _show_line() -> void:
	_text.text = _lines[_line]
	_text.visible_characters = 0
	_shown = 0.0


func _process(delta: float) -> void:
	if not _active:
		return
	if _text.visible_ratio < 1.0:
		_shown += delta * CHARS_PER_SECOND * float(Settings.get_value("text_speed"))
		_text.visible_characters = int(_shown)
	_more.visible = _text.visible_ratio >= 1.0 and _options.is_empty()
	if not _options.is_empty() and _text.visible_ratio >= 1.0 and not _choices.visible:
		_show_choices()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if _choices.visible:
		var dir := int(event.is_action_pressed("ui_down") or event.is_action_pressed("move_down")) \
			- int(event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"))
		if dir != 0:
			_pick = wrapi(_pick + dir, 0, _options.size())
			_mark_pick()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		advance()
		get_viewport().set_input_as_handled()


func _patch(tex: Texture2D, margin: int) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = tex
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		p.set(m, margin)
	p.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	p.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	return p


## Мигающий уголок «далее» в углу пергамента.
class _MoreMark extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(9, 6)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var bob := 1.0 if int(Time.get_ticks_msec() / 350) % 2 == 0 else 0.0
		draw_colored_polygon(PackedVector2Array([Vector2(0, bob), Vector2(8, bob), Vector2(4, 5 + bob)]), Color("7a2a24"))
