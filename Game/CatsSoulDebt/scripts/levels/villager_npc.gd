extends Npc
## Житель Ивового Брода с побочными квестами (данные — scripts/data/village_quests.gd, тексты — NPC_DRAFTS.md).
## Разговор по порядку: сдать квест (выбор на последнем шаге) → напомнить о текущем → предложить следующий →
## обычные реплики по этапу (до спуска в Рубеж, после, после своего квеста), каждая третья — слух.
## Агата и Ларп (NPC_DRAFTS.md, «Агата и Ларп»): квесты «спустя сутки» (after_days), цикл заказов Ларпа (cycle),
## сдача ночью (finish_night), слухи для «Собора слухов?» (QUEST_RUMORS), алхимический стол («Сварить зелье»),
## лавка по репутации (SHOPS[...].min_rep).

const DATA := preload("res://scripts/data/village_quests.gd")

@export var villager_id: String = ""

var _info: Dictionary
var _idle_i := 0


func _ready() -> void:
	_info = DATA.VILLAGERS.get(villager_id, DATA.MIKA.get(villager_id, {}))
	npc_id = villager_id
	display_name = _info.get("name", villager_id)
	if sheet == null and ResourceLoader.exists(_info.get("sheet", "")):
		sheet = load(_info["sheet"])
		hframes = 4
		vframes = 3
	super()


## Житель только на ночь (night_only, Агата): днём его нет — ни спрайта, ни разговора, ни препятствия.
func _present() -> bool:
	return not _info.get("night_only", false) or _talking or TimeOfDay.is_night()


func prompt_text() -> String:
	return super() if _present() else ""


func can_interact() -> bool:
	return _present() and super()


func _process(delta: float) -> void:
	super(delta)
	var here := _present()
	if here != visible:
		visible = here
		for child in get_children():
			if child is StaticBody3D:
				child.process_mode = Node.PROCESS_MODE_INHERIT if here else Node.PROCESS_MODE_DISABLED


## Разговор: слух по заданию «Собор слухов?» — сразу; у торговца и алхимика — выбор «Поговорить / Торговать /
## Сварить зелье / Уйти» (раньше, пока был открыт его квест, лавка не открывалась вовсе — у Марты и Ильзы до конца
## обоих квестов); «Поговорить» — квесты и обычные реплики.
func talk() -> void:
	PlayerState.take("met:" + villager_id)   # знакомство: книга показывает репутацию только после него
	if _rumor_talk():
		return
	var shop_ok := DATA.SHOPS.has(villager_id) and _shop_allowed()
	var can_brew := _has_table()
	if shop_ok or can_brew:
		var question := _next_line()
		_idle_i += 1   # «Поговорить» без квестов скажет уже следующую реплику, а не ту же
		var labels := PackedStringArray(["Поговорить"])
		var actions: Array[String] = ["talk"]
		if shop_ok:
			labels.append(DATA.SHOPS[villager_id]["talk"])
			actions.append("shop")
		if can_brew:
			labels.append("Сварить зелье")
			actions.append("brew")
		labels.append("Уйти")
		actions.append("leave")
		ask(question, labels, func(i): _do_action(actions[i]))
		return
	if not _quest_talk():
		_idle()


func _do_action(action: String) -> void:
	match action:
		"talk":
			if not _quest_talk():
				_idle()
		"shop":
			open_shop()
		"brew":
			_brew_menu()


## Лавка открыта всегда, кроме тех, где нужна репутация (у Агаты — контрабандистов ≥ 5, после «Поиска черноты»).
func _shop_allowed() -> bool:
	var need: Dictionary = DATA.SHOPS[villager_id].get("min_rep", {})
	for group in need:
		if PlayerState.reputation_of(group) < int(need[group]):
			return false
	return true


## Алхимический стол есть у Ларпа.
func _has_table() -> bool:
	return villager_id == "larp"


## Слух, который этот житель отдаёт заданию «Собор слухов?»: реплики и событие. false — слуха нет.
func _rumor_talk() -> bool:
	var info: Dictionary = DATA.QUEST_RUMORS.get(villager_id, {})
	if info.is_empty() or PlayerState.is_taken("rumor:" + String(info["id"])):
		return false
	var q: String = info["quest"]
	if not QuestState.active.has(q) or QuestState.is_done(q) or not QuestState.waiting_for(q).begins_with("rumors:"):
		return false
	var heard_id: String = info["id"]
	say(PackedStringArray(info["lines"]), func():
		if QuestState.notify_rumor(heard_id):
			var n := PlayerState.taken.filter(func(k): return k.begins_with("rumor:")).size()
			CombatFX.float_text(global_position + Vector3(0, 2.2, 0), "Слух услышан (%d)" % n, Color("e8c870")))
	return true


