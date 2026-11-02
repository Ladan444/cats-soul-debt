class_name SettingRow
extends Button
## Строка настройки на пергаменте: подпись слева, справа — «◀ значение ▶» (OPTIONS) или ползунок-ремешок (SLIDER).
## Влево/вправо (клавиатура, крестовина, стик) меняют значение; мышью — клик по стрелкам или по ремешку.

signal value_changed(value: Variant)

enum Kind { OPTIONS, SLIDER }

const CLAW := preload("res://assets/ui/claw.png")
const INK := Color("2a1e18")
const FOCUS := Color("3f6a4a")
const LEATHER := Color("5c3a2a")
const LEATHER_DARK := Color("2e1d14")
const BRASS := Color("c9a040")
const BRASS_LIGHT := Color("e8c870")
## Доля ширины строки, с которой начинается правая часть.
const VALUE_START := 0.58

var label: String
var kind: Kind
var options: PackedStringArray = []
var index: int = 0
var min_value: float = 0.0
var max_value: float = 1.0
var step: float = 0.05
var value: float = 0.0
## Как показывать значение ползунка: "percent" или "multiplier".
var display: String = "percent"

var _time: float = 0.0
var _dragging: bool = false


static func make_options(text: String, opts: PackedStringArray, current: int) -> SettingRow:
	var r := SettingRow.new()
	r.label = text
	r.kind = Kind.OPTIONS
	r.options = opts
	r.index = clampi(current, 0, opts.size() - 1)
	return r


static func make_slider(text: String, from: float, to: float, current: float, step_size := 0.05, fmt := "percent") -> SettingRow:
	var r := SettingRow.new()
	r.label = text
	r.kind = Kind.SLIDER
	r.min_value = from
	r.max_value = to
	r.step = step_size
	r.value = current
	r.display = fmt
	return r


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, 12)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(grab_focus)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _process(delta: float) -> void:
	if has_focus():
		_time += delta
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		_step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		_step(1)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_click(event.position.x)
			_dragging = kind == Kind.SLIDER
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_click(event.position.x)
		accept_event()


func _step(direction: int) -> void:
	if kind == Kind.OPTIONS:
		_set_index(index + direction)
	else:
		_set_value(value + step * direction)


func _click(x: float) -> void:
	var vx := size.x * VALUE_START
	if kind == Kind.OPTIONS:
		if x < vx + 8:
			_step(-1)
		elif x > size.x - 8:
			_step(1)
	else:
		var track := _track_rect()
		_set_value(lerpf(min_value, max_value, clampf((x - track.position.x) / track.size.x, 0.0, 1.0)))


func _set_index(i: int) -> void:
	i = clampi(i, 0, options.size() - 1)
	if i != index:
		index = i
		queue_redraw()
		value_changed.emit(index)


func _set_value(v: float) -> void:
	v = clampf(snappedf(v, step), min_value, max_value)
	if not is_equal_approx(v, value):
		value = v
		queue_redraw()
		value_changed.emit(value)


func _track_rect() -> Rect2:
	var vx := size.x * VALUE_START
	return Rect2(vx + 2, floorf(size.y / 2.0) - 2, size.x - vx - 30, 4)


func _draw() -> void:
	var font := get_theme_default_font()
	var focused := has_focus()
	var color := FOCUS if focused else INK
	var baseline := floorf(size.y / 2.0) + 4
	if focused:
		draw_texture(CLAW, Vector2(1 + roundf(sin(_time * 5.0)), floorf((size.y - 7) / 2.0)))
	draw_string(font, Vector2(12, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)

	var vx := size.x * VALUE_START
	if kind == Kind.OPTIONS:
		var w := size.x - vx
		_triangle(Vector2(vx + 2, floorf(size.y / 2.0)), -1, color if index > 0 else Color(color, 0.25))
		_triangle(Vector2(size.x - 3, floorf(size.y / 2.0)), 1, color if index < options.size() - 1 else Color(color, 0.25))
		draw_string(font, Vector2(vx + 8, baseline), options[index], HORIZONTAL_ALIGNMENT_CENTER, w - 16, 8, color)
	else:
		var track := _track_rect()
		var t := (value - min_value) / (max_value - min_value)
		# Ремешок: кожа с тёмной окантовкой и стежками, заполненная часть светлее.
		draw_rect(track.grow(1), LEATHER_DARK)
		draw_rect(track, LEATHER)
		draw_rect(Rect2(track.position, Vector2(floorf(track.size.x * t), track.size.y)), Color("8a5a3a"))
		for sx in range(int(track.position.x) + 2, int(track.end.x), 4):
			draw_rect(Rect2(sx, track.position.y + 1, 1, 1), Color("c9b387"))
		var kx := track.position.x + floorf(track.size.x * t) - 2
		draw_rect(Rect2(kx, track.position.y - 2, 5, 8), LEATHER_DARK)
		draw_rect(Rect2(kx + 1, track.position.y - 1, 3, 6), BRASS)
		draw_rect(Rect2(kx + 1, track.position.y - 1, 1, 1), BRASS_LIGHT)
		var text := ("%d%%" % roundi(value * 100.0)) if display == "percent" else ("×%.1f" % value)
		draw_string(font, Vector2(track.end.x + 4, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)


## Пиксельный треугольник-стрелка высотой 5: direction -1 — влево, 1 — вправо.
func _triangle(tip: Vector2, direction: int, color: Color) -> void:
	for i in 3:
		var x := tip.x - direction * i
		draw_rect(Rect2(x, tip.y - i, 1, i * 2 + 1), color)
