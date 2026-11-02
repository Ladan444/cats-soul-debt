class_name SettingsMenu
extends Control
## Экран настроек (UI_SPEC, раздел 5): лист рваного пергамента, вкладки-закладки,
## строки «◀ значение ▶» и ползунки-ремешки. Изменения применяются сразу и сохраняются при закрытии.
## Общий для главного меню и паузы. Q/E или LB/RB — вкладки, Esc/B — назад.

signal closed

const PAPER := preload("res://assets/ui/panel_torn.png")
const INK := Color("2a1e18")
const PANEL_SIZE := Vector2(340, 250)
## Отступ содержимого от края панели: рамка новой панели толщиной 14, плюс воздух.
const PAD := 22
const CONTENT_W := 340 - PAD * 2 - 8   # справа запас под значение ползунка («100%»)
## Русские подписи клавиш вместо английских названий движка.
const KEY_NAMES := {"Up": "↑", "Down": "↓", "Left": "←", "Right": "→", "Space": "Пробел",
	"Escape": "Esc", "Shift": "Shift", "Tab": "Tab"}
const TABS := ["Изображение", "Звук", "Управление", "Игра"]
const LOSS_TEXT := ["Потеря 50% гелиосов спуска при смерти.", "Потеря 75% гелиосов спуска при смерти.", "Потеря 90% гелиосов спуска при смерти."]

## Подписи действий для вкладки «Управление».
const ACTION_NAMES := {
	"move_up": "Вверх", "move_down": "Вниз", "move_left": "Влево", "move_right": "Вправо",
	"attack": "Атака", "dash": "Рывок", "run": "Бег", "interact": "Действие",
	"skill_1": "Скилл 1", "skill_2": "Скилл 2", "skill_3": "Скилл 3", "skill_4": "Скилл 4",
	"item_1": "Предмет 1", "item_2": "Предмет 2", "item_3": "Предмет 3", "item_4": "Предмет 4",
	"inventory": "Книга: Рэй", "journal": "Карта", "pause": "Пауза",
	"ui_tab_prev": "Закладка ←", "ui_tab_next": "Закладка →",
}
const PAD_BUTTONS := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "View", 6: "Start", 7: "L3", 8: "R3",
	9: "LB", 10: "RB", 11: "↑", 12: "↓", 13: "←", 14: "→"}
const PAD_AXES := {0: "Стик ←→", 1: "Стик ↑↓", 4: "LT", 5: "RT"}

var _panel: NinePatchRect
var _tab_buttons: Array[Button] = []
var _content: VBoxContainer
var _bottom: HBoxContainer
var _tab: int = 0
var _difficulty_hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_layout)
	_layout()
	visible = false


func open() -> void:
	visible = true
	_show_tab(_tab)


func close() -> void:
	Settings.save_settings()
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_tab_prev"):
		_show_tab(wrapi(_tab - 1, 0, TABS.size()))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_tab_next"):
		_show_tab(wrapi(_tab + 1, 0, TABS.size()))
		get_viewport().set_input_as_handled()


