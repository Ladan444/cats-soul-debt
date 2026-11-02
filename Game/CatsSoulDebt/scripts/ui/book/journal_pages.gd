extends Node
## Страницы журнала в книге (UI_SPEC, раздел 4): «Записи», «Люди», «Улики», «Бестиарий».
## Карта места — не в книге, а во весь экран на M (LocationMap вызывает build_map).
## Записи от руки — рукописным шрифтом, приказы командиров — печатным; авторы различаются цветом чернил.
## Рамку, закладки и ввод держит Book; сюда приходят только области страниц.

## Рукописный шрифт First Time Writing (GGBotNet, CC0): 16 UI-пикселей, со сглаживанием
## (без него растеризатор теряет тонкие штрихи) и утолщением, чтобы чернила не были бледными.
const HAND_FONT := preload("res://assets/fonts/first_time_writing/FirstTimeWriting.ttf")
const HAND_SIZE := 16
const HAND_EMBOLDEN := 0.7
const INK := Color("2a1e18")
const FADED := Color("8a7350")
const GREEN := Color("3f6a4a")

## Карта текущей локации и игрок — задаёт Book.
var map: JournalMap
var player: Node3D

var _left: VBoxContainer
var _right: VBoxContainer
var _text_width: float = 240.0
## Запись, которую нужно выбрать при следующем показе «Записей» (ссылка из «Ключевого»).
var pending_entry: StringName = &""
var _hand_font: FontVariation


## Строит раздел tab (0..3) в областях страниц.
func build(tab: int, left: Control, right: Control) -> void:
	_text_width = left.size.x - 24
	_left = _page_box(left, 3)
	_right = _page_box(right, 4)
	match tab:
		0: _records_tab(JournalEntry.Section.RECORDS, "Записи")
		1: _records_tab(JournalEntry.Section.PEOPLE, "Люди")
		2: _clues_tab()
		3: _bestiary_tab()


## Карта места во весь экран (LocationMap): слева — списки мест, справа — рисунок.
func build_map(left: Control, right: Control) -> void:
	_text_width = left.size.x - 24
	_left = _page_box(left, 3)
	_right = _page_box(right, 4)
	_maps_tab(right)


func handle_cancel() -> bool:
	return false


func _records_tab(section: JournalEntry.Section, title: String) -> void:
	_left.add_child(_title(title))
	var list := JournalState.visible_entries(section)
	if list.is_empty():
		_left.add_child(_wrap("Пока пусто.", FADED))
		return
	var target: ClawButton
	var target_entry: JournalEntry = list[0]
	for e in list:
		var b := ClawButton.new(e.title + ("  *" if JournalState.is_new(e.id) else ""), true)
		b.custom_minimum_size.x = _text_width
		b.focus_entered.connect(_show_entry.bind(e))
		b.pressed.connect(_show_entry.bind(e))
		_left.add_child(b)
		if target == null or e.id == pending_entry:
			target = b
			target_entry = e
	pending_entry = &""
	_focus_later(target)
	_show_entry(target_entry)


func _show_entry(e: JournalEntry) -> void:
	if not is_instance_valid(_right):
		return
	for c in _right.get_children():
		c.queue_free()
	JournalState.mark_read(e.id)
	var ink: Color = JournalEntry.AUTHOR_INK[e.author]
	var title := _wrap(e.title, ink)
	title.add_theme_font_size_override("font_size", 16 if e.title.length() <= 14 else 8)
	_right.add_child(title)
	if e.section == JournalEntry.Section.PEOPLE and e.portrait_sheet:
		_right.add_child(_portrait(e.portrait_sheet))
	else:
		_right.add_child(_wrap("Почерк: " + JournalEntry.AUTHOR_NAMES[e.author], FADED))
	# Казённые бумаги командиров — ровным «печатным» шрифтом, всё остальное — от руки.
	_right.add_child(_wrap(e.text, ink) if e.author == JournalEntry.Author.COMMANDER else _hand(e.text, ink))
	if e.sealed:
		_right.add_child(_Seal.new())


