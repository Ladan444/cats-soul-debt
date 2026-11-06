extends CanvasLayer
## Торговля у жителя (данные — SHOPS в scripts/data/village_quests.gd): разворот в стиле книги.
## Слева — список: «Купить» (что продаёт житель), «Продать» (что он берёт у Рэя), у кузницы — улучшение меча;
## справа — выбранная вещь: описание, характеристики, цена и кнопка. Игра на паузе.
## Мышь, клавиатура и геймпад (фокус кнопок, Q/E и LB/RB — вкладки); Esc/B/крестик/клик мимо — закрыть.

signal closed

const DATA := preload("res://scripts/data/village_quests.gd")
const COVER := preload("res://assets/ui/book_cover.png")
const PAGE := preload("res://assets/ui/book_page.png")
const INK := Color("2a1e18")
const FADED := Color("8a7350")
const GOLD := Color("9a6a10")
const STAT_NAMES := {"damage": "урон", "defense": "защита", "max_hp": "здоровье", "max_energy": "энергия души"}

var _shop: Dictionary = {}
var _tab := "sell"
var _list: VBoxContainer
var _info: VBoxContainer
var _title: Label
var _wallet: Label
var _content: Control


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func is_open() -> bool:
	return visible


func open(shop_id: String) -> void:
	_shop = DATA.SHOPS.get(shop_id, {})
	if _shop.is_empty():
		return
	_tab = "upgrade" if _shop.has("upgrades") else "sell"
	_build()
	visible = true
	get_tree().paused = true
	Audio.play("book_open")
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Audio.play("book_close")
	get_viewport().gui_release_focus()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close()
	elif (event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev")) and not _shop.get("buy", {}).is_empty():
		_tab = "buy" if _tab == "sell" else "sell"
		_refresh()
	else:
		return
	get_viewport().set_input_as_handled()


func _build() -> void:
	if _content:
		_content.queue_free()
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.02, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	_content.add_child(dim)
	var scaler: Control = load("res://scripts/ui/ui_scaler.gd").new()
	scaler.set("min_canvas", Vector2(440, 270))
	_content.add_child(scaler)
	var size := Vector2(420, 250)
	var cover := _patch(COVER, 14)
	cover.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	cover.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.size = size
	cover.position = ((scaler.size - size) / 2.0).floor()
	scaler.add_child(cover)
	var left := _patch(PAGE, 8)
	left.position = Vector2(10, 10)
	left.size = Vector2(196, size.y - 20)
	cover.add_child(left)
	var right := _patch(PAGE, 8)
	right.position = Vector2(214, 10)
	right.size = Vector2(196, size.y - 20)
	cover.add_child(right)
	var close_btn := CloseButton.new()
	close_btn.position = Vector2(size.x - 18, 2)
	close_btn.pressed.connect(close)
	cover.add_child(close_btn)
	var lv := VBoxContainer.new()
	lv.position = Vector2(10, 8)
	lv.size = left.size - Vector2(20, 16)
	lv.add_theme_constant_override("separation", 3)
	left.add_child(lv)
	_title = _label(_shop["title"].to_upper(), INK, 8)
	lv.add_child(_title)
	_wallet = _label("", GOLD, 8)
	lv.add_child(_wallet)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	lv.add_child(_list)
	_info = VBoxContainer.new()
	_info.position = Vector2(10, 8)
	_info.size = right.size - Vector2(20, 16)
	_info.add_theme_constant_override("separation", 4)
	right.add_child(_info)


func _refresh() -> void:
	_clear(_list)
	_clear(_info)
	_wallet.text = "Гелиосы: %d" % PlayerState.helios
	if not _shop.get("buy", {}).is_empty():
		var tabs := HBoxContainer.new()
		for t in [["sell", "Купить"], ["buy", "Продать"]]:
			var b := Button.new()
			b.text = t[1]
			b.toggle_mode = true
			b.button_pressed = _tab == t[0]
			b.pressed.connect(func():
				_tab = t[0]
				_refresh())
			tabs.add_child(b)
		_list.add_child(tabs)
	var entries := _entries()
	if entries.is_empty():
		_list.add_child(_label("Нечего предложить." if _tab != "upgrade" else "Лучше уже не сделать.", FADED, 8))
	var first: Button = null
	for e in entries:
		var b := Button.new()
		b.text = "%d г. · %s" % [e["price"], e["item"].name]   # цена — первой: длинные названия обрезаются
		b.tooltip_text = b.text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size.x = 176
		b.add_theme_font_size_override("font_size", 8)
		b.focus_entered.connect(_show.bind(e))
		b.mouse_entered.connect(_show.bind(e))
		b.pressed.connect(_deal.bind(e))
		_list.add_child(b)
		if first == null:
			first = b
	if first:
		_focus_later(first)   # отложенно, и только если кнопка ещё в дереве (вкладку/лавку могли закрыть)
		_show(entries[0])
	else:
		_info.add_child(_label("Esc — закрыть", FADED, 8))


## Строки списка вкладки: {item, price, kind, from}.
func _entries() -> Array:
	var out := []
	match _tab:
		"sell":
			for s in _shop.get("sell", []):
				var it := ContentDB.item(StringName(s["item"]))
				# Снаряжение, которое у Рэя уже есть, не предлагается: второй такой же не надеть.
				if it and not (it.max_stack <= 1 and PlayerState.count_of(it) > 0):
					out.append({"item": it, "price": int(s["price"]), "kind": "buy"})
		"buy":
			var wants: Dictionary = _shop.get("buy", {})
			for id in wants:
				var it := ContentDB.item(StringName(id))
				# Нужное для взятого квеста не продаётся (как и не выбрасывается).
				if it and PlayerState.count_of(it) > 0 and not QuestState.needs_item(String(id)):
					out.append({"item": it, "price": int(wants[id]), "kind": "sell"})
		"upgrade":
			var weapon: ItemData = PlayerState.equipment.get("weapon")
			for u in _shop.get("upgrades", []):
				if weapon and String(weapon.id) == u["from"]:
					out.append({"item": ContentDB.item(StringName(u["to"])), "price": int(u["price"]), "kind": "upgrade",
						"from": weapon, "material": ContentDB.item(StringName(u.get("material", ""))),
						"count": int(u.get("count", 0))})
	return out


func _show(e: Dictionary) -> void:
	_clear(_info)
	var it: ItemData = e["item"]
	_info.add_child(_label(it.name, INK, 8))
	_info.add_child(_label(it.description, FADED, 8))
	for k in it.stats:
		_info.add_child(_label("%s +%s" % [STAT_NAMES.get(k, k), it.stats[k]], INK, 8))
	if it.heal > 0:
		_info.add_child(_label("лечит %d" % int(it.heal), INK, 8))
	if e["kind"] == "upgrade":
		_info.add_child(_label("Сейчас: %s (урон %s)" % [e["from"].name, e["from"].stats.get("damage", 0)], FADED, 8))
	var verb: String = {"buy": "Купить", "sell": "Продать", "upgrade": "Улучшить"}[e["kind"]]
	var price := _label("%s за %d г." % [verb, e["price"]], GOLD, 8)
	_info.add_child(price)
	if e["kind"] == "buy" and _full(it):
		_info.add_child(_label("Больше не унести (%d)." % it.max_stack, FADED, 8))
	elif e["kind"] != "sell" and PlayerState.helios < e["price"]:
		_info.add_child(_label("Не хватает гелиосов.", FADED, 8))
	if e.get("material") != null:
		var have := PlayerState.count_of(e["material"])
		_info.add_child(_label("Нужно: %s ×%d (у тебя %d)" % [e["material"].name.to_lower(), e["count"], have],
			INK if have >= e["count"] else FADED, 8))
	if e["kind"] == "sell":
		_info.add_child(_label("У тебя: %d" % PlayerState.count_of(it), FADED, 8))


func _deal(e: Dictionary) -> void:
	var it: ItemData = e["item"]
	match e["kind"]:
		"buy":
			if PlayerState.helios < e["price"] or _full(it):
				return
			PlayerState.add_helios(-e["price"], false)
			PlayerState.add_item(it, 1)
		"sell":
			if PlayerState.count_of(it) == 0:
				return
			PlayerState.remove_item(it, 1)
			PlayerState.add_helios(e["price"], false)
		"upgrade":
			if PlayerState.helios < e["price"]:
				return
			if e.get("material") != null and PlayerState.count_of(e["material"]) < e["count"]:
				return
			PlayerState.add_helios(-e["price"], false)
			if e.get("material") != null:
				PlayerState.remove_item(e["material"], e["count"])
			PlayerState.remove_item(e["from"], 1)
			PlayerState.add_item(it, 1)
			PlayerState.equip(it, "weapon")
	Audio.play("pickup")
	_refresh()


## Полная стопка: покупка взяла бы гелиосы, а вещь не добавилась бы (add_item обрезает до max_stack).
func _full(it: ItemData) -> bool:
	return it.max_stack > 1 and PlayerState.count_of(it) >= it.max_stack


## Убрать содержимое сразу (queue_free оставляет старые строки до конца кадра — они задваивались).
func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## Подпись по ширине страницы, с переносом по словам.
func _label(text: String, color: Color, font_size: int) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 176
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _patch(tex: Texture2D, margin: int) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = tex
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		p.set(m, margin)
	return p


func _focus_later(c: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()