func _build() -> void:
	_panel = NinePatchRect.new()
	_panel.texture = PAPER
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		_panel.set(m, 14)
	_panel.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_panel.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	add_child(_panel)

	var title := Label.new()
	title.name = "Title"
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 16)
	title.size = Vector2(PANEL_SIZE.x, 16)
	_panel.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.position = Vector2(PAD, 40)
	tabs.add_theme_constant_override("separation", 2)
	_panel.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE  # вкладки — мышью и Q/E, LB/RB
		_style_tab(b)
		b.pressed.connect(_show_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)

	_content = VBoxContainer.new()
	_content.position = Vector2(PAD, 62)
	_content.size = Vector2(CONTENT_W, 130)
	_content.add_theme_constant_override("separation", 3)
	_panel.add_child(_content)

	_bottom = HBoxContainer.new()
	_bottom.position = Vector2(PAD, PANEL_SIZE.y - 42)
	_bottom.size = Vector2(CONTENT_W, 12)
	_bottom.add_theme_constant_override("separation", 24)
	_panel.add_child(_bottom)
	var defaults := ClawButton.new("По умолчанию", true)
	defaults.pressed.connect(func():
		Settings.reset_to_defaults()
		_show_tab(_tab))
	_bottom.add_child(defaults)
	var back := ClawButton.new("Назад", true)
	back.pressed.connect(close)
	_bottom.add_child(back)

	var close_btn := CloseButton.new()
	close_btn.position = Vector2(PANEL_SIZE.x - 32, 12)
	close_btn.pressed.connect(close)
	_panel.add_child(close_btn)

	# Подсказка картинками клавиш — меняется вместе с устройством (клавиатура / геймпад).
	var hint := HBoxContainer.new()
	hint.position = Vector2(PAD, PANEL_SIZE.y - 28)
	hint.add_theme_constant_override("separation", 3)
	_panel.add_child(hint)
	hint.add_child(KeyGlyph.new(&"ui_tab_prev"))
	hint.add_child(KeyGlyph.new(&"ui_tab_next"))
	hint.add_child(_ink_label("вкладки", Color("8a7350")))
	var gap := Control.new()
	gap.custom_minimum_size.x = 10
	hint.add_child(gap)
	hint.add_child(KeyGlyph.new(&"ui_cancel"))
	hint.add_child(_ink_label("назад", Color("8a7350")))


func _layout() -> void:
	_panel.size = PANEL_SIZE
	_panel.position = ((size - PANEL_SIZE) / 2.0).floor()


func _style_tab(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("5c3a2a")
	normal.border_color = Color("2e1d14")
	normal.set_border_width_all(1)
	normal.set_content_margin_all(3)
	var active := normal.duplicate()
	active.bg_color = Color("4e6253")
	var hover := normal.duplicate()
	hover.bg_color = Color("76503a")
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", active)
	b.add_theme_stylebox_override("hover_pressed", active)
	b.add_theme_color_override("font_color", Color("e6d6b0"))
	b.add_theme_color_override("font_pressed_color", Color("e8c870"))
	b.add_theme_color_override("font_hover_pressed_color", Color("e8c870"))


func _show_tab(i: int) -> void:
	_tab = i
	_tab_buttons[i].button_pressed = true
	for child in _content.get_children():
		child.queue_free()
	_difficulty_hint = null
	match i:
		0: _build_video()
		1: _build_audio()
		2: _build_controls()
		3: _build_game()
	# Фокус на первую строку (после того как новые строки войдут в дерево).
	_focus_first.call_deferred()


func _focus_first() -> void:
	for child in _content.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE and not child.is_queued_for_deletion():
			child.grab_focus()
			return
	_bottom.get_child(1).grab_focus()


func _add_row(row: SettingRow, key: String) -> SettingRow:
	_content.add_child(row)
	row.value_changed.connect(func(v): Settings.set_value(key, v))
	return row


func _build_video() -> void:
	var res := PackedStringArray()
	for r in Settings.RESOLUTIONS:
		res.append("%d×%d" % [r.x, r.y])
	_add_row(SettingRow.make_options("Разрешение", res, Settings.get_value("resolution")), "resolution")
	_add_row(SettingRow.make_options("Режим окна", PackedStringArray(Settings.WINDOW_MODES), Settings.get_value("window_mode")), "window_mode")
	var vsync := SettingRow.make_options("Верт. синхронизация", PackedStringArray(["Выкл", "Вкл"]), 1 if Settings.get_value("vsync") else 0)
	_content.add_child(vsync)
	vsync.value_changed.connect(func(v): Settings.set_value("vsync", v == 1))
	_add_row(SettingRow.make_options("Ограничение кадров", PackedStringArray(Settings.FPS_LIMIT_NAMES), int(Settings.get_value("max_fps"))), "max_fps")
	var scales := PackedStringArray(["×2", "×3", "×4"])
	var scale_row := SettingRow.make_options("Масштаб интерфейса", scales, int(Settings.get_value("ui_scale")) - 2)
	_content.add_child(scale_row)
	scale_row.value_changed.connect(func(v): Settings.set_value("ui_scale", int(v) + 2))
	_add_row(SettingRow.make_slider("Яркость", 0.5, 1.5, Settings.get_value("brightness")), "brightness")


func _build_audio() -> void:
	for pair in [["Общая громкость", "master_volume"], ["Музыка", "music_volume"], ["Эффекты", "sfx_volume"],
			["Окружение", "ambient_volume"], ["Голоса", "voice_volume"]]:
		_add_row(SettingRow.make_slider(pair[0], 0.0, 1.0, Settings.get_value(pair[1])), pair[1])
	_note("Звука в игре пока нет — громкость сохранится на будущее.")


func _build_controls() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(CONTENT_W, 126)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL  # стрелки/стик прокручивают таблицу
	scroll.gui_input.connect(func(e: InputEvent):
		var bar := scroll.get_v_scroll_bar()
		if e.is_action_pressed("ui_down", true) and scroll.scroll_vertical < bar.max_value - bar.page:
			scroll.scroll_vertical += 9
			scroll.accept_event()
		elif e.is_action_pressed("ui_up", true) and scroll.scroll_vertical > 0:
			scroll.scroll_vertical -= 9
			scroll.accept_event())
	_content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 0)
	scroll.add_child(grid)
	for header in ["Действие", "Клавиатура", "Геймпад"]:
		grid.add_child(_ink_label(header, Color("4e6253")))
	for action in ACTION_NAMES:
		var keys := PackedStringArray()
		var pads := PackedStringArray()
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				var key_name := OS.get_keycode_string(e.physical_keycode)
				keys.append(KEY_NAMES.get(key_name, key_name))
			elif e is InputEventMouseButton:
				keys.append({1: "ЛКМ", 2: "ПКМ", 3: "СКМ"}.get(e.button_index, "Мышь"))
			elif e is InputEventJoypadButton:
				pads.append(PAD_BUTTONS.get(e.button_index, "Кн %d" % e.button_index))
			elif e is InputEventJoypadMotion:
				pads.append(PAD_AXES.get(e.axis, "Ось %d" % e.axis))
		grid.add_child(_ink_label(ACTION_NAMES[action]))
		grid.add_child(_ink_label(", ".join(keys)))
		grid.add_child(_ink_label(", ".join(pads)))
	_note("Переназначение клавиш появится позже.")


