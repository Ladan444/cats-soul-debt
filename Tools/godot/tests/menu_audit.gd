extends SceneTree
## Аудит переходов между меню: все пути открытия/закрытия из всех состояний.
## После каждого шага проверяет паузу, видимость окон, владельца фокуса и вылезающий за панели текст.

var HEADLESS := DisplayServer.get_name() == "headless"
var fails: Array[String] = []
var _potion: Resource
var steps := 0
var scene: Node
var book: CanvasLayer
var pause: CanvasLayer
var settings: Control


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var st := root.get_node("Settings")
	var original_scale = st.get_value("ui_scale")
	# В headless размер окна не меняется (1920×1080); разные холсты проверяем масштабом ×2/×3/×4.
	for ui_scale in [2, 3, 4]:
		st.set_value("ui_scale", ui_scale)
		await _main_menu_suite("x%d" % ui_scale)
		await _game_suite("x%d" % ui_scale)
	st.set_value("ui_scale", original_scale)
	st.save_settings()
	print("\n=== ШАГОВ: %d, ОШИБОК: %d ===" % [steps, fails.size()])
	for f in fails:
		print("FAIL ", f)
	quit(1 if fails.size() > 0 else 0)


# --- Ввод -----------------------------------------------------------------------

func key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		root.push_input(e)
	await frames(3)


func pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		root.push_input(e)
	await frames(3)


func click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.global_position = at
		e.pressed = pressed
		root.push_input(e)
	await frames(3)


func press(button: BaseButton) -> void:
	if button == null:
		fails.append("кнопка не найдена")
		return
	button.pressed.emit()
	await frames(3)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func find_button(where: Node, text: String) -> BaseButton:
	for b in where.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text == text:
			return b
	return null


func find_by_class(where: Node, cls: String) -> Node:
	for n in where.find_children("*", "", true, false):
		var s: Script = n.get_script()
		if s and s.get_global_name() == cls and n is CanvasItem and n.is_visible_in_tree():
			return n
	return null


# --- Проверки -------------------------------------------------------------------

## expect: paused, book, pause, settings — ожидаемое состояние; focus_in — где должен быть фокус (или null — любой/никакой).
func check(tag: String, expect: Dictionary, focus_in: Node = null) -> void:
	steps += 1
	if expect.has("paused") and paused != expect["paused"]:
		fails.append("%s: paused=%s, ждали %s" % [tag, paused, expect["paused"]])
	var actual := {"book": book.visible, "pause": pause.visible and pause._panel.visible,
		"settings": settings.is_visible_in_tree()}
	for k in actual:
		if expect.has(k) and actual[k] != expect[k]:
			fails.append("%s: %s visible=%s, ждали %s" % [tag, k, actual[k], expect[k]])
	var owner := root.gui_get_focus_owner()
	if owner and not owner.is_visible_in_tree():
		fails.append("%s: фокус на невидимом %s" % [tag, owner.get_path()])
	if focus_in:
		if owner == null:
			fails.append("%s: нет фокуса (ждали внутри %s)" % [tag, focus_in.name])
		elif not focus_in.is_ancestor_of(owner):
			fails.append("%s: фокус на %s, ждали внутри %s" % [tag, owner.get_path(), focus_in.name])
	_check_overflow(tag)


## Текст и кнопки не вылезают за свою панель (NinePatchRect), а по ширине — и за прокрутку; панели — за экран.
func _check_overflow(tag: String) -> void:
	var screen := root.get_visible_rect()
	for c in root.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree():
			continue
		if c is NinePatchRect and c.get_parent() is Control and not (c.get_parent() is NinePatchRect):
			var r: Rect2 = c.get_global_rect()
			if not screen.grow(1).encloses(r):
				fails.append("%s: панель %s за экраном %s > %s" % [tag, c.get_path(), r, screen.size])
		if not (c is Label or c is Button):
			continue
		var r: Rect2 = c.get_global_rect()
		var p := c.get_parent()
		while p and not (p is NinePatchRect or p is ScrollContainer):
			p = p.get_parent()
		if p == null or not (p is Control):
			continue
		var cr: Rect2 = p.get_global_rect().grow(0.5)
		var ok := r.position.x >= cr.position.x and r.end.x <= cr.end.x
		if p is NinePatchRect:
			ok = ok and r.position.y >= cr.position.y and r.end.y <= cr.end.y
		if not ok:
			var t: String = c.text if "text" in c else ""
			fails.append("%s: «%s» (%s) вылезает из %s: %s vs %s" % [tag, t.left(30), c.name, p.name, r, cr])


# --- Главное меню ------------------------------------------------------------------

