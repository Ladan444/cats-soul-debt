extends Control
## HUD (UI_SPEC, раздел 2): HP, энергия души, 9 искр-отметок смерти, печать Рубежа,
## 4 скилла + 4 предмета, гелиосы, миникарта, название зоны. В хабе (таверна) хотбар прячется.
## Размеры — в UI-пикселях; родитель — UIScaler.

## Новый HUD (макет «Красивый HUD», Арт/Генерации/UI/hud_v2): графика — лист hud_atlas.png (HudAtlas), раскладка — для
## холста 640×360; при другом размере холста низ привязан к центру и нижнему краю, верх — к углам.
const SPARK_FULL_NAME := "spark_full"
const SPARK_SPENT_NAME := "spark_spent"

## Необязательно: AtmosphereBlender — для названия зоны и режима хаба.
@export var atmosphere_path: NodePath

var _hotbar: Control
var _hp_bar: PixelBar
var _energy_bar: PixelBar
var _sparks: Array[TextureRect] = []
var _tray_l: TextureRect
var _tray_r: TextureRect
var _plank: TextureRect
var _medallion: TextureRect
var _heart: TextureRect
var _soul: TextureRect
var _skill_slots: Array[HotbarSlot] = []
var _item_slots: Array[HotbarSlot] = []
var _helios_label: Label
var _plaque: Control
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

	_plank = _atlas_rect("Plank", "plank")
	_hotbar.add_child(_plank)
	_tray_l = _atlas_rect("TrayL", "tray")
	_tray_r = _atlas_rect("TrayR", "tray")
	_hotbar.add_child(_tray_l)
	_hotbar.add_child(_tray_r)

	_hp_bar = PixelBar.new()
	_hp_bar.name = "HPBar"
	_hp_bar.kind = "hp"
	_hotbar.add_child(_hp_bar)
	_energy_bar = PixelBar.new()
	_energy_bar.name = "EnergyBar"
	_energy_bar.kind = "en"
	_energy_bar.tip_left = true
	_hotbar.add_child(_energy_bar)
	_heart = _atlas_rect("HeartIcon", "heart")
	_soul = _atlas_rect("SoulIcon", "soul")
	_hotbar.add_child(_heart)
	_hotbar.add_child(_soul)

	for i in PlayerState.MAX_DEATHS:
		var spark := _atlas_rect("Spark%d" % i, SPARK_FULL_NAME)
		spark.pivot_offset = Vector2(3.5, 4.5)
		_sparks.append(spark)
		_hotbar.add_child(spark)

	_medallion = _atlas_rect("Emblem", "medallion")
	_hotbar.add_child(_medallion)

	for i in 4:
		var s := HotbarSlot.new()
		s.name = "Skill%d" % i
		s.index = i
		s.is_skill = true
		s.pressed.connect(func(): if _can_act(): PlayerState.use_skill(i))
		_skill_slots.append(s)
		_hotbar.add_child(s)
	for i in 4:
		var s := HotbarSlot.new()
		s.name = "Item%d" % i
		s.index = 4 + i
		s.is_skill = false
		s.pressed.connect(func(): if _can_act(): PlayerState.use_item(i))
		_item_slots.append(s)
		_hotbar.add_child(s)

	# Кнопки меню — левый верхний угол, видны и в хабе: книга, карта, пауза.
	_menu_buttons = HBoxContainer.new()
	_menu_buttons.name = "MenuButtons"
	_menu_buttons.position = Vector2(8, 7)
	_menu_buttons.add_theme_constant_override("separation", 6)
	_menu_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_buttons)
	_menu_button("BookButton", "ic_book", "tag_TAB", "Книга", func(): _open_book(-1))
	_menu_button("MapButton", "ic_map", "tag_M", "Карта", func():
		var book := get_tree().current_scene.get_node_or_null("Book") as Book
		if book and not get_tree().paused:
			book.open_map())
	_menu_button("MenuButton", "ic_gear", "tag_ESC", "Меню", func():
		var pause := get_tree().current_scene.get_node_or_null("PauseMenu")
		if pause and not get_tree().paused:
			pause.open())

	# Гелиосы — плашка в правом верхнем углу (рисуется из спрайта plaque), видна и в хабе.
	_plaque = _Plaque.new()
	_plaque.name = "Helios"
	_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plaque)
	_helios_label = _label("0", 8)
	_helios_label.pivot_offset = Vector2(0, 4)
	_helios_label.add_theme_constant_override("outline_size", 0)
	_helios_label.add_theme_color_override("font_color", Color("f4e4b0"))
	_helios_label.position = Vector2(17, 3)
	_plaque.add_child(_helios_label)
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
	var L := HudAtlas.layout()
	var w := size.x
	var h := size.y
	var ox := floorf(w / 2.0) - 320.0     # раскладка нарисована для холста 640×360: низ — от центра и нижнего края
	var oy := h - 360.0
	var sy: float = L["slot_y"] + oy
	_plank.position = Vector2(L["plank_pos"][0] + ox, L["plank_pos"][1] + oy)
	_tray_l.position = Vector2(L["skills_x"] - 2 + ox, sy - 2)
	_tray_r.position = Vector2(L["items_x"] - 2 + ox, sy - 2)
	var by: float = L["bar_y"] + oy
	_hp_bar.position = Vector2(L["hp_x"] + ox, by)
	_energy_bar.position = Vector2(L["en_x"] - 4 + ox, by)
	_heart.position = Vector2(L["hp_x"] - 3 + ox, by - 2)
	_soul.position = Vector2(L["en_x"] + L["bar_w"] - 9 + ox, by - 2)
	var mcx: float = L["med_cx"] + ox
	var mcy: float = L["med_cy"] + oy
	_medallion.position = Vector2(mcx - 21, mcy - 21)
	for i in _sparks.size():
		var a := deg_to_rad(-L["spark_deg"] + i * (2.0 * L["spark_deg"] / 8.0))
		_sparks[i].position = Vector2(roundf(mcx + sin(a) * L["spark_r"] - 3.5), roundf(mcy - cos(a) * L["spark_r"] - 4.5))
	for i in 4:
		_skill_slots[i].position = Vector2(L["skills_x"] + ox + i * (L["slot"] + L["gap"]), sy)
		_item_slots[i].position = Vector2(L["items_x"] + ox + i * (L["slot"] + L["gap"]), sy)
	_refresh_plaque()
	_delta_label.position = Vector2(w - 8 - 40, 22)
	_delta_label.size = Vector2(40, 10)
	_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_minimap.position = Vector2(w - 104, 21)
	_zone_label.position = Vector2(0, 124)  # ниже кнопок меню и круга миникарты
	_zone_label.size = Vector2(w, 16)


