extends Control
## HUD (UI_SPEC, раздел 2): HP, энергия души, 9 искр-отметок смерти, печать Рубежа,
## 4 скилла + 4 предмета, гелиосы, миникарта, название зоны. В хабе (таверна) хотбар прячется.
## Размеры — в UI-пикселях; родитель — UIScaler.

const PLANK := preload("res://assets/ui/plank.png")
const ICON_HEART := preload("res://assets/ui/icon_heart.png")
const ICON_SOUL := preload("res://assets/ui/icon_soul.png")
const ICON_HELIOS := preload("res://assets/ui/icon_helios.png")
const SPARK_FULL := preload("res://assets/ui/spark_full.png")
const SPARK_SPENT := preload("res://assets/ui/spark_spent.png")
const EMBLEM := preload("res://assets/ui/emblem.png")
const EMBLEM_SOCKET := preload("res://assets/ui/emblem_socket.png")

const SLOT := 24
const PLANK_BORDER := 5   ## толщина рамки доски (plank.png)
const GAP := 2
const GROUP_W := SLOT * 4 + GAP * 3
const CENTER_W := 32
const BOTTOM := 5

const ICON_BOOK := preload("res://assets/ui/sicon_book.png")
const ICON_MAP := preload("res://assets/ui/sicon_map.png")
const ICON_GEAR := preload("res://assets/ui/sicon_gear.png")
## Закладка «Карты» в книге (Book.SECTIONS).

## Необязательно: AtmosphereBlender — для названия зоны и режима хаба.
@export var atmosphere_path: NodePath

var _hotbar: Control
var _hp_bar: PixelBar
var _energy_bar: PixelBar
var _sparks: Array[TextureRect] = []
var _skill_slots: Array[HotbarSlot] = []
var _item_slots: Array[HotbarSlot] = []
var _helios_label: Label
var _helios_box: Control
var _delta_label: Label
var _zone_label: Label
var _atmosphere: AtmosphereBlender
var _zone: String = ""
var _hub: bool = false
var _menu_buttons: HBoxContainer
var _minimap: Minimap


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atmosphere = get_node_or_null(atmosphere_path) as AtmosphereBlender
	_build()
	resized.connect(_layout)
	_layout()

	PlayerState.hp_changed.connect(func(hp, max_hp): _hp_bar.set_ratio(hp / max_hp))
	PlayerState.energy_changed.connect(func(e, max_e): _energy_bar.set_ratio(e / max_e))
	PlayerState.energy_denied.connect(func(): _energy_bar.flash())
	PlayerState.deaths_changed.connect(_on_deaths_changed)
	PlayerState.helios_changed.connect(_on_helios_changed)
	PlayerState.skill_used.connect(func(i): _skill_slots[i].pulse())
	PlayerState.item_used.connect(func(i): _item_slots[i].pulse())
	PlayerState.items_changed.connect(_refresh_slots)
	InputGlyphs.device_changed.connect(func(_g): _refresh_slots())

	_hp_bar.set_ratio(PlayerState.hp / PlayerState.max_hp)
	_energy_bar.set_ratio(PlayerState.energy / PlayerState.max_energy)
	_on_deaths_changed(PlayerState.deaths)
	_helios_label.text = str(PlayerState.helios)
	_refresh_slots()


