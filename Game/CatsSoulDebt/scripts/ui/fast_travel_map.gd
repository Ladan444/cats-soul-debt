extends CanvasLayer
## Карта мира с быстрыми перемещениями (решение автора 2026-10-22: «как в Genshin Impact», откуда угодно):
## M (через Book.open_map) или «Карта» в паузе — карта во весь экран, игра на паузе. Фонари душ — значки: зажжённые
## фиолетовые, к ним можно перенестись; незажжённые серые. Подписи мест, Рэй — белая стрелка.
## Мышь: колесо — масштаб, перетаскивание — сдвиг, клик по фонарю — выбрать. Клавиатура/геймпад:
## движение — сдвиг, правый стик / PgUp-PgDn — масштаб, Q/E (LB/RB) — по зажжённым фонарям,
## Enter/A — перенестись, Esc/B/M — закрыть. Перенос: затемнение, Рэй у подножия фонаря, камера сразу за ним.

const LIT := Color(0.78, 0.6, 1.0)
const UNLIT := Color(0.5, 0.48, 0.54)
const FRAME := Color("2a1e18")
const PARCHMENT := Color("e6d6b0")
const FADE := 0.35

@export var player_path: NodePath
@export var camera_path: NodePath
@export var map_texture: Texture2D
## Godot (x, z) левого верхнего пикселя карты и метров на пиксель.
@export var map_origin := Vector2.ZERO
@export var map_mpp := 1.0
## Туман поверх карты (у подземелий: неоткрытое тёмное; та же картинка, что у миникарты) и заголовок окна.
@export var fog_texture: Texture2D
@export var title_text := "Карта мира — Долина Серебряной Реки"
## Подписи мест: [[название, Vector2(x, z)], ...].
@export var places: Array = []
## Перенос к зажжённому фонарю бесплатный (в том числе через проводника-сову у фонаря — он открывает эту же карту).
## Перенос в любую точку карты стоит POINT_TRAVEL_COST гелиосов: Рэй появляется на ближайшей к точке дороге.
## Цена меняется только здесь (баланс — BALANCE.md, чат «Бой»).
const POINT_TRAVEL_COST := 100

var _traveling := false
## Имя узла фонаря → подпись («Фонарь у шахты»).
@export var lantern_names: Dictionary = {}

var _player: Node3D
var _camera: Node3D
var _scaler: Control
var _view: Control
var _panel: PanelContainer
var _title: Label
var _status: Label
var _go: ClawButton
var _fade: ColorRect
var _zoom := 1.0
var _fit := 1.0
var _center := Vector2.ZERO
var _selected: Node3D
## Выбранная точка карты для платного переноса (метры мира) и точка дороги, где Рэй появится.
var _point: Variant = null
var _landing := Vector2.ZERO
var _press_at := Vector2.ZERO
var _moved := false
var _dragging := false
var _time := 0.0


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("world_map")
	_player = get_node_or_null(player_path) as Node3D
	PlayerState.helios_changed.connect(func(_h, _d): if is_open(): _refresh_panel())
	_camera = get_node_or_null(camera_path) as Node3D
	_scaler = load("res://scripts/ui/ui_scaler.gd").new()
	_scaler.set("min_canvas", Vector2(480, 300))
	add_child(_scaler)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.05, 0.92)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scaler.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view = Control.new()
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_map)
	_view.gui_input.connect(_view_input)
	_scaler.add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.offset_left = 8
	_view.offset_top = 28
	_view.offset_right = -8
	_view.offset_bottom = -20
	var head := Label.new()
	head.text = title_text
	head.add_theme_color_override("font_color", PARCHMENT)
	head.position = Vector2(10, 6)
	_scaler.add_child(head)
	# Навигатор: цель, расстояние по маршруту и клавиши метки — вторая строка заголовка.
	_nav = Label.new()
	_nav.add_theme_font_size_override("font_size", 8)
	_nav.add_theme_color_override("font_color", Color("ffd24a"))
	_nav.position = Vector2(10, 14)
	_nav.size = Vector2(380, 10)
	_nav.clip_text = true
	_scaler.add_child(_nav)
	_keys = Label.new()
	var keys := _keys
	keys.text = "ПКМ/F/Y — метка   T — задание"
	keys.add_theme_font_size_override("font_size", 8)
	keys.add_theme_color_override("font_color", Color(PARCHMENT, 0.75))
	keys.position = Vector2(400, 14)
	keys.size = Vector2(210, 10)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scaler.add_child(keys)
	var hint := Label.new()
	hint.name = "Hint"
	hint.add_theme_color_override("font_color", Color(PARCHMENT, 0.75))
	hint.add_theme_font_size_override("font_size", 8)
	_scaler.add_child(hint)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 10
	hint.offset_top = -15
	hint.offset_bottom = -3
	var close := CloseButton.new()
	close.pressed.connect(close_map)
	_scaler.add_child(close)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.position.x -= 22
	close.position.y += 4
	_build_panel()
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.01, 0.03, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 13
	add_child(fade_layer)
	fade_layer.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.visible = false
	_set_open(false)