func _main_menu_suite(res: String) -> void:
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await frames(5)
	scene = current_scene
	paused = false
	var candidates: Array = [scene] + scene.find_children("*", "Control", true, false)
	var menu: Control = candidates.filter(func(n): return n.get_script() and n.get_script().resource_path.ends_with("main_menu.gd"))[0]
	settings = menu._settings
	var list: Control = menu._menu
	var t := "главное меню " + res
	_mm_check(t + ": старт", menu, list)

	await press(find_button(list, "Новая игра"))
	_mm_check(t + ": сложность", menu, menu._difficulty)
	await key(KEY_ESCAPE)
	_mm_check(t + ": сложность→Esc", menu, list)
	await press(find_button(list, "Новая игра"))
	await press(find_by_class(menu._difficulty, "CloseButton"))
	_mm_check(t + ": сложность→крестик", menu, list)
	await press(find_button(list, "Новая игра"))
	await pad(JOY_BUTTON_B)
	_mm_check(t + ": сложность→B", menu, list)

	await press(find_button(list, "Авторы"))
	_mm_check(t + ": авторы", menu, menu._credits)
	await key(KEY_ESCAPE)
	_mm_check(t + ": авторы→Esc", menu, list)
	await press(find_button(list, "Авторы"))
	await press(find_button(menu._credits, "Назад"))
	_mm_check(t + ": авторы→Назад", menu, list)
	await press(find_button(list, "Авторы"))
	await press(find_by_class(menu._credits, "CloseButton"))
	_mm_check(t + ": авторы→крестик", menu, list)

	await press(find_button(list, "Настройки"))
	for i in 4:
		_mm_check(t + ": настройки вкладка %d" % i, menu, settings)
		await key(KEY_E)
	await key(KEY_Q)
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	await key(KEY_ESCAPE)
	_mm_check(t + ": настройки→Esc", menu, list)
	await press(find_button(list, "Настройки"))
	await press(find_by_class(settings, "CloseButton"))
	_mm_check(t + ": настройки→крестик", menu, list)
	await press(find_button(list, "Настройки"))
	await pad(JOY_BUTTON_B)
	_mm_check(t + ": настройки→B", menu, list)
	# Esc в самом меню ничего не ломает.
	await key(KEY_ESCAPE)
	_mm_check(t + ": Esc в меню", menu, list)


func _mm_check(tag: String, menu: Control, focus_in: Control) -> void:
	steps += 1
	for pair in [["list", menu._menu], ["difficulty", menu._difficulty], ["credits", menu._credits], ["settings", settings]]:
		var should: bool = pair[1] == focus_in or (focus_in == null and pair[0] == "list")
		if pair[1].visible != should:
			fails.append("%s: %s visible=%s, ждали %s" % [tag, pair[0], pair[1].visible, should])
	var owner := root.gui_get_focus_owner()
	if owner == null:
		fails.append("%s: нет фокуса" % tag)
	elif not owner.is_visible_in_tree():
		fails.append("%s: фокус на невидимом %s" % [tag, owner.name])
	elif not focus_in.is_ancestor_of(owner):
		fails.append("%s: фокус на %s, ждали внутри %s" % [tag, owner.get_path(), focus_in.name])
	_check_overflow(tag)


# --- Игра ---------------------------------------------------------------------------