## Квестовая часть разговора: сдать, напомнить, выдать следующий квест. false — квестовых дел нет.
func _quest_talk() -> bool:
	# Чужой квест, шаг которого — поговорить с этим жителем (Рэй принёс Ларпу вещи Агаты).
	for id in QuestState.active:
		if QuestState.is_done(id) or not DATA.QUESTS.has(id) or DATA.QUESTS[id]["giver"] == villager_id:   # chapter1 — не квест жителя
			continue
		if QuestState.waiting_for(id) == "talk:" + villager_id and DATA.QUESTS[id].get("visits", {}).has(villager_id):
			say(PackedStringArray(DATA.QUESTS[id]["visits"][villager_id]), func(): QuestState.notify("talk:" + villager_id))
			return true
	for id in _quests():
		if not QuestState.active.has(id) or QuestState.is_done(id):
			continue
		var steps: Array = QuestState.steps(id)
		var i: int = QuestState.step(id)
		if steps[i]["event"] == "talk:" + villager_id:
			if i == steps.size() - 1:
				if DATA.QUESTS[id].get("finish_night", false) and not TimeOfDay.is_night():
					say(PackedStringArray(DATA.QUESTS[id].get("wait_lines", DATA.QUESTS[id]["remind"])))
					return true
				_finish(id)
			else:
				say(PackedStringArray(DATA.QUESTS[id]["offer"]), func(): QuestState.notify("talk:" + villager_id))
			return true
		say(PackedStringArray(DATA.QUESTS[id]["remind"]))
		return true
	_reset_cycle()
	for id in _quests():
		if not QuestState.active.has(id) and _available(id):
			QuestState.start(id)
			_give_offer_items(id)
			say(PackedStringArray(DATA.QUESTS[id]["offer"]), func(): QuestState.notify("talk:" + villager_id))
			return true
	return false


## Предметы, которые житель вручает вместе с квестом (свёрток и рецепт Агаты).
func _give_offer_items(id: String) -> void:
	for item_id in DATA.QUESTS[id].get("offer_items", []):
		var item := ContentDB.item(StringName(item_id))
		if item and PlayerState.count_of(item) == 0:
			PlayerState.add_item(item, 1)


## Экран торговли (один на сцену, создаётся при первом открытии).
func open_shop() -> void:
	var scene := get_tree().current_scene
	var shop := scene.get_node_or_null("ShopScreen")
	if shop == null:
		shop = load("res://scripts/ui/shop_screen.gd").new()
		shop.name = "ShopScreen"
		scene.add_child(shop)
	shop.open(villager_id)


## Квесты этого жителя (по порядку в данных).
func _quests() -> Array:
	var out := []
	for id in DATA.QUESTS:
		if DATA.QUESTS[id]["giver"] == villager_id:
			out.append(id)
	return out


## Следующий квест жителя — после того, как предыдущие его квесты сданы (и после after_days игровых суток).
func _available(id: String) -> bool:
	var prev := ""
	for other in _quests():
		if other == id:
			break
		if not QuestState.is_done(other):
			return false
		prev = other
	var days: int = DATA.QUESTS[id].get("after_days", 0)
	if days > 0 and prev != "" and TimeOfDay.day < int(PlayerState.quest_days.get(prev, TimeOfDay.day - days)) + days:
		return false
	return true


## Цикл заказов (cycle): все заказы сданы и прошли сутки — начать круг заново.
func _reset_cycle() -> void:
	var all := _quests().filter(func(q): return DATA.QUESTS[q].get("cycle", false))
	if all.is_empty() or all.size() != _quests().size():
		return
	for q in all:
		if not QuestState.is_done(q):
			return
	var last: int = int(PlayerState.quest_days.get(all[all.size() - 1], TimeOfDay.day - 1))
	if TimeOfDay.day < last + int(DATA.QUESTS[all[0]].get("after_days", 1)):
		return
	for q in all:
		QuestState.active.erase(q)
		PlayerState.quest_days.erase(q)
	QuestState.changed.emit()


## Следующий квест уже можно взять, но ждёт новых суток (заказ Ларпа сдан сегодня).
func _blocked_by_day() -> bool:
	_reset_cycle()
	for id in _quests():
		if QuestState.active.has(id):
			continue
		if _available(id):
			return false
		return DATA.QUESTS[id].get("after_days", 0) > 0
	return false


## Реплика по этапу (без показа) — для вопроса «Торговать / Поговорить».
func _next_line() -> String:
	var pool: Array = _info.get(_stage(), ["…"])
	return pool[_idle_i % pool.size()].get_slice("|", 0)


func _stage() -> String:
	var stage := "first"
	for id in _quests() + ([_info["late_after"]] if _info.has("late_after") else []):
		if QuestState.active.has(id) and QuestState.is_done(id):
			stage = "late"
	if stage == "first" and QuestState.active.has("chapter1") and QuestState.step("chapter1") >= 2:
		stage = "after"
	return stage


func _idle() -> void:
	if _info.has("wait_day") and _blocked_by_day():
		say(PackedStringArray([_info["wait_day"][_idle_i % _info["wait_day"].size()]]))
		_idle_i += 1
		return
	var pool: Array = _info.get(_stage(), ["…"])
	var line: String = pool[_idle_i % pool.size()]
	if _idle_i % 3 == 2 and not _info.get("rumors", []).is_empty():
		var rumors: Array = _info["rumors"]
		line = "Слыхал? " + rumors[int(_idle_i / 3.0) % rumors.size()]
	_idle_i += 1
	say(line.split("|"))  # «|» в реплике — продолжение в следующем окне