var _nav: Label
var _keys: Label


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(120, 0)
	_scaler.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # растёт влево от правого края, а не за экран
	_panel.offset_right = -12
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_title.custom_minimum_size = Vector2(110, 0)
	v.add_child(_title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 8)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(110, 0)
	v.add_child(_status)
	_go = ClawButton.new("Перенестись")
	_go.pressed.connect(func(): _go_pressed())
	v.add_child(_go)
	_panel.visible = false


func is_open() -> bool:
	return _scaler.visible


func _set_open(on: bool) -> void:
	_scaler.visible = on


func open_map() -> void:
	if is_open() or map_texture == null:
		return
	if _player and (_player.get("input_locked") or not _player.call("is_alive")):
		return
	_set_open(true)
	get_tree().paused = true
	var hint := _scaler.get_node("Hint") as Label
	_keys.visible = Waypoints.in_world(get_tree())   # метки и платный перенос — только в большом мире
	var first := "%s — фонарь или точка (100 г.)" if Waypoints.in_world(get_tree()) else "%s — фонарь"
	hint.text = (first + "  колесо — масштаб  %s/%s — фонари  %s — перенестись  %s — закрыть") % [
		"ЛКМ", InputGlyphs.label(&"ui_tab_prev"), InputGlyphs.label(&"ui_tab_next"),
		InputGlyphs.label(&"ui_accept"), InputGlyphs.label(&"ui_cancel")]
	await get_tree().process_frame
	var tex := map_texture.get_size()
	_fit = minf(_view.size.x / tex.x, _view.size.y / tex.y)
	_zoom = _fit * 2.0
	_center = _to_map(_player.global_position) if _player else tex / 2.0
	_select(null)
	_clamp()
	_view.queue_redraw()


func close_map() -> void:
	if not is_open():
		return
	_set_open(false)
	get_tree().paused = false


func _lanterns() -> Array:
	return get_tree().get_nodes_in_group("soul_lanterns")


func _to_map(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - map_origin) / map_mpp


func _to_view(m: Vector2) -> Vector2:
	return (m - _center) * _zoom + _view.size / 2.0


func _clamp() -> void:
	_zoom = clampf(_zoom, _fit, _fit * 8.0)
	var tex := map_texture.get_size()
	var half := _view.size / 2.0 / _zoom
	_center.x = clampf(_center.x, minf(half.x, tex.x / 2.0), maxf(tex.x - half.x, tex.x / 2.0))
	_center.y = clampf(_center.y, minf(half.y, tex.y / 2.0), maxf(tex.y - half.y, tex.y / 2.0))