func _game_suite(res: String) -> void:
	change_scene_to_file("res://tests/test_arena.tscn")
	await frames(5)
	scene = current_scene
	paused = false
	book = scene.get_node("Book")
	pause = scene.get_node("PauseMenu")
	settings = pause._settings
	var ps := root.get_node("PlayerState")
	var t := "игра " + res
	var none := {"paused": false, "book": false, "pause": false, "settings": false}
	var in_book := {"paused": true, "book": true, "pause": false, "settings": false}
	var in_pause := {"paused": true, "book": false, "pause": true, "settings": false}
	var in_settings := {"paused": true, "book": false, "pause": false, "settings": true}
	check(t + ": старт", none)

	# Книга с клавиатуры: Tab, все 8 закладок по E и по Q, повторный Tab закрывает.
	await key(KEY_TAB)
	check(t + ": Tab", in_book, book)
	for i in 8:
		await key(KEY_E)
		check(t + ": E→закладка %d" % book.section, in_book)
	if book.section != 0:
		fails.append("%s: 8×E не вернули на 0, а на %d" % [t, book.section])
	for i in 8:
		await key(KEY_Q)
		check(t + ": Q→закладка %d" % book.section, in_book)
	await key(KEY_TAB)
	check(t + ": Tab закрыл", none)
	await key(KEY_I)
	check(t + ": I", in_book, book)
	await key(KEY_I)
	check(t + ": I закрыл", none)

	# Карта: M открывает карту места во весь экран (книга закрыта), M закрывает; из открытой книги M — на карту.
	var in_map := {"paused": true, "book": false, "pause": false, "settings": false}
	await key(KEY_M)
	check(t + ": M — карта", in_map)
	if not book.is_map_open():
		fails.append("%s: M не открыл карту" % t)
	await key(KEY_M)
	check(t + ": M закрыл карту", none)
	await key(KEY_TAB)
	await key(KEY_M)
	check(t + ": Tab→M — карта", in_map)
	if not book.is_map_open():
		fails.append("%s: M из книги не открыл карту" % t)
	await key(KEY_ESCAPE)
	check(t + ": Esc закрыл карту", none)

	# Геймпад: View открывает, RB/LB листают, B закрывает.
	await pad(JOY_BUTTON_BACK)
	check(t + ": View", in_book, book)
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	await pad(JOY_BUTTON_LEFT_SHOULDER)
	await pad(JOY_BUTTON_LEFT_SHOULDER)
	check(t + ": LB/RB", in_book)
	await pad(JOY_BUTTON_START)
	check(t + ": Start в книге — пауза не лезет", in_book)
	await pad(JOY_BUTTON_B)
	check(t + ": B закрыл", none)
	await key(KEY_TAB)  # вернуть клавиатуру
	await key(KEY_TAB)

	# Крестик и касание мимо книги.
	await key(KEY_TAB)
	await press(find_by_class(book, "CloseButton"))
	check(t + ": крестик книги", none)
	await key(KEY_TAB)
	await click(Vector2(2, root.get_visible_rect().size.y / 2.0))
	if HEADLESS and book.visible:
		# В headless мышь не доходит до GUI — шлём событие прямо в затемнение.
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = true
		book.get_child(0).gui_input.emit(e)
		await frames(2)
	check(t + ": клик мимо книги", none)

	# Режим назначения в хотбар: Esc сначала отменяет назначение, книга остаётся.
	await key(KEY_TAB)
	book.show_section(1)
	await frames(2)
	var potion: Resource = null
	for e in ps.inventory:
		if e["item"].category == 1:  # CONSUMABLE
			potion = e["item"]
	if potion:
		_potion = potion
	elif _potion:  # прошлые прогоны выпили все зелья кликами по хотбару
		ps.add_item(_potion, 3)
		potion = _potion
		await frames(2)
	if potion:
		book._character._start_assign(potion)
		await frames(2)
		check(t + ": назначение", in_book, book)
		await key(KEY_ESCAPE)
		check(t + ": назначение→Esc отменяет", in_book, book)
		if book._character._assigning != null:
			fails.append("%s: назначение не отменилось" % t)
		book._character._start_assign(potion)
		await key(KEY_E)
		check(t + ": назначение→E", in_book)
		if book._character._assigning != null:
			fails.append("%s: назначение пережило смену закладки" % t)
		book.show_section(1)
		book._character._start_assign(potion)
		await key(KEY_TAB)
		check(t + ": назначение→Tab закрыл", none)
	else:
		fails.append("%s: нет зелья для проверки назначения" % t)

	# Ссылка «В журнале» из «Ключевого».
	await key(KEY_TAB)
	book.show_section(3)
	await frames(2)
	var link := find_button(book, "В журнале")
	if link and not link.disabled:
		await press(link)
		check(t + ": ключевое→журнал", in_book, book)
		if book.section != 4:
			fails.append("%s: ссылка открыла раздел %d" % [t, book.section])
	await key(KEY_ESCAPE)
	check(t + ": журнал→Esc", none)

	# Пауза: Esc / Start, крестик, «Продолжить».
	await key(KEY_ESCAPE)
	check(t + ": Esc→пауза", in_pause, pause)
	await key(KEY_ESCAPE)
	check(t + ": пауза→Esc", none)
	await pad(JOY_BUTTON_START)
	check(t + ": Start→пауза", in_pause, pause)
	await pad(JOY_BUTTON_B)
	check(t + ": пауза→B", none)
	await key(KEY_ESCAPE)
	await press(find_by_class(pause, "CloseButton"))
	check(t + ": пауза→крестик", none)
	await key(KEY_ESCAPE)
	await press(find_button(pause, "Продолжить"))
	check(t + ": пауза→Продолжить", none)

	# Пауза: клавиши книги не открывают её поверх паузы.
	await key(KEY_ESCAPE)
	await key(KEY_TAB)
	check(t + ": пауза+Tab", in_pause)
	await key(KEY_M)
	check(t + ": пауза+M", in_pause)

	# Пауза → Персонаж / Журнал → Esc.
	await press(find_button(pause, "Персонаж"))
	check(t + ": пауза→Персонаж", in_book, book)
	if book.section >= 4:
		fails.append("%s: «Персонаж» открыл журнал" % t)
	await key(KEY_ESCAPE)
	check(t + ": Персонаж→Esc", none)
	await key(KEY_ESCAPE)
	await press(find_button(pause, "Журнал"))
	check(t + ": пауза→Журнал", in_book)
	if book.section < 4:
		fails.append("%s: «Журнал» открыл Рэя" % t)
	await key(KEY_M)
	check(t + ": Журнал→M — карта", {"paused": true, "book": false, "pause": false, "settings": false})
	if not book.is_map_open():
		fails.append("%s: M из журнала не открыл карту" % t)
	await key(KEY_ESCAPE)
	check(t + ": карта→Esc", none)

	# Пауза → Карта (с геймпада карта открывается только так) → Esc.
	await key(KEY_ESCAPE)
	await press(find_button(pause, "Карта"))
	if not book.is_map_open():
		fails.append("%s: «Карта» в паузе не открыла карту" % t)
	await key(KEY_ESCAPE)
	check(t + ": пауза→Карта→Esc", none)

	# Пауза → Настройки → вкладки → Esc / крестик / B / Назад.
	await key(KEY_ESCAPE)
	await press(find_button(pause, "Настройки"))
	check(t + ": пауза→настройки", in_settings, settings)
	for i in 4:
		await key(KEY_E)
		check(t + ": настройки E %d" % i, in_settings)
	await key(KEY_TAB)
	check(t + ": настройки+Tab", in_settings)
	await key(KEY_M)
	check(t + ": настройки+M", in_settings)
	await key(KEY_ESCAPE)
	check(t + ": настройки→Esc", in_pause, pause)
	await press(find_button(pause, "Настройки"))
	await press(find_by_class(settings, "CloseButton"))
	check(t + ": настройки→крестик", in_pause, pause)
	await press(find_button(pause, "Настройки"))
	await pad(JOY_BUTTON_B)
	check(t + ": настройки→B", in_pause, pause)
	await press(find_button(pause, "Настройки"))
	await pad(JOY_BUTTON_START)
	check(t + ": настройки→Start (пауза не закрывается под настройками)", in_settings)
	await press(find_button(settings, "Назад"))
	check(t + ": настройки→Назад", in_pause, pause)
	await key(KEY_ESCAPE)
	check(t + ": выход из паузы", none)

	# Кнопки HUD и хотбар мышью/касанием.
	var hud := scene.get_node("HUD/UIScaler/HUD")
	await press(hud.get_node("MenuButtons/BookButton"))
	check(t + ": HUD Книга", in_book, book)
	await key(KEY_ESCAPE)
	await press(hud.get_node("MenuButtons/MapButton"))
	check(t + ": HUD Карта", {"paused": true, "book": false, "pause": false, "settings": false})
	if not book.is_map_open():
		fails.append("%s: HUD Карта не открыла карту" % t)
	await press(hud.get_node("MenuButtons/BookButton"))
	check(t + ": HUD Книга при открытой карте — пауза, кнопка не срабатывает", {"paused": true, "book": false})
	await key(KEY_ESCAPE)
	await press(hud.get_node("MenuButtons/MenuButton"))
	check(t + ": HUD Меню", in_pause, pause)
	await key(KEY_ESCAPE)
	var used := [0]
	ps.item_used.connect(func(_i): used[0] += 1)
	ps.skill_used.connect(func(_i): used[0] += 1)
	for i in 4:
		hud.get_node("Hotbar/Item%d" % i).pressed.emit()
		hud.get_node("Hotbar/Skill%d" % i).pressed.emit()
	await frames(2)
	print("%s: срабатываний хотбара по клику: %d" % [t, used[0]])
	check(t + ": после хотбара", none)
	# Реальный клик по ячейке предмета через GUI.
	var slot: Control = hud.get_node("Hotbar/Item0")
	# Из таверны (хаб, хотбар спрятан) — в Каменный Рубеж.
	scene.get_node("Player").global_position = Vector3(0, 0, 0)
	await frames(60)
	var raw := [0]
	slot.pressed.connect(func(): raw[0] += 1)
	await click(slot.get_global_rect().get_center())
	print("%s: реальный клик по Item0: сигнал %d, clickable=%s, хаб=%s" % [t, raw[0], slot.clickable, hud._hub])
	if not HEADLESS and slot.clickable and raw[0] == 0:
		fails.append("%s: клик мышью по ячейке хотбара не дошёл" % t)
