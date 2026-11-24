extends CanvasLayer
## Фоторежим (C03–C05, C09, C11, C12): F2 в игре.
## Пауза, скрытый HUD, свободная камера вокруг Рэя, линза (DOF и FOV), сетка третей,
## форматы кадра, цветокоры, покадровый шаг и галерея снимков в user://screenshots.
##
## Камера — отдельный Camera3D в текущей сцене; игра на паузе, поэтому Рэй не двигается.
## Интерфейс — на своём CanvasLayer 15, выше HUD (1) и эффектов экрана (0), но ниже меню паузы (20).

const PAPER := preload("res://assets/ui/panel_torn.png")
const INK := Color("2a1e18")
const UserFiles := preload("res://scripts/core/user_files.gd")

const PANEL_W := 226.0
const PANEL_H := 340.0
const CONTENT_W := 198.0
const FORMATS := ["16:9", "4:3", "1:1", "9:16"]
const ASPECTS := [16.0 / 9.0, 4.0 / 3.0, 1.0, 9.0 / 16.0]

## Сетка третей и рамка кадра: рисуются только в интерфейсе, на снимок не попадают.
class FrameGrid:
	extends Control
	var grid: bool = false
	var border: bool = true

	func _draw() -> void:
		if border:
			var ink := Color(0.95, 0.9, 0.75, 0.45)
			draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), ink, false, 1.0)
		if not grid:
			return
		var line := Color(1, 1, 1, 0.28)
		for i in [1, 2]:
			var x := roundf(size.x * i / 3.0)
			var y := roundf(size.y * i / 3.0)
			draw_line(Vector2(x, 0), Vector2(x, size.y), line, 1.0)
			draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)

var _open: bool = false
var _saving: bool = false
var _stepping: bool = false

var _player: Node3D
var _game_camera: Camera3D
var _cam: Camera3D
var _attrs: CameraAttributesPractical
var _hidden_hud: CanvasLayer

## Камера вокруг точки интереса.
var _focus: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 38.0
var _distance: float = 12.0
var _fov: float = 30.0
var _dof: float = 0.6
var _dragging: bool = false

var _format: int = 0
var _grid: bool = true
var _hide_player: bool = false
var _x2: bool = false
var _grade: int = 0
var _selected_shot: String = ""

var _ui: Control
var _panel: NinePatchRect
var _rows: VBoxContainer
var _gallery: Control
var _gallery_grid: GridContainer
var _frame: FrameGrid
var _bar_left: ColorRect
var _bar_right: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _toast: Label
var _toast_left: float = 0.0


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_ui.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		if event.is_action_pressed("photo_mode"):
			open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("photo_mode") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("photo_step"):
		step_frame()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_distance = clampf(_distance - 0.8, 3.0, 40.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = clampf(_distance + 0.8, 3.0, 40.0)
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch + event.relative.y * 0.22, 5.0, 85.0)


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.visible = false
	if _open and _cam != null:
		_place_camera()


func open() -> void:
	if _open or DisplayServer.get_name() == "headless":
		return
	if get_tree().paused:
		return   # уже открыта книга, карта или пауза
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return   # главное меню: смотреть нечего
	_player = player
	_game_camera = get_viewport().get_camera_3d()
	_focus = player.global_position + Vector3(0, 1.0, 0)
	_yaw = 0.0
	_pitch = 38.0
	_distance = 12.0
	_dof = clampf(float(Settings.get_value("miniature")), 0.0, 1.0)
	_grade = 0
	ScreenFX.set_grade(0)
	_make_camera()
	_set_game_hud(false)
	_ui.visible = true
	_show_gallery(false)
	_layout_frame.call_deferred()
	_open = true
	get_tree().paused = true
	_toast.visible = false
	_focus_button.call_deferred()


func close() -> void:
	if not _open:
		return
	_open = false
	_ui.visible = false
	_dragging = false
	get_tree().paused = false
	if is_instance_valid(_game_camera):
		_game_camera.current = true
	if is_instance_valid(_player):
		_set_player_visible(true)
	if is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	_attrs = null
	ScreenFX.set_grade(0)
	_set_game_hud(true)


func is_open() -> bool:
	return _open


## Один шаг мира (C11): снимаем паузу ровно на кадр — ловим удар или прыжок.
func step_frame() -> void:
	if not _open or _stepping:
		return
	_stepping = true
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().process_frame
	if _open:
		get_tree().paused = true
	_stepping = false


func _make_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "PhotoCamera"
	_cam.fov = _fov
	_cam.near = 0.05
	_cam.far = 300.0
	_attrs = CameraAttributesPractical.new()
	_cam.attributes = _attrs
	var host := get_tree().current_scene
	if host == null:
		host = self
	host.add_child(_cam)
	_place_camera()
	_cam.current = true