func _build() -> void:
	_hotbar = Control.new()
	_hotbar.name = "Hotbar"
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotbar)

	var plank := NinePatchRect.new()
	plank.name = "Plank"
	plank.texture = PLANK
	plank.patch_margin_left = PLANK_BORDER
	plank.patch_margin_right = PLANK_BORDER
	plank.patch_margin_top = PLANK_BORDER
	plank.patch_margin_bottom = PLANK_BORDER
	plank.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_hotbar.add_child(plank)

	_hp_bar = PixelBar.new()
	_hp_bar.name = "HPBar"
	_hotbar.add_child(_hp_bar)
	_energy_bar = PixelBar.new()
	_energy_bar.name = "EnergyBar"
	_energy_bar.fill_color = Color("8fd8d0")
	_energy_bar.shade_color = Color("3e7e86")
	_energy_bar.trail_color = Color("e8fffb")
	_hotbar.add_child(_energy_bar)
	_hotbar.add_child(_icon("HeartIcon", ICON_HEART))
	_hotbar.add_child(_icon("SoulIcon", ICON_SOUL))

	for i in PlayerState.MAX_DEATHS:
		var spark := _icon("Spark%d" % i, SPARK_FULL)
		spark.pivot_offset = Vector2(3.5, 3.5)
		_sparks.append(spark)
		_hotbar.add_child(spark)

	_hotbar.add_child(_icon("EmblemSocket", EMBLEM_SOCKET))
	_hotbar.add_child(_icon("Emblem", EMBLEM))

	for i in 4:
		var s := HotbarSlot.new()
		s.name = "Skill%d" % i
		s.pressed.connect(func(): if _can_act(): PlayerState.use_skill(i))
		_skill_slots.append(s)
		_hotbar.add_child(s)
	for i in 4:
		var s := HotbarSlot.new()
		s.name = "Item%d" % i
		s.pressed.connect(func(): if _can_act(): PlayerState.use_item(i))
		_item_slots.append(s)
		_hotbar.add_child(s)

	# Кнопки меню — левый верхний угол, видны и в хабе: книга, карта, пауза.
	_menu_buttons = HBoxContainer.new()
	_menu_buttons.name = "MenuButtons"
	_menu_buttons.position = Vector2(6, 6)
	_menu_buttons.add_theme_constant_override("separation", 6)
	_menu_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_buttons)
	_menu_button("BookButton", ICON_BOOK, &"inventory", "Книга", func(): _open_book(-1))
	_menu_button("MapButton", ICON_MAP, &"journal", "Карта", func():
		var book := get_tree().current_scene.get_node_or_null("Book") as Book
		if book and not get_tree().paused:
			book.open_map())
	_menu_button("MenuButton", ICON_GEAR, &"pause", "Меню", func():
		var pause := get_tree().current_scene.get_node_or_null("PauseMenu")
		if pause and not get_tree().paused:
			pause.open())

	# Гелиосы — правый верхний угол, видны и в хабе.
	_helios_box = HBoxContainer.new()
	_helios_box.name = "Helios"
	_helios_box.add_theme_constant_override("separation", 3)
	_helios_label = _label("0", 8)
	_helios_label.pivot_offset = Vector2(0, 4)
	_helios_box.add_child(_helios_label)
	var coin := _icon("Coin", ICON_HELIOS)
	_helios_box.add_child(coin)
	add_child(_helios_box)
	_delta_label = _label("", 8)
	_delta_label.modulate.a = 0.0
	add_child(_delta_label)

	# Миникарта — правый верхний угол, под гелиосами.
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	add_child(_minimap)

	_zone_label = _label("", 16)
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.modulate.a = 0.0
	add_child(_zone_label)

	var hints := TutorialHints.new()
	hints.name = "TutorialHints"
	add_child(hints)


func _layout() -> void:
	var w := size.x
	var h := size.y
	var cx := floorf(w / 2.0)
	var slot_y := h - BOTTOM - SLOT
	var skills_x := cx - CENTER_W / 2.0 - 5 - GROUP_W
	var items_x := cx + CENTER_W / 2.0 + 5
	var bar_h := 9
	var bar_y := slot_y - 3 - bar_h

	var plank: NinePatchRect = _hotbar.get_node("Plank")
	plank.position = Vector2(skills_x - 5 - PLANK_BORDER + 2, bar_y - 4 - PLANK_BORDER + 2)
	plank.size = Vector2(GROUP_W * 2 + CENTER_W + 10 + 10 + 2 * (PLANK_BORDER - 2), h - plank.position.y)

	_hp_bar.position = Vector2(skills_x + 13, bar_y)
	_hp_bar.size = Vector2(GROUP_W - 13, bar_h)
	_hotbar.get_node("HeartIcon").position = Vector2(skills_x, bar_y)
	_energy_bar.position = Vector2(items_x, bar_y)
	_energy_bar.size = Vector2(GROUP_W - 12, bar_h)
	_hotbar.get_node("SoulIcon").position = Vector2(items_x + GROUP_W - 10, bar_y)

	var sparks_w := 7 * _sparks.size() + 3 * (_sparks.size() - 1)
	for i in _sparks.size():
		_sparks[i].position = Vector2(cx - floorf(sparks_w / 2.0) + i * 10, bar_y - 12)

	# Эмблема-печать по центру, чуть выше ряда ячеек; рамка уже нарисована в самой картинке.
	_hotbar.get_node("EmblemSocket").visible = false
	var emb: TextureRect = _hotbar.get_node("Emblem")
	emb.position = Vector2(cx - emb.texture.get_width() / 2.0, slot_y + SLOT / 2.0 - emb.texture.get_height() / 2.0 - 2)

	for i in 4:
		_skill_slots[i].position = Vector2(skills_x + i * (SLOT + GAP), slot_y)
		_item_slots[i].position = Vector2(items_x + i * (SLOT + GAP), slot_y)

	_helios_box.reset_size()
	_helios_box.position = Vector2(w - 8 - _helios_box.size.x, 8)
	_delta_label.position = Vector2(w - 8 - 40, 20)
	_delta_label.size = Vector2(40, 10)
	_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_minimap.position = Vector2(w - 6 - _minimap.size.x, 30)
	_zone_label.position = Vector2(0, 84)  # ниже кнопок меню и отладочной подсказки
	_zone_label.size = Vector2(w, 16)


