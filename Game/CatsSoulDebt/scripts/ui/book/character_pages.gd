extends Node
## Страницы Рэя в книге (UI_SPEC, раздел 3): слева — Рэй, экипировка, характеристики;
## справа — сетка вкладки («Снаряжение», «Предметы», «Души», «Ключевое»), хотбар, описание, действия.
## Рамку, закладки и ввод держит Book; сюда приходят только области страниц.

const RAY_SHEET := preload("res://assets/sprites/ray/ray_anim.png")
const ICON_HELIOS := preload("res://assets/ui/icon_helios.png")
const ICON_SOUL := preload("res://assets/ui/icon_soul.png")
const SLOT_ICONS := {
	"weapon": preload("res://assets/ui/icon_sword.png"),
	"cloak": preload("res://assets/ui/icon_cloak.png"),
	"armor": preload("res://assets/ui/icon_armor.png"),
	"amulet": preload("res://assets/ui/icon_amulet.png"),
	"relic_1": preload("res://assets/ui/icon_relic.png"),
	"relic_2": preload("res://assets/ui/icon_relic.png"),
}
const INK := Color("2a1e18")
const GREEN := Color("3f6a4a")
const FADED := Color("8a7350")
const RED := Color("7a2a24")
const TITLES := ["Снаряжение", "Предметы", "Души", "Ключевое"]
## Ширина текста описаний (выставляется при сборке правой страницы).
var _text_w: float = 200.0

const GRID_COLS := 6
const GRID_ROWS := 3

var book: Node  # Book — для ссылки «Открыть в журнале»

var _tab: int = 0
var _grid: GridContainer
var _hotbar_label: Label
var _hotbar_grid: GridContainer
var _hotbar_slots: Array[InventorySlot] = []
var _details: VBoxContainer
var _actions: HFlowContainer
var _stats: Label
var _helios: Label
var _portrait: TextureRect
var _equip_slots: Dictionary = {}
var _selected: Variant = null
var _assigning: Variant = null
var _confirm_drop: bool = false
var _last_focus_index: int = 0
var _frame: int = 0
var _frame_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerState.items_changed.connect(_refresh)
	PlayerState.stats_changed.connect(_refresh_stats)
	PlayerState.helios_changed.connect(func(_h, _d): _refresh_stats())


func _process(delta: float) -> void:
	if _portrait == null or not is_instance_valid(_portrait) or not _portrait.is_visible_in_tree():
		return
	_frame_time += delta
	if _frame_time > 0.25:
		_frame_time = 0.0
		_frame = (_frame + 1) % 4
		(_portrait.texture as AtlasTexture).region = Rect2(_frame * 64, 0, 64, 64)


## Строит вкладку tab (0..3) в областях страниц.
func build(tab: int, left: Control, right: Control) -> void:
	_assigning = null
	_tab = tab
	_selected = null
	_build_left(left)
	_build_right(right)
	_refresh()
	_last_focus_index = 0
	_focus_grid.call_deferred(0)


## Esc внутри страниц: сначала отменяет назначение в хотбар. true — событие обработано.
func handle_cancel() -> bool:
	if _assigning != null:
		_stop_assign()
		return true
	return false


# --- Левая страница -------------------------------------------------------------