## Сдача квеста: выбор (что отдать) или реакция по флагу находки; награда и событие «talk:<житель>».
func _finish(id: String) -> void:
	var fin: Dictionary = DATA.QUESTS[id]["finish"]
	if fin.has("flag"):
		var branch: Dictionary = fin["if_flag"] if PlayerState.is_taken(fin["flag"]) else fin["else"]
		if not _has_all(branch.get("give", [])):
			say(PackedStringArray(DATA.QUESTS[id]["remind"]))
			return
		_apply(id, branch, -1)
		return
	var options: Array = []
	var numbers: Array[int] = []   # номер варианта в данных: флаг «quest:<id>:<n>» — по нему, а не по показанному
	var labels := PackedStringArray()
	var all: Array = fin["options"]
	for n in all.size():
		if _has_all(all[n]["give"]):
			options.append(all[n])
			numbers.append(n)
			labels.append(all[n]["label"])
	if options.is_empty():
		say(PackedStringArray(DATA.QUESTS[id]["remind"]))
		return
	# Один вариант без вопроса (auto): сдача сразу — награды Агаты и заказы Ларпа.
	if fin.get("auto", false) and options.size() == 1:
		_apply(id, options[0], numbers[0])
		return
	ask(fin["ask"], labels, func(i): _apply(id, options[i], numbers[i]))


func _has_all(items: Array) -> bool:
	for item_id in items:
		var item := ContentDB.item(StringName(item_id))
		if item == null or PlayerState.count_of(item) == 0:
			return false
	return true


func _apply(id: String, branch: Dictionary, choice: int) -> void:
	for item_id in branch.get("give", []):
		PlayerState.remove_item(ContentDB.item(StringName(item_id)), 1)
	var reward: Dictionary = branch.get("reward", {})
	if reward.get("helios", 0) > 0:
		PlayerState.add_helios(reward["helios"], false)
	for item_id in reward.get("items", []):
		PlayerState.add_item(ContentDB.item(StringName(item_id)), 1)
	var rep: Dictionary = reward.get("rep", {})
	for group in rep:
		PlayerState.add_reputation(group, int(rep[group]))
	PlayerState.quest_days[id] = TimeOfDay.day
	PlayerState.take("quest:%s:%d" % [id, choice])
	# Шаг закрывается сразу, вместе с наградой: сохранение посреди заключительных реплик не оставит квест
	# с отданными вещами, но несданным.
	QuestState.notify("talk:" + villager_id)
	say(PackedStringArray(branch.get("lines", [])))


# --- Алхимический стол Ларпа ---------------------------------------------------

## Рецепты, на которые хватает ингредиентов (рецепт квеста — только пока квест взят и не сдан).
func _brewable() -> Array:
	var out := []
	for rid in DATA.RECIPES:
		var recipe: Dictionary = DATA.RECIPES[rid]
		var q: String = recipe.get("needs_quest", "")
		if q != "" and QuestState.waiting_for(q) != "brew:" + rid:   # раньше шага варка тратила вещи впустую — квест застревал
			continue
		if _has_all(recipe["inputs"]):
			out.append(rid)
	return out


func _brew_menu() -> void:
	var ids := _brewable()
	if ids.is_empty():
		say(PackedStringArray(["Стол свободен, а вот ингредиентов не хватает. Приноси: часть продаю я, часть — Марта и лес.",
			"Рецепты у меня простые: три ингредиента на зелье. Список лежит на столе (и в моей голове)."]))
		return
	var labels := PackedStringArray()
	for rid in ids:
		var names: PackedStringArray = []
		for item_id in DATA.RECIPES[rid]["inputs"]:
			names.append(ContentDB.item(StringName(item_id)).name)
		labels.append("%s (%s)" % [DATA.RECIPES[rid]["name"], ", ".join(names)])
	labels.append("Передумал")
	ask("Что варим?", labels, func(i):
		if i < ids.size():
			brew(ids[i]))


## Сварить зелье: расходует ингредиенты, выдаёт склянки, событие «brew:<рецепт>». false — не хватает ингредиентов.
func brew(recipe_id: String) -> bool:
	var recipe: Dictionary = DATA.RECIPES.get(recipe_id, {})
	if recipe.is_empty() or not _has_all(recipe["inputs"]):
		return false
	for item_id in recipe["inputs"]:
		PlayerState.remove_item(ContentDB.item(StringName(item_id)), 1)
	PlayerState.add_item(ContentDB.item(StringName(recipe["output"])), int(recipe["count"]))
	QuestState.notify("brew:" + recipe_id)
	var lines: Array = recipe.get("lines", ["(Ларп помешивает, считает капли, шепчет что-то про меру и вес.)",
		"Готово! Две склянки: одну сдашь, вторую оставишь себе. Не пей натощак."])
	say(PackedStringArray(lines))
	return true