func _place_camera() -> void:
	var cp := cos(deg_to_rad(_pitch))
	var sp := sin(deg_to_rad(_pitch))
	var dir := Vector3(sin(_yaw) * cp, sp, cos(_yaw) * cp)
	_cam.global_position = _focus + dir * _distance
	_cam.look_at(_focus, Vector3.UP)
	_cam.fov = _fov
	_apply_photo_dof()


## Линза (C04): резкая полоса вокруг точки фокуса, тем шире размытие, чем больше «диафрагма».
func _apply_photo_dof() -> void:
	if _attrs == null:
		return
	var s := clampf(_dof, 0.0, 1.0)
	_attrs.dof_blur_near_enabled = s > 0.01
	_attrs.dof_blur_far_enabled = s > 0.01
	if s <= 0.01:
		_attrs.dof_blur_amount = 0.0
		return
	var band := lerpf(9.0, 1.6, s)
	_attrs.dof_blur_near_distance = maxf(_distance - band, 0.4)
	_attrs.dof_blur_near_transition = band * 0.9
	_attrs.dof_blur_far_distance = _distance + band
	_attrs.dof_blur_far_transition = band * 1.2
	_attrs.dof_blur_amount = 0.03 + 0.07 * s


func _set_player_visible(on: bool) -> void:
	if not is_instance_valid(_player):
		return
	var sprite := _player.get_node_or_null("Sprite3D") as Sprite3D
	if sprite == null:
		for child in _player.get_children():
			if child is Sprite3D:
				sprite = child
				break
	if sprite:
		sprite.visible = on


func _set_game_hud(on: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var hud := scene.get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		for child in scene.get_children():
			if child is CanvasLayer and child.name == "HUD":
				hud = child
				break
	if hud == null:
		return
	if not on:
		_hidden_hud = hud
		hud.visible = false
	elif _hidden_hud != null and is_instance_valid(_hidden_hud):
		_hidden_hud.visible = true
		_hidden_hud = null


## --- интерфейс ---------------------------------------------------------------

func _build() -> void:
	_ui = Control.new()
	_ui.name = "PhotoUI"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)

	var scaler := UIScaler.new()
	scaler.min_canvas = Vector2(420, 300)
	_ui.add_child(scaler)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scaler.add_child(canvas)

	# Поля кадра: рисуются поверх 3D, но на снимок не попадают.
	_bar_left = _bar(canvas)
	_bar_right = _bar(canvas)
	_bar_top = _bar(canvas)
	_bar_bottom = _bar(canvas)
	_frame = FrameGrid.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_frame)
	canvas.resized.connect(_layout_frame)

	_panel = NinePatchRect.new()
	_panel.name = "PhotoPanel"
	_panel.texture = PAPER
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		_panel.set(m, 14)
	_panel.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_panel.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.position = Vector2(640 - PANEL_W - 10, 10)
	canvas.add_child(_panel)

	var title := Label.new()
	title.text = "Фоторежим"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 14)
	title.size = Vector2(PANEL_W, 16)
	_panel.add_child(title)

	var hint := _ink("ЛКМ — поворот · колесо — зум", Color("8a7350"))
	hint.position = Vector2(12, 33)
	_panel.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 46)
	scroll.custom_minimum_size = Vector2(CONTENT_W, 214)
	scroll.size = Vector2(CONTENT_W, 214)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 3)
	scroll.add_child(_rows)

	var shots := HBoxContainer.new()
	shots.position = Vector2(12, 266)
	shots.add_theme_constant_override("separation", 6)
	_panel.add_child(shots)
	var shoot := ClawButton.new("Снимок", true)
	shoot.pressed.connect(take_shot)
	shots.add_child(shoot)
	var step_btn := ClawButton.new("Кадр +1", true)
	step_btn.pressed.connect(step_frame)
	shots.add_child(step_btn)

	var more := HBoxContainer.new()
	more.position = Vector2(12, 288)
	more.add_theme_constant_override("separation", 6)
	_panel.add_child(more)
	var gallery := ClawButton.new("Галерея", true)
	gallery.pressed.connect(func(): _show_gallery(not _gallery.visible))
	more.add_child(gallery)
	var close_btn := ClawButton.new("Закрыть", true)
	close_btn.pressed.connect(close)
	more.add_child(close_btn)

	var keys := _ink("F2 — выход · F3 — кадр", Color("8a7350"))
	keys.position = Vector2(12, 312)
	_panel.add_child(keys)

	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(0, 330)
	_toast.size = Vector2(640, 12)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Color("e8d8b0"))
	_toast.add_theme_color_override("font_outline_color", Color("1a1208"))
	_toast.add_theme_constant_override("outline_size", 3)
	_toast.visible = false
	canvas.add_child(_toast)

	_gallery = _make_gallery()
	canvas.add_child(_gallery)

	_build_rows()