func _build_left(left: Control) -> void:
	_equip_slots.clear()
	var title := _ink("Рэй", INK)
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 10)
	title.size = Vector2(left.size.x, 16)
	left.add_child(title)

	var atlas := AtlasTexture.new()
	atlas.atlas = RAY_SHEET
	atlas.region = Rect2(0, 0, 64, 64)
	_portrait = TextureRect.new()
	_portrait.texture = atlas
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait.size = Vector2(128, 128)
	_portrait.position = Vector2(floorf((left.size.x - 128) / 2.0), 24)
	left.add_child(_portrait)

	var lx := 22.0
	var rx := left.size.x - 22 - 22
	var places := {"weapon": Vector2(lx, 46), "cloak": Vector2(lx, 80), "relic_1": Vector2(lx, 114),
		"armor": Vector2(rx, 46), "amulet": Vector2(rx, 80), "relic_2": Vector2(rx, 114)}
	for slot in places:
		var s := InventorySlot.new()
		s.position = places[slot]
		s.placeholder = SLOT_ICONS[slot]
		s.focus_entered.connect(func(): _select("slot:" + slot))
		s.pressed.connect(func():
			if PlayerState.equipment.has(slot):
				PlayerState.unequip(slot))
		left.add_child(s)
		_equip_slots[slot] = s

	_stats = _ink("", INK)
	_stats.position = Vector2(30, 166)
	_stats.size = Vector2(left.size.x - 60, 60)
	left.add_child(_stats)

	var coin := TextureRect.new()
	coin.texture = ICON_HELIOS
	coin.position = Vector2(30, left.size.y - 24)
	left.add_child(coin)
	_helios = _ink("", INK)
	_helios.position = Vector2(44, left.size.y - 24)
	left.add_child(_helios)


# --- Правая страница ------------------------------------------------------------

func _build_right(right: Control) -> void:
	var title := _ink(TITLES[_tab], INK)
	title.add_theme_font_size_override("font_size", 16)
	title.position = Vector2(12, 10)
	right.add_child(title)

	# Сетка показывает 3 ряда; если вещей больше — прокручивается вслед за фокусом.
	var grid_scroll := ScrollContainer.new()
	grid_scroll.position = Vector2(12, 32)
	grid_scroll.size = Vector2(GRID_COLS * 24, GRID_ROWS * 24)
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	grid_scroll.follow_focus = true
	right.add_child(grid_scroll)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	grid_scroll.add_child(_grid)

	# Хотбар 2×2 справа от сетки.
	_hotbar_label = _ink("Хотбар", FADED)
	_hotbar_label.position = Vector2(170, 32)
	right.add_child(_hotbar_label)
	_hotbar_grid = GridContainer.new()
	_hotbar_grid.columns = 2
	_hotbar_grid.position = Vector2(180, 46)
	_hotbar_grid.add_theme_constant_override("h_separation", 2)
	_hotbar_grid.add_theme_constant_override("v_separation", 2)
	right.add_child(_hotbar_grid)
	_hotbar_slots.clear()
	for i in 4:
		var s := InventorySlot.new()
		s.focus_mode = Control.FOCUS_NONE
		s.pressed.connect(_on_hotbar_pressed.bind(i))
		_hotbar_slots.append(s)
		_hotbar_grid.add_child(s)

	_text_w = right.size.x - 24   # ширина текста — по странице справа (она у книги автора уже прежней)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 110)
	scroll.size = Vector2(_text_w, 144)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	right.add_child(scroll)
	_details = VBoxContainer.new()
	_details.custom_minimum_size.x = scroll.size.x
	_details.add_theme_constant_override("separation", 3)
	scroll.add_child(_details)

	_actions = HFlowContainer.new()
	_actions.position = Vector2(8, 262)
	_actions.size = Vector2(right.size.x - 16, 30)
	_actions.add_theme_constant_override("h_separation", 4)
	right.add_child(_actions)


# --- Обновление ------------------------------------------------------------------

func _tab_entries() -> Array:
	var result := []
	match _tab:
		0:
			for e in PlayerState.inventory:
				if e["item"].category == ItemData.Category.EQUIPMENT:
					result.append(e)
		1:
			for e in PlayerState.inventory:
				if e["item"].category in [ItemData.Category.CONSUMABLE, ItemData.Category.MATERIAL]:
					result.append(e)
		2:
			result = PlayerState.souls.duplicate()
		3:
			for e in PlayerState.inventory:
				if e["item"].category == ItemData.Category.KEY:
					result.append(e)
	return result