func _process(delta: float) -> void:
	if not is_open():
		return
	_time += delta
	_refresh_nav()
	var pan := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var zoom_axis := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if Input.is_key_pressed(KEY_PAGEUP):
		zoom_axis = -1.0
	elif Input.is_key_pressed(KEY_PAGEDOWN):
		zoom_axis = 1.0
	if pan.length() > 0.1:
		_center += pan * 260.0 * delta / _zoom
	if absf(zoom_axis) > 0.25:
		_zoom *= 1.0 - zoom_axis * 1.5 * delta
	_clamp()
	_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_open() or _fade.visible:
		return
	if event.is_action_pressed("journal") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close_map()
	elif event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		_cycle(1 if event.is_action_pressed("ui_tab_next") else -1)
	elif event.is_action_pressed("ui_accept") and (_selected or _point != null):
		_go_pressed()   # Enter / A: перенос к выбранному фонарю или в выбранную точку
	elif event.is_action_pressed("ui_accept"):
		_select_point(_center)   # ничего не выбрано — точка в центре карты (геймпад и клавиатура); второй Enter переносит
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_T:
		Waypoints.cycle_tracked(get_tree())   # следующее отслеживаемое задание
	elif (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F) 			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y):
		_toggle_mark(_center)   # метка в центре карты (для клавиатуры и геймпада)
	else:
		return
	get_viewport().set_input_as_handled()


func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var before := (mb.position - _view.size / 2.0) / _zoom + _center
			_zoom *= 1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
			_clamp()
			_center = before - (mb.position - _view.size / 2.0) / _zoom
			_clamp()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_toggle_mark((mb.position - _view.size / 2.0) / _zoom + _center)   # ПКМ — поставить/снять свою метку
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			var hit := _lantern_at(mb.position)
			if hit:
				if hit == _selected and mb.double_click:
					_travel(hit)
				else:
					_select(hit)
			else:
				_dragging = true
				_press_at = mb.position
				_moved = false
	elif event is InputEventMouseButton and not event.pressed:
		# Клик без перетаскивания по пустому месту карты — выбрать точку для платного переноса.
		if _dragging and not _moved and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_select_point((_press_at - _view.size / 2.0) / _zoom + _center)
		_dragging = false
	elif event is InputEventMouseMotion and _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false   # кнопку отпустили за пределами карты
	elif event is InputEventMouseMotion and _dragging:
		if (event as InputEventMouseMotion).position.distance_to(_press_at) > 4.0:
			_moved = true
		_center -= (event as InputEventMouseMotion).relative / _zoom
		_clamp()
	_view.queue_redraw()


## Своя метка игрока на карте (точка m — в пикселях карты): рядом с уже стоящей — снимает её.
func _toggle_mark(m: Vector2) -> void:
	var world := m * map_mpp + map_origin
	if Waypoints.custom != null and (Waypoints.custom as Vector2).distance_to(world) < 12.0 / _zoom * map_mpp:
		Waypoints.custom = null
	else:
		Waypoints.custom = world
	_view.queue_redraw()


func _lantern_at(pos: Vector2) -> Node3D:
	var best: Node3D = null
	var best_d := 10.0
	for l in _lanterns():
		var d := _to_view(_to_map(l.global_position)).distance_to(pos)
		if d < best_d:
			best = l
			best_d = d
	return best


## Следующий/предыдущий зажжённый фонарь (по кругу), карта сдвигается к нему.
func _cycle(dir: int) -> void:
	var lit := _lanterns().filter(func(l): return l.get("lit"))
	if lit.is_empty():
		return
	var i := lit.find(_selected)
	i = (i + dir + lit.size()) % lit.size() if i >= 0 else 0
	_select(lit[i])
	_center = _to_map(lit[i].global_position)
	_clamp()


func _select(l: Node3D) -> void:
	_selected = l
	_point = null
	_refresh_panel()


