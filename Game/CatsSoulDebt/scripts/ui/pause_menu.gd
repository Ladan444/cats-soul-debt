extends CanvasLayer
## Меню паузы (UI_SPEC, раздел 5): Esc / Start. Мир за меню размыт и затемнён.
## Выход в главное меню сохраняет игру (один слот, SaveGame). Закрытие окна — тоже.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const WOOD := preload("res://assets/ui/panel_wood.png")
const BLUR := preload("res://assets/ui/pause_blur.gdshader")

var _blur: ColorRect
var _panel: NinePatchRect
var _menu: VBoxContainer
var _settings: SettingsMenu
var _map_item: ClawButton


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_blur = ColorRect.new()
	_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = BLUR
	_blur.material = mat
	add_child(_blur)

	var scaler := UIScaler.new()
	add_child(scaler)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scaler.add_child(root)

	_panel = NinePatchRect.new()
	_panel.texture = WOOD
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		_panel.set(m, 12)
	_panel.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_panel.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_panel.size = Vector2(170, 139)   # 6 пунктов (с «Картой»)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = -_panel.size / 2.0
	root.add_child(_panel)

	var title := Label.new()
	title.text = "Пауза"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("e8c870"))
	title.add_theme_color_override("font_outline_color", Color("2e1d14"))
	title.add_theme_constant_override("outline_size", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 10)
	title.size = Vector2(_panel.size.x, 16)
	_panel.add_child(title)

	_menu = VBoxContainer.new()
	_menu.position = Vector2(16, 34)
	_menu.add_theme_constant_override("separation", 3)
	_panel.add_child(_menu)
	var close_btn := CloseButton.new()
	close_btn.position = Vector2(_panel.size.x - 18, 4)
	close_btn.pressed.connect(resume)
	_panel.add_child(close_btn)

	_item("Продолжить", resume)
	_item("Персонаж", func(): _open_book(false))
	_item("Журнал", func(): _open_book(true))
	_item("Настройки", func():
		_panel.visible = false
		_settings.open())
	# Карта (как M): в мире — карта мира с перемещениями, в остальных местах — карта места; с геймпада — отсюда.
	_map_item = _item("Карта", func():
		var book := get_tree().current_scene.get_node_or_null("Book") as Book
		if book:
			resume()
			book.open_map())
	# Фоторежим: с клавиатуры — F2, отсюда — с геймпада.
	_item("Фоторежим", func():
		resume()
		PhotoMode.open())
	_item("В главное меню", _to_main_menu)

	_settings = SettingsMenu.new()
	_settings.closed.connect(func():
		_panel.visible = true
		_blur.visible = true
		_menu.get_child(3).grab_focus())
	# Предпросмотр камеры: пока правят камеру, пауза-блюр убирается, чтобы видеть кадр.
	_settings.preview_changed.connect(func(on: bool): _blur.visible = not on)
	root.add_child(_settings)

	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if not visible:
			if get_tree().paused:
				return  # игру остановило другое меню (книга) — Esc закроет его
			if get_tree().get_first_node_in_group("scene_transition"):
				return  # идёт смена сцены — затемнение выше меню
			open()
		elif not _settings.visible:
			resume()
		get_viewport().set_input_as_handled()
	elif visible and not _settings.visible and event.is_action_pressed("ui_cancel"):
		resume()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()


func open() -> void:
	if get_tree().get_first_node_in_group("scene_transition"):
		return
	visible = true
	_panel.visible = true
	_map_item.visible = get_tree().current_scene.get_node_or_null("Book") != null
	get_tree().paused = true
	_menu.get_child(0).grab_focus()


func resume() -> void:
	visible = false
	_settings.visible = false
	get_tree().paused = false


## Открывает книгу сцены вместо паузы (journal — на закладках журнала); игра остаётся на паузе.
func _open_book(journal: bool) -> void:
	var book := get_tree().current_scene.get_node_or_null("Book") as Book
	# Посреди реплики книга не открывается (_blocked): не прячем паузу, иначе игра оставалась на паузе без окон.
	if book and book.can_open():
		visible = false
		book.open_half(journal)


func _to_main_menu() -> void:
	_save()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)


func _save() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := scene.get_node_or_null("Player") as Node3D
	if player:
		SaveGame.save(scene.scene_file_path, player.global_position)


func _item(text: String, action: Callable) -> ClawButton:
	var b := ClawButton.new(text)
	b.custom_minimum_size.x = 140
	b.pressed.connect(action)
	_menu.add_child(b)
	return b