func _refresh() -> void:
	if _grid == null or not is_instance_valid(_grid):
		return
	var entries := _tab_entries()
	_ensure_cells(maxi(GRID_COLS * GRID_ROWS, ceili(entries.size() / float(GRID_COLS)) * GRID_COLS))
	for i in _grid.get_child_count():
		var s: InventorySlot = _grid.get_child(i)
		if i < entries.size():
			var e: Dictionary = entries[i]
			if e.has("soul"):
				s.payload = e
				s.icon_tex = ICON_SOUL
				s.count = -1
				s.equipped = false
				s.dimmed = e["state"] != SoulData.State.COLLECTED
			else:
				s.payload = e["item"]
				s.icon_tex = e["item"].icon
				s.count = e["count"] if e["item"].max_stack > 1 else -1
				s.equipped = PlayerState.is_equipped(e["item"])
				s.dimmed = false
		else:
			s.payload = null
			s.icon_tex = null
			s.count = -1
			s.equipped = false
	for slot in _equip_slots:
		var item: ItemData = PlayerState.equipment.get(slot)
		_equip_slots[slot].icon_tex = item.icon if item else null
	var skills_row := _tab == 2
	if _assigning == null:
		_hotbar_label.text = "Хотбар"
		_hotbar_label.add_theme_color_override("font_color", FADED)
	_hotbar_grid.visible = _tab != 3
	_hotbar_label.visible = _tab != 3
	for i in 4:
		var data: Resource = PlayerState.hotbar_skills[i] if skills_row else PlayerState.hotbar_items[i]
		_hotbar_slots[i].icon_tex = data.icon if data else null
		_hotbar_slots[i].count = PlayerState.count_of(data) if data is ItemData and data.max_stack > 1 else -1
	_refresh_stats()
	_select(_selected)


func _refresh_stats() -> void:
	if _stats == null or not is_instance_valid(_stats):
		return
	var ps := PlayerState
	_stats.text = "HP       %d/%d\nДуша     %d/%d\nУрон     %d\nЗащита   %d" % [
		ps.hp, ps.max_hp, ps.energy, ps.max_energy, ps.damage_bonus, ps.defense]
	_helios.text = "%d гелиосов" % ps.helios


func _ensure_cells(n: int) -> void:
	while _grid.get_child_count() < n:
		var i := _grid.get_child_count()
		var s := InventorySlot.new()
		s.focus_entered.connect(_on_grid_focus.bind(s, i))
		s.pressed.connect(_on_grid_pressed.bind(s))
		_grid.add_child(s)


func _focus_grid(index: int) -> void:
	if _grid != null and is_instance_valid(_grid) and _grid.is_visible_in_tree() and index < _grid.get_child_count():
		_grid.get_child(index).grab_focus()


# --- Выбор и описание -------------------------------------------------------------

func _on_grid_focus(slot: InventorySlot, index: int) -> void:
	_last_focus_index = index
	_select(slot.payload)


func _on_grid_pressed(slot: InventorySlot) -> void:
	var p: Variant = slot.payload
	if p is ItemData:
		if p.category == ItemData.Category.EQUIPMENT:
			_toggle_equip(p)
		elif p.category == ItemData.Category.CONSUMABLE:
			PlayerState.start_use(p)  # еда — Рэй начнёт есть, когда книга закроется


func _select(p: Variant) -> void:
	if _details == null or not is_instance_valid(_details):
		return
	_selected = p
	_confirm_drop = false
	for c in _details.get_children():
		c.queue_free()
	for c in _actions.get_children():
		c.queue_free()
	if p == null:
		_details.add_child(_wrap("Пусто.", FADED))
		return
	if p is String and p.begins_with("slot:"):
		var slot: String = p.substr(5)
		var item: ItemData = PlayerState.equipment.get(slot)
		var slot_name: String = PlayerState.EQUIP_SLOT_NAMES[PlayerState.EQUIP_SLOTS.find(slot)]
		if item == null:
			_details.add_child(_heading(SLOT_ICONS[slot], slot_name))
			_details.add_child(_wrap("Пусто. Надеть предмет можно во вкладке «Снаряжение».", FADED))
			return
		_describe_item(item)
		_action("Снять", func(): PlayerState.unequip(slot))
		return
	if p is ItemData:
		_describe_item(p)
		_item_actions(p)
	elif p is Dictionary and p.has("soul"):
		_describe_soul(p)