## Платный перенос: выбрана точка карты (m — пиксели карты).
func _select_point(m: Vector2) -> void:
	if not Waypoints.in_world(get_tree()):
		return   # дорог в подземелье нет: платный перенос в точку — только в большом мире
	var world := m * map_mpp + map_origin
	var road: Variant = Waypoints.nearest_road_point(world)
	if road == null:
		return
	_selected = null
	_point = world
	_landing = road
	_refresh_panel()


func _refresh_panel() -> void:
	if _selected == null and _point == null:
		_panel.visible = false
		return
	_panel.visible = true
	var wallet := PlayerState.helios
	if _selected != null:
		var l := _selected
		_title.text = lantern_names.get(String(l.name), "Фонарь душ")
		var lit: bool = l.get("lit")
		_status.text = "Фонарь зажжён — перенос бесплатный." if lit else "Не зажжён: сначала доберись до него и зажги."
		_go.text = "Перенестись"
		_go.disabled = not lit
		if lit:
			_go.grab_focus()
		return
	_title.text = "Точка на карте"
	var can_pay := wallet >= POINT_TRAVEL_COST
	var off := (_point as Vector2).distance_to(_landing)
	_status.text = "Рэй появится на ближайшей дороге (%d м от точки). Гелиосов: %d." % [int(off), wallet]
	_go.text = "Перенестись (%d г.)" % POINT_TRAVEL_COST if can_pay else "Не хватает гелиосов"
	_go.disabled = not can_pay
	if can_pay:
		_go.grab_focus()


func _go_pressed() -> void:
	if _selected != null:
		_travel(_selected)
	elif _point != null:
		_travel_point()


func _travel(l: Node3D) -> void:
	# Двойной щелчок по «Перенестись» во время затемнения запускал перенос дважды.
	if l == null or not l.get("lit") or _player == null or _traveling:
		return
	_do_travel(l.call("respawn_point") + Vector3(0, 0.3, 0), 0)


## Платный перенос в точку карты: Рэй появляется на ближайшей точке дороги (высота — лучом по рельефу).
func _travel_point() -> void:
	if _point == null or _player == null or _traveling or PlayerState.helios < POINT_TRAVEL_COST:
		return
	var ground := _ground_at(_landing)
	if ground == Vector3.INF:
		return
	_do_travel(ground + Vector3(0, 0.3, 0), POINT_TRAVEL_COST)


func _ground_at(p: Vector2) -> Vector3:
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 400.0, p.y), Vector3(p.x, -200.0, p.y))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3.INF


func _do_travel(dest: Vector3, cost: int) -> void:
	_traveling = true
	if cost > 0:
		PlayerState.add_helios(-cost, false)
		Audio.play("coins")
	_fade.visible = true
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, FADE)
	await t.finished
	_set_open(false)
	_point = null
	_player.global_position = dest
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	if _camera and _camera.has_method("snap_to_target"):
		_camera.snap_to_target()
	get_tree().paused = false
	Audio.play("lantern", _player.global_position)
	await get_tree().create_timer(0.25).timeout
	var t2 := create_tween()
	t2.tween_property(_fade, "color:a", 0.0, FADE)
	await t2.finished
	_fade.visible = false
	_traveling = false