func _process(_delta: float) -> void:
	for i in 4:
		var s: SkillData = PlayerState.hotbar_skills[i]
		_skill_slots[i].cooldown = PlayerState.skill_cooldown_ratio(i)
		_skill_slots[i].dimmed = s != null and PlayerState.energy < s.energy_cost
	if _atmosphere:
		var preset := _atmosphere.current_preset()
		if preset and preset.zone_name != _zone:
			_zone = preset.zone_name
			_show_zone(_zone)
		var hub := preset != null and preset.hub
		if hub != _hub:
			_set_hub(hub)


func _refresh_slots() -> void:
	for i in 4:
		var s: SkillData = PlayerState.hotbar_skills[i]
		_skill_slots[i].icon = s.icon if s else null
		_skill_slots[i].key_text = InputGlyphs.label("skill_%d" % (i + 1))
		var it: ItemData = PlayerState.hotbar_items[i]
		_item_slots[i].icon = it.icon if it else null
		_item_slots[i].count = PlayerState.count_of(it) if it and it.max_stack > 1 else -1
		_item_slots[i].key_text = InputGlyphs.label("item_%d" % (i + 1))


## Открыть книгу: -1 — на последней закладке Рэя, иначе на разделе section.
func _open_book(section: int) -> void:
	var book := get_tree().current_scene.get_node_or_null("Book") as Book
	if book == null or get_tree().paused:
		return
	if section < 0:
		book.open_half(false)
	else:
		book.open(section)


func _on_deaths_changed(deaths: int) -> void:
	for i in _sparks.size():
		var spent := i < deaths
		var spark := _sparks[i]
		if spent and spark.texture == SPARK_FULL:
			# Искра «тонет»: вспыхивает, опускается и темнеет до цвета Тихой Воды.
			var base_y := spark.position.y
			var t := create_tween()
			t.tween_property(spark, "scale", Vector2(1.6, 1.6), 0.12)
			t.tween_callback(func(): spark.texture = SPARK_SPENT)
			t.tween_property(spark, "scale", Vector2.ONE, 0.2)
			t.parallel().tween_property(spark, "position:y", base_y + 2, 0.2)
			t.tween_property(spark, "position:y", base_y, 0.4)
		elif not spent:
			spark.texture = SPARK_FULL


func _on_helios_changed(helios: int, delta: int) -> void:
	_helios_label.text = str(helios)
	_layout()
	var bump := create_tween()
	bump.tween_property(_helios_label, "scale", Vector2(1, 1.3), 0.06)
	bump.tween_property(_helios_label, "scale", Vector2.ONE, 0.12)
	if delta == 0:
		return
	_delta_label.text = ("+%d" if delta > 0 else "−%d") % absi(delta)
	_delta_label.add_theme_color_override("font_color", Color("e8c870") if delta > 0 else Color("b07ae0"))
	_delta_label.modulate.a = 1.0
	var y := 20.0
	_delta_label.position.y = y
	var t := create_tween()
	t.tween_property(_delta_label, "position:y", y + (4.0 if delta < 0 else -4.0), 0.9)
	t.parallel().tween_property(_delta_label, "modulate:a", 0.0, 0.9).set_delay(0.4)


func _show_zone(zone_name: String) -> void:
	_zone_label.text = zone_name
	var t := create_tween()
	t.tween_property(_zone_label, "modulate:a", 1.0, 0.5)
	t.tween_interval(2.0)
	t.tween_property(_zone_label, "modulate:a", 0.0, 1.0)


func _set_hub(hub: bool) -> void:
	_hub = hub
	for s in _skill_slots + _item_slots:
		s.clickable = not hub
	var t := create_tween()
	t.tween_property(_hotbar, "modulate:a", 0.0 if hub else 1.0, 0.4)


func _menu_button(node_name: String, icon: Texture2D, action: StringName, tip: String, callback: Callable) -> void:
	var b := RoundButton.new(icon, action, tip)
	b.name = node_name
	b.pressed.connect(callback)
	_menu_buttons.add_child(b)


func _icon(node_name: String, tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.name = node_name
	r.texture = tex
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color("e6d6b0"))
	l.add_theme_color_override("font_outline_color", Color("2a1e18"))
	l.add_theme_constant_override("outline_size", 2)
	return l


## Клик по ячейке хотбара — как нажатие клавиши: не после смерти и не во время реплик/переходов
## (иначе тратились энергия и настойки, а Рэй ничего не делал).
func _can_act() -> bool:
	var p := get_tree().get_first_node_in_group("player")
	return p != null and not p.get("input_locked") and (not p.has_method("is_alive") or p.call("is_alive"))