func _describe_item(item: ItemData) -> void:
	_details.add_child(_heading(item.icon, item.name))
	_details.add_child(_wrap(item.type_line(), GREEN))
	_details.add_child(_wrap(item.description, INK))
	var stats := item.stat_lines()
	if not stats.is_empty():
		_details.add_child(_wrap("  ".join(stats), GREEN))
	if not item.owner_story.is_empty():
		_details.add_child(_wrap(item.owner_story, RED))


func _item_actions(item: ItemData) -> void:
	match item.category:
		ItemData.Category.EQUIPMENT:
			_action("Снять" if PlayerState.is_equipped(item) else "Надеть", func(): _toggle_equip(item))
		ItemData.Category.CONSUMABLE:
			_action("Съесть" if item.use_time > 0.0 else "Пить", func(): PlayerState.start_use(item))
			_action("В хотбар", func(): _start_assign(item))
		ItemData.Category.KEY:
			var b := _action("В журнале", func(): _open_journal(item))
			b.disabled = item.journal_entry == &""
			return
	if QuestState.needs_item(String(item.id)):
		return   # нужна для взятого квеста — не выбросить
	_action("Выбросить", func():
		if not _confirm_drop:
			_confirm_drop = true
			_actions.get_child(_actions.get_child_count() - 1).text = "Точно?"
			return
		PlayerState.remove_item(item, PlayerState.count_of(item)))


func _describe_soul(e: Dictionary) -> void:
	var soul: SoulData = e["soul"]
	_details.add_child(_heading(ICON_SOUL, soul.name))
	_details.add_child(_wrap("%s · %s" % [soul.company, SoulData.STATE_NAMES[e["state"]]], GREEN))
	_details.add_child(_wrap("«%s»" % soul.memory, INK))
	if soul.skill:
		var s := soul.skill
		_details.add_child(_wrap("Сила: %s" % s.name, GREEN))
		_details.add_child(_wrap("%s Энергия %d, перезарядка %.0f с." % [s.description, s.energy_cost, s.cooldown], INK))
		_action("В хотбар", func(): _start_assign(s))


func _toggle_equip(item: ItemData) -> void:
	if PlayerState.is_equipped(item):
		for slot in PlayerState.equipment.keys():
			if PlayerState.equipment[slot] == item:
				PlayerState.unequip(slot)
	else:
		PlayerState.equip(item)


func _open_journal(item: ItemData) -> void:
	if book and book.has_method("open_entry"):
		book.open_entry(item.journal_entry)


# --- Назначение в хотбар ------------------------------------------------------------

func _start_assign(data: Resource) -> void:
	_assigning = data
	_hotbar_label.text = "Куда?"
	_hotbar_label.add_theme_color_override("font_color", GREEN)
	for s in _hotbar_slots:
		s.focus_mode = Control.FOCUS_ALL
	_hotbar_slots[0].grab_focus()


func _on_hotbar_pressed(index: int) -> void:
	if _assigning == null:
		return
	if _assigning is SkillData:
		PlayerState.assign_skill(index, _assigning)
	else:
		PlayerState.assign_item(index, _assigning)
	_stop_assign()


func _stop_assign() -> void:
	if _assigning == null:
		return
	_assigning = null
	for s in _hotbar_slots:
		s.focus_mode = Control.FOCUS_NONE
	_refresh()
	_focus_grid(_last_focus_index)


# --- Помощники ---------------------------------------------------------------------

func _action(text: String, callback: Callable) -> ClawButton:
	var b := ClawButton.new(text, true)
	b.pressed.connect(func():
		callback.call()
		if not _confirm_drop:
			_focus_grid.call_deferred(_last_focus_index))
	_actions.add_child(b)
	return b


func _heading(icon: Texture2D, title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var pic := TextureRect.new()
	pic.texture = icon
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.custom_minimum_size = icon.get_size() * 2 if icon else Vector2.ZERO
	row.add_child(pic)
	var l := _ink(title, INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _text_w - pic.custom_minimum_size.x - 4
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


func _wrap(text: String, color: Color) -> Label:
	var l := _ink(text, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _text_w
	return l


func _ink(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 0)
	return l