func _bar(parent: Control) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0.03, 0.02, 0.02)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	parent.add_child(bar)
	return bar


func _make_gallery() -> Control:
	var box := Control.new()
	box.name = "Gallery"
	box.position = Vector2(12, 46)
	box.size = Vector2(CONTENT_W, 240)
	box.visible = false

	var paper := NinePatchRect.new()
	paper.texture = PAPER
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		paper.set(m, 14)
	paper.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	paper.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	paper.size = Vector2(CONTENT_W + 8, 246)
	paper.position = Vector2(-8, -6)
	box.add_child(paper)

	_gallery_grid = GridContainer.new()
	_gallery_grid.columns = 2
	_gallery_grid.position = Vector2(0, 2)
	_gallery_grid.add_theme_constant_override("h_separation", 6)
	_gallery_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_gallery_grid)

	var buttons := HBoxContainer.new()
	buttons.position = Vector2(0, 214)
	buttons.add_theme_constant_override("separation", 4)
	box.add_child(buttons)
	var folder := ClawButton.new("Папка", true)
	folder.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path(_shot_dir())))
	buttons.add_child(folder)
	var remove := ClawButton.new("Удалить", true)
	remove.pressed.connect(_delete_selected_shot)
	buttons.add_child(remove)
	var back := ClawButton.new("Назад", true)
	back.pressed.connect(func(): _show_gallery(false))
	buttons.add_child(back)
	return box


## Строки настроек: линза (C04), эффекты (C06–C08), кадр (C05, C09).
func _build_rows() -> void:
	_slider("Диафрагма", 0.0, 1.0, _dof, 0.05, "percent", func(v): _dof = v)
	_slider("Фокусное", 15.0, 90.0, _fov, 1.0, "degrees", func(v): _fov = v)
	_slider("Размытие", 0.0, 1.0, float(Settings.get_value("fx_tilt")), 0.05, "percent",
		func(v): Settings.set_value("fx_tilt", v))
	_slider("Виньетка", 0.0, 1.0, float(Settings.get_value("fx_vignette")), 0.05, "percent",
		func(v): Settings.set_value("fx_vignette", v))
	_slider("Зерно плёнки", 0.0, 1.0, float(Settings.get_value("fx_grain")), 0.05, "percent",
		func(v): Settings.set_value("fx_grain", v))
	_slider("Хроматика", 0.0, 1.0, float(Settings.get_value("fx_chroma")), 0.05, "percent",
		func(v): Settings.set_value("fx_chroma", v))
	var grades := PackedStringArray()
	for i in ScreenFX.grade_count():
		grades.append(ScreenFX.grade_name(i))
	_choice("Цвет", grades, _grade, func(v):
		_grade = int(v)
		ScreenFX.set_grade(_grade))
	_choice("Формат кадра", PackedStringArray(FORMATS), _format, func(v):
		_format = int(v)
		_layout_frame())
	_toggle("Сетка третей", _grid, func(on):
		_grid = on
		_frame.grid = on
		_frame.queue_redraw())
	_toggle("Рэй в кадре", not _hide_player, func(on):
		_hide_player = not on
		_set_player_visible(on))
	_toggle("Снимок ×2", _x2, func(on): _x2 = on)


func _slider(text: String, from: float, to: float, value: float, step: float, fmt: String, setter: Callable) -> SettingRow:
	var row := SettingRow.make_slider(text, from, to, value, step, fmt)
	_rows.add_child(row)
	row.value_changed.connect(func(v): setter.call(v))
	return row


func _choice(text: String, options: PackedStringArray, current: int, setter: Callable) -> SettingRow:
	var row := SettingRow.make_options(text, options, current)
	_rows.add_child(row)
	row.value_changed.connect(func(v): setter.call(v))
	return row


func _toggle(text: String, on: bool, setter: Callable) -> SettingRow:
	return _choice(text, PackedStringArray(["Выкл", "Вкл"]), 1 if on else 0, func(v): setter.call(int(v) == 1))


func _ink(text: String, color := INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)
	return label


func _focus_button() -> void:
	for row in _rows.get_children():
		if row is Control and row.focus_mode != Control.FOCUS_NONE:
			row.grab_focus()
			return