func _maps_tab(right: Control) -> void:
	_left.add_child(_title("Карта"))
	if map == null:
		_left.add_child(_wrap("Для этого места карты нет.", FADED))
		return
	_left.add_child(_wrap(map.title, GREEN))
	# Где Рэй сейчас — с заметкой; остальное — короткими списками (на больших картах заметки не влезут).
	# Нумерация — как на рисунке карты (JournalMapView): только места, без проходов.
	var here: Dictionary = {}
	if is_instance_valid(player):
		here = map.room_at(Vector2(player.global_position.x, player.global_position.z))
	var explored: PackedStringArray = []
	var hinted: PackedStringArray = []
	var number := 0
	for r in map.rooms:
		if r.get("passage", false):
			continue
		number += 1
		var label := "%d. %s" % [number, r["name"]]
		match JournalState.room_state(map.id, r["id"]):
			2:
				explored.append(label)
				if not here.is_empty() and here["id"] == r["id"] and r["note"] != "":
					_left.add_child(_hand("Здесь: %s — %s" % [label, r["note"]], INK, 14))
			1:
				hinted.append(label)
	if not explored.is_empty():
		_left.add_child(_hand("Был: " + " · ".join(explored), INK, 14))
	if not hinted.is_empty():
		var hint_note: String = ""
		for r in map.rooms:
			if r.get("hinted", false) and r.has("hint_note"):
				hint_note = " (%s)" % r["hint_note"].trim_suffix(".")
				break
		var listed := " · ".join(hinted) if hinted.size() <= 6 else "ещё %d мест — на карте пунктиром" % hinted.size()
		_left.add_child(_hand("Намечено%s: %s" % [hint_note, listed], FADED, 14))
	var view := JournalMapView.new()
	view.position = Vector2(4, 8)
	view.size = Vector2(right.size.x - 8, right.size.y - 48)
	view.map = map
	view.player_position = player.global_position if is_instance_valid(player) else null
	right.add_child(view)
	var legend := _wrap("x — смерть, фиолетовые — фонари душ, зелёная лапа — Рэй", FADED)
	legend.custom_minimum_size.x = right.size.x - 24   # по ширине своей страницы (на карте во весь экран — шире)
	legend.position = Vector2(12, right.size.y - 36)
	right.add_child(legend)


func _clues_tab() -> void:
	_left.add_child(_title("Улики"))
	_left.add_child(_wrap("Кто знал о моих ночных вылазках к печати — и молчал?", INK))
	var linked := false
	for e in PlayerState.inventory:
		var item: ItemData = e["item"]
		if item.category == ItemData.Category.KEY and item.journal_entry != &"":
			var entry := JournalState.entry(item.journal_entry)
			if entry == null:
				continue
			var b := ClawButton.new(item.name, true)
			b.custom_minimum_size.x = _text_width
			b.focus_entered.connect(_show_entry.bind(entry))
			b.pressed.connect(_show_entry.bind(entry))
			_left.add_child(b)
			if not linked:
				_focus_later(b)
				_show_entry(entry)
			linked = true
	if not linked:
		_right.add_child(_wrap("Улик пока нет.", FADED))
	_left.add_child(_wrap("Связи между уликами появятся по ходу расследования.", FADED))


func _bestiary_tab() -> void:
	_left.add_child(_title("Бестиарий"))
	_left.add_child(_wrap("Ещё ни одной встречи.", FADED))
	_right.add_child(_wrap("Сюда я буду записывать тех, кто живёт внизу: повадки, слабости, как уцелеть.", FADED))


# --- Помощники ---------------------------------------------------------------------

## Набросок-портрет: кадр «вниз» из листа спрайтов, чернилами (силуэт сепией).
func _portrait(sheet: Texture2D) -> Control:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 0, 64, 64)
	var r := TextureRect.new()
	r.texture = atlas
	r.custom_minimum_size = Vector2(64, 64)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.self_modulate = Color(0.42, 0.3, 0.22, 0.85)
	return r


func _focus_later(target: Control) -> void:
	(func(): if is_instance_valid(target) and target.is_inside_tree(): target.grab_focus()).call_deferred()


func _title(text: String) -> Label:
	var l := _label(text, INK)
	l.add_theme_font_size_override("font_size", 16)
	return l


## Прокручиваемая область страницы с вертикальным списком внутри (колесо мыши, длинные записи).
func _page_box(page: Control, separation: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 10)
	scroll.size = page.size - Vector2(24, 18)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = true
	page.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = scroll.size.x
	box.add_theme_constant_override("separation", separation)
	scroll.add_child(box)
	return box


## Текст «от руки» — рукописным шрифтом.
func _hand(text: String, color: Color, font_size: int = HAND_SIZE) -> Label:
	var l := _wrap(text, color)
	if _hand_font == null:
		_hand_font = FontVariation.new()
		_hand_font.base_font = HAND_FONT
		_hand_font.variation_embolden = HAND_EMBOLDEN
	l.add_theme_font_override("font", _hand_font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("line_spacing", -2)
	return l


func _wrap(text: String, color: Color) -> Label:
	var l := _label(text, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = _text_width
	return l


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 0)
	return l


## Сургучная печать под казёнными бумагами.
class _Seal extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(20, 16)

	func _draw() -> void:
		var c := Vector2(10, 8)
		for y in range(-6, 7):
			for x in range(-7, 8):
				var d := Vector2(x, y).length()
				if d <= 6.5:
					draw_rect(Rect2(c + Vector2(x, y), Vector2.ONE), Color("8a1e1e") if d > 4.0 else Color("b23a3a"))
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(3, 3)), Color("e8c870"))