func _build_game() -> void:
	var diff := _add_row(SettingRow.make_options("Сложность", PackedStringArray(Settings.DIFFICULTIES), Settings.get_value("difficulty")), "difficulty")
	_difficulty_hint = _note(LOSS_TEXT[diff.index])
	diff.value_changed.connect(func(v): _difficulty_hint.text = LOSS_TEXT[v])
	_add_row(SettingRow.make_slider("Тряска камеры", 0.0, 1.0, Settings.get_value("camera_shake")), "camera_shake")
	_add_row(SettingRow.make_slider("Сила помех и глитча", 0.0, 1.0, Settings.get_value("glitch_strength")), "glitch_strength")
	_add_row(SettingRow.make_slider("Скорость текста", 0.5, 2.0, Settings.get_value("text_speed"), 0.1, "multiplier"), "text_speed")
	_add_row(SettingRow.make_options("Сенсорное управление", PackedStringArray(Settings.TOUCH_MODES), Settings.get_value("touch_controls")), "touch_controls")
	var hints := SettingRow.make_options("Подсказки обучения", PackedStringArray(["Выкл", "Вкл"]), 1 if Settings.get_value("tutorial_hints") else 0)
	_content.add_child(hints)
	hints.value_changed.connect(func(v): Settings.set_value("tutorial_hints", v == 1))
	_content.add_child(SettingRow.make_options("Язык", PackedStringArray(["Русский"]), 0))


func _note(text: String) -> Label:
	var l := _ink_label(text, Color("8a7350"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = CONTENT_W
	_content.add_child(l)
	return l


func _ink_label(text: String, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 0)
	return l
