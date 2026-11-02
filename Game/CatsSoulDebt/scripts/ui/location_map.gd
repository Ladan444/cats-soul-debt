extends CanvasLayer
## Карта места во весь экран (решение автора 2026-10-22: карта — на M, из дневника убрана).
## Там, где есть карта мира (мир вокруг Брода), M открывает её (перемещения между фонарями) — это решает Book.
## Здесь — карта локации из журнала (JournalMap: Рубеж, Брод, таверна): слева — где Рэй, где был,
## что намечено; справа — рисунок карты (JournalMapView) на весь разворот. Игра на паузе.
## M, Esc/B, крестик или клик мимо — закрыть.

const COVER := preload("res://assets/ui/book_cover.png")
const PAGE := preload("res://assets/ui/book_page.png")
const LEFT_W := 190.0

var _content: Control
var _pages: Node


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func is_open() -> bool:
	return visible


func open(map: JournalMap, player: Node3D) -> void:
	if visible:
		return
	if _content:
		_content.queue_free()
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.02, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	_content.add_child(dim)
	var scaler: Control = load("res://scripts/ui/ui_scaler.gd").new()
	scaler.set("min_canvas", Vector2(560, 320))
	_content.add_child(scaler)
	var canvas: Vector2 = scaler.size
	var size := (canvas - Vector2(24, 20)).floor()
	var cover := _patch(COVER, 14)
	cover.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	cover.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.position = ((canvas - size) / 2.0).floor()
	cover.size = size
	scaler.add_child(cover)
	var left := _patch(PAGE, 8)
	left.position = Vector2(12, 10)
	left.size = Vector2(LEFT_W, size.y - 20)
	cover.add_child(left)
	var right := _patch(PAGE, 8)
	right.position = Vector2(12 + LEFT_W + 6, 10)
	right.size = Vector2(size.x - LEFT_W - 30, size.y - 20)
	cover.add_child(right)
	var close_btn := CloseButton.new()
	close_btn.position = Vector2(size.x - 20, 4)
	close_btn.pressed.connect(close)
	cover.add_child(close_btn)
	# Содержимое — те же страницы, что строил журнал: списки мест и рисунок карты.
	if _pages == null:
		_pages = load("res://scripts/ui/book/journal_pages.gd").new()
		add_child(_pages)
	_pages.map = map
	_pages.player = player
	_pages.build_map(left, right)
	visible = true
	get_tree().paused = true
	Audio.play("book_open")


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Audio.play("book_close")


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("journal") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _patch(tex: Texture2D, margin: int) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = tex
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		p.set(m, margin)
	return p
