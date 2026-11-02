class_name TouchControls
extends Control
## Сенсорное управление (UI_SPEC 7б): плавающий джойстик слева — где коснулись, там и центр;
## справа кнопки «Удар» (крупная), «Рывок», «Действие». Скиллы и предметы — касанием ячеек хотбара.
## Видно, когда играют касанием (или всегда/никогда — настройка «Сенсорное управление»).
## Мультитач: джойстик и кнопки работают одновременно. Родитель — UIScaler (размеры в UI-пикселях).

const ICON_SWORD := preload("res://assets/ui/sicon_sword.png")
const ICON_DASH := preload("res://assets/ui/sicon_dash.png")
const ICON_PAW := preload("res://assets/ui/sicon_paw.png")
const STICK_RADIUS := 26.0
const KNOB_RADIUS := 10.0
const DEADZONE := 0.2
## Полуширина хотбара от центра экрана (HUD) — джойстик не начинается поверх ячеек.
const HOTBAR_HALF := 124.0
const INK := Color(0.16, 0.12, 0.1, 0.55)
const RIM := Color(0.9, 0.84, 0.69, 0.55)
const RIM_ACTIVE := Color(0.91, 0.78, 0.44, 0.9)

## Кнопки: действие, иконка, радиус, смещение центра от правого нижнего угла.
var _buttons := [
	{"action": &"attack", "icon": ICON_SWORD, "radius": 18.0, "offset": Vector2(-34, -40)},
	{"action": &"dash", "icon": ICON_DASH, "radius": 12.0, "offset": Vector2(-72, -24)},
	{"action": &"interact", "icon": ICON_PAW, "radius": 12.0, "offset": Vector2(-28, -82)},
]
var _stick_touch: int = -1
var _stick_center: Vector2
var _stick_vector: Vector2 = Vector2.ZERO
var _button_touch: Dictionary = {}  # индекс касания -> индекс кнопки


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _process(_delta: float) -> void:
	var show := InputGlyphs.touch_controls_visible() and not get_tree().paused
	if show != visible:
		visible = show
		if not show:
			_release_all()
	if visible:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var pos := _to_local(event.position)
		if event.pressed:
			var b := _button_at(pos)
			if b >= 0:
				_button_touch[event.index] = b
				_send(_buttons[b]["action"], true)
				get_viewport().set_input_as_handled()
			elif _stick_touch == -1 and _in_stick_zone(pos):
				_stick_touch = event.index
				_stick_center = pos
				_set_stick(Vector2.ZERO)
				get_viewport().set_input_as_handled()
		else:
			if _button_touch.has(event.index):
				_send(_buttons[_button_touch[event.index]]["action"], false)
				_button_touch.erase(event.index)
			elif event.index == _stick_touch:
				_stick_touch = -1
				_set_stick(Vector2.ZERO)
	elif event is InputEventScreenDrag and event.index == _stick_touch:
		var offset := _to_local(event.position) - _stick_center
		_set_stick(offset.limit_length(STICK_RADIUS) / STICK_RADIUS)
		get_viewport().set_input_as_handled()


## Нажатие или отпускание действия как настоящим вводом (удар читается в _unhandled_input игрока).
func _send(action: StringName, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


## Отклонение стика 0..1 по каждому направлению — как аналоговый стик геймпада.
func _set_stick(v: Vector2) -> void:
	_stick_vector = v if v.length() > DEADZONE else Vector2.ZERO
	var dirs := {&"move_right": maxf(_stick_vector.x, 0.0), &"move_left": maxf(-_stick_vector.x, 0.0),
		&"move_down": maxf(_stick_vector.y, 0.0), &"move_up": maxf(-_stick_vector.y, 0.0)}
	for action in dirs:
		if dirs[action] > 0.0:
			Input.action_press(action, dirs[action])
		else:
			Input.action_release(action)


func _release_all() -> void:
	for index in _button_touch:
		_send(_buttons[_button_touch[index]]["action"], false)
	_button_touch.clear()
	_stick_touch = -1
	_set_stick(Vector2.ZERO)


func _to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _button_center(b: Dictionary) -> Vector2:
	return size + b["offset"]


func _button_at(pos: Vector2) -> int:
	for i in _buttons.size():
		# Область касания чуть больше нарисованной кнопки.
		if pos.distance_to(_button_center(_buttons[i])) <= _buttons[i]["radius"] + 4.0:
			return i
	return -1


## Джойстик: левая часть экрана ниже кнопок меню, но не поверх хотбара.
func _in_stick_zone(pos: Vector2) -> bool:
	if pos.x > size.x * 0.45 or pos.y < size.y * 0.3:
		return false
	return not (pos.y > size.y - 50.0 and pos.x > size.x / 2.0 - HOTBAR_HALF - 6.0)


## Где стоит джойстик, пока его не трогают.
func _rest_center() -> Vector2:
	return Vector2(minf(56.0, size.x / 2.0 - HOTBAR_HALF - 34.0), size.y - 48.0)


func _draw() -> void:
	var center := _stick_center if _stick_touch != -1 else _rest_center()
	_ring(center, STICK_RADIUS, RIM if _stick_touch != -1 else Color(RIM, 0.3))
	draw_circle(center, STICK_RADIUS - 1.0, Color(INK, 0.25), true, -1.0, false)
	draw_circle(center + _stick_vector * STICK_RADIUS, KNOB_RADIUS, Color(RIM, 0.75 if _stick_touch != -1 else 0.35), true, -1.0, false)
	var pressed := _button_touch.values()
	for i in _buttons.size():
		var b: Dictionary = _buttons[i]
		var c := _button_center(b)
		var down := pressed.has(i)
		draw_circle(c, b["radius"], Color(INK, 0.75) if down else INK, true, -1.0, false)
		_ring(c, b["radius"], RIM_ACTIVE if down else RIM)
		var icon: Texture2D = b["icon"]
		var s := 2.0 if b["radius"] >= 16.0 else 1.0
		var icon_size := icon.get_size() * s
		draw_texture_rect(icon, Rect2((c - icon_size / 2.0).floor() + Vector2(0, 1 if down else 0), icon_size), false)


func _ring(center: Vector2, radius: float, color: Color) -> void:
	draw_arc(center, radius, 0.0, TAU, 48, color, 2.0, false)