## Плашка гелиосов: ширина по числу цифр, правый край — 6 px от края холста.
func _refresh_plaque() -> void:
	var digits := str(PlayerState.helios).length()
	var pw := 22 + digits * 8
	_plaque.size = Vector2(pw, 14)
	_plaque.position = Vector2(size.x - 6 - pw, 5)
	_plaque.queue_redraw()


## Плашка: левый и правый край из спрайта, середина тянется повтором 20-го столбца.
class _Plaque extends Control:
	func _draw() -> void:
		var sp := HudAtlas.tex("plaque")
		var r := sp.region
		var w := int(size.x)
		var left := AtlasTexture.new()
		left.atlas = sp.atlas
		left.region = Rect2(r.position, Vector2(8, r.size.y))
		draw_texture(left, Vector2.ZERO)
		var mid := AtlasTexture.new()
		mid.atlas = sp.atlas
		mid.region = Rect2(r.position + Vector2(24, 0), Vector2(4, r.size.y))
		var x := 8
		while x < w - 8:
			var cw := mini(4, w - 8 - x)
			var piece := AtlasTexture.new()
			piece.atlas = sp.atlas
			piece.region = Rect2(r.position + Vector2(24, 0), Vector2(cw, r.size.y))
			draw_texture(piece, Vector2(x, 0))
			x += cw
		var right := AtlasTexture.new()
		right.atlas = sp.atlas
		right.region = Rect2(r.position + Vector2(r.size.x - 8, 0), Vector2(8, r.size.y))
		draw_texture(right, Vector2(w - 8, 0))
		draw_texture(HudAtlas.tex("coin"), Vector2(3, 0))


func _process(_delta: float) -> void:
	for i in 4:
		var s: SkillData = PlayerState.hotbar_skills[i]
		_skill_slots[i].cooldown = PlayerState.skill_cooldown_ratio(i)
		_skill_slots[i].cooldown_secs = 0.0
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
		if spent and spark.texture == HudAtlas.tex(SPARK_FULL_NAME):
			# Искра «тонет»: вспыхивает, опускается и темнеет до цвета Тихой Воды.
			var base_y := spark.position.y
			var t := create_tween()
			t.tween_property(spark, "scale", Vector2(1.6, 1.6), 0.12)
			t.tween_callback(func(): spark.texture = HudAtlas.tex(SPARK_SPENT_NAME))
			t.tween_property(spark, "scale", Vector2.ONE, 0.2)
			t.parallel().tween_property(spark, "position:y", base_y + 2, 0.2)
			t.tween_property(spark, "position:y", base_y, 0.4)
		elif not spent:
			spark.texture = HudAtlas.tex(SPARK_FULL_NAME)


func _on_helios_changed(helios: int, delta: int) -> void:
	_helios_label.text = str(helios)
	_refresh_plaque()
	var bump := create_tween()
	bump.tween_property(_helios_label, "scale", Vector2(1, 1.3), 0.06)
	bump.tween_property(_helios_label, "scale", Vector2.ONE, 0.12)
	if delta == 0:
		return
	_delta_label.text = ("+%d" if delta > 0 else "−%d") % absi(delta)
	_delta_label.add_theme_color_override("font_color", Color("e8c870") if delta > 0 else Color("b07ae0"))
	_delta_label.modulate.a = 1.0
	var y := 22.0
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


func _menu_button(node_name: String, icon_sprite: String, tag_sprite: String, tip: String, callback: Callable) -> void:
	var b := RoundButton.new(icon_sprite, tag_sprite, tip)
	b.name = node_name
	b.pressed.connect(callback)
	_menu_buttons.add_child(b)


func _atlas_rect(node_name: String, sprite: String) -> TextureRect:
	var r := _icon(node_name, HudAtlas.tex(sprite))
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r


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