func _draw_map() -> void:
	var tex := map_texture.get_size()
	var tl := _to_view(Vector2.ZERO)
	_view.draw_texture_rect(map_texture, Rect2(tl, tex * _zoom), false)
	if fog_texture:
		_view.draw_texture_rect(fog_texture, Rect2(tl, tex * _zoom), false)
	_view.draw_rect(Rect2(tl, tex * _zoom), FRAME, false, 2.0)
	var font := _view.get_theme_default_font()
	# Подписи мест — мелко, с обводкой; при малом масштабе — только крупные.
	for p in places:
		var at := _to_view((p[1] as Vector2 - map_origin) / map_mpp)
		var w := font.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		_view.draw_string_outline(font, at + Vector2(-w / 2.0, -4), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, FRAME)
		_view.draw_string(font, at + Vector2(-w / 2.0, -4), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, PARCHMENT)
	# Фонари: ромб; выбранный — пульсирующее кольцо.
	for l in _lanterns():
		var at := _to_view(_to_map(l.global_position)).round()
		var lit: bool = l.get("lit")
		var c := LIT if lit else UNLIT
		var r := 5.0
		var diamond := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
		_view.draw_colored_polygon(diamond, FRAME)
		var inner := PackedVector2Array([at + Vector2(0, -r + 2), at + Vector2(r - 2, 0), at + Vector2(0, r - 2), at + Vector2(-r + 2, 0)])
		_view.draw_colored_polygon(inner, c)
		if lit:
			_view.draw_circle(at, 1.5, Color.WHITE)
		if l == _selected:
			_view.draw_arc(at, 8.0 + sin(_time * 5.0), 0, TAU, 20, Color.WHITE, 1.0)
	_draw_route()
	_draw_point()
	# Рэй — белая стрелка по направлению взгляда камеры (север вверху).
	if _player:
		var at := _to_view(_to_map(_player.global_position)).round()
		var pulse := 1.0 + 0.15 * sin(_time * 4.0)
		var arrow := PackedVector2Array([at + Vector2(0, -6) * pulse, at + Vector2(4, 4) * pulse, at + Vector2(0, 2) * pulse, at + Vector2(-4, 4) * pulse])
		_view.draw_colored_polygon(arrow, FRAME)
		_view.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.WHITE, 1.0)


## Маршрут навигатора по дорогам (пунктир) и метки: цель задания — золотой ромб, своя метка — синий.
func _draw_route() -> void:
	var pts := Waypoints.route(get_tree())
	if pts.size() > 1:
		var v := PackedVector2Array()
		for p in pts:
			v.append(_to_view((p - map_origin) / map_mpp).round())
		_view.draw_polyline(v, FRAME, 4.0)
		for i in range(1, v.size()):
			_dashed(v[i - 1], v[i], Color("ffd24a"))
	for t in Waypoints.targets(get_tree()):
		var at := _to_view(((t["at"] as Vector2) - map_origin) / map_mpp).round()
		var col := Color("ffd24a") if t["kind"] == "quest" else Color("6fb4ff")
		var r := 7.0
		_view.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r - 1), at + Vector2(r + 1, 0), at + Vector2(0, r + 1), at + Vector2(-r - 1, 0)]), FRAME)
		_view.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r + 1), at + Vector2(r - 1, 0), at + Vector2(0, r - 1), at + Vector2(-r + 1, 0)]), col)
		_view.draw_arc(at, 10.0 + sin(_time * 5.0), 0, TAU, 20, col, 1.0)


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(len, 0.001)
	var d := 0.0
	while d < len:
		_view.draw_line(a + dir * d, a + dir * minf(d + 5.0, len), col, 2.0)
		d += 9.0


func _refresh_nav() -> void:
	var txt := ""
	var t := Waypoints.main_target(get_tree())
	if not t.is_empty():
		txt = "%s — %d м" % [t["label"], int(Waypoints.length_of(Waypoints.route(get_tree())))]
	if _nav and _nav.text != txt:
		_nav.text = txt


## Выбранная точка платного переноса (белый ромб) и место на дороге, где Рэй появится (линия к нему).
func _draw_point() -> void:
	if _point == null:
		return
	var at := _to_view(((_point as Vector2) - map_origin) / map_mpp).round()
	var to := _to_view((_landing - map_origin) / map_mpp).round()
	_view.draw_line(at, to, FRAME, 3.0)
	_view.draw_line(at, to, Color.WHITE, 1.0)
	for c in [[7.0, FRAME], [5.0, Color("e8fffb")]]:
		var r: float = c[0]
		_view.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), c[1])
	_view.draw_circle(to, 3.0, FRAME)
	_view.draw_circle(to, 2.0, Color("e8c870"))