## Поля кадра и сетка под выбранный формат (C05). В UI-пикселях холста 640×360.
func _layout_frame() -> void:
	if _frame == null:
		return
	var canvas := _frame.size
	if canvas.x <= 0.0:
		return
	if _panel:
		_panel.position = Vector2(canvas.x - PANEL_W - 10, 10)
	if _toast:
		_toast.position = Vector2(0, canvas.y - 24)
		_toast.size = Vector2(canvas.x, 12)
	var aspect: float = ASPECTS[clampi(_format, 0, ASPECTS.size() - 1)]
	var view := canvas.x / maxf(canvas.y, 1.0)
	var side := 0.0
	var top := 0.0
	if aspect < view:
		side = (canvas.x - canvas.y * aspect) * 0.5
	else:
		top = (canvas.y - canvas.x / aspect) * 0.5
	_bar_left.position = Vector2.ZERO
	_bar_left.size = Vector2(side, canvas.y)
	_bar_right.position = Vector2(canvas.x - side, 0)
	_bar_right.size = Vector2(side, canvas.y)
	_bar_left.visible = side > 0.5
	_bar_right.visible = side > 0.5
	_bar_top.position = Vector2.ZERO
	_bar_top.size = Vector2(canvas.x, top)
	_bar_bottom.position = Vector2(0, canvas.y - top)
	_bar_bottom.size = Vector2(canvas.x, top)
	_bar_top.visible = top > 0.5
	_bar_bottom.visible = top > 0.5
	_frame.grid = _grid
	_frame.queue_redraw()


## --- снимок и галерея --------------------------------------------------------

func take_shot() -> void:
	if not _open or _saving or _cam == null:
		return
	_saving = true
	_ui.visible = false
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if _open:
		_ui.visible = true
	if img == null or img.is_empty():
		_saving = false
		_toast_text("Не удалось снять кадр")
		return
	img = _crop(img, ASPECTS[clampi(_format, 0, ASPECTS.size() - 1)])
	if _x2:
		img.resize(maxi(int(img.get_width() * 2), 1), maxi(int(img.get_height() * 2), 1), Image.INTERPOLATE_LANCZOS)
	var dir := _shot_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s%s_%d.png" % [dir, "shot_".to_lower() + stamp, Time.get_ticks_msec() % 1000]
	var err := img.save_png(path)
	_saving = false
	if err == OK:
		_toast_text("Снимок: " + path.get_file())
		_refresh_gallery()
	else:
		_toast_text("Не удалось сохранить: %s" % error_string(err))


func _crop(img: Image, aspect: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return img
	var current := float(w) / float(h)
	if absf(current - aspect) < 0.002:
		return img
	if aspect < current:
		var new_w := maxi(int(round(h * aspect)), 1)
		return img.get_region(Rect2i((w - new_w) / 2, 0, new_w, h))
	var new_h := maxi(int(round(w / aspect)), 1)
	return img.get_region(Rect2i(0, (h - new_h) / 2, w, new_h))


func _shot_dir() -> String:
	return UserFiles.path("screenshots/")


func _shots() -> PackedStringArray:
	var dir := _shot_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var access := DirAccess.open(dir)
	var names := PackedStringArray()
	if access == null:
		return names
	for file_name in access.get_files():
		if file_name.to_lower().ends_with(".png"):
			names.append(file_name)
	names.sort()
	names.reverse()
	return names


func _refresh_gallery() -> void:
	if _gallery_grid == null:
		return
	for child in _gallery_grid.get_children():
		child.queue_free()
	var names := _shots()
	if names.is_empty():
		var empty := _ink("Пока пусто — сделай снимок", Color("8a7350"))
		_gallery_grid.add_child(empty)
		return
	for i in mini(names.size(), 6):
		var path := _shot_dir() + names[i]
		var image := Image.load_from_file(path)
		var button := Button.new()
		button.custom_minimum_size = Vector2(94, 54)
		button.tooltip_text = names[i]
		button.mouse_entered.connect(func(): _selected_shot = names[i])
		button.pressed.connect(func():
			_selected_shot = names[i]
			OS.shell_open(ProjectSettings.globalize_path(path)))
		if image != null and not image.is_empty():
			image.resize(94, 54, Image.INTERPOLATE_BILINEAR)
			button.icon = ImageTexture.create_from_image(image)
			button.expand_icon = true
		else:
			button.text = "?"
		_gallery_grid.add_child(button)


func _show_gallery(on: bool) -> void:
	if _gallery == null:
		return
	_gallery.visible = on
	if on:
		_refresh_gallery()


func _delete_selected_shot() -> void:
	if _selected_shot == "":
		_toast_text("Выбери снимок наведением")
		return
	var dir := DirAccess.open(_shot_dir())
	if dir and dir.remove(_selected_shot) == OK:
		_toast_text("Удалён: " + _selected_shot)
		_selected_shot = ""
		_refresh_gallery()


func _toast_text(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast_left = 3.5
