extends Npc
## Житель Ивового Брода с побочными квестами (данные — scripts/data/village_quests.gd, тексты — NPC_DRAFTS.md).
## Разговор по порядку: сдать квест (выбор на последнем шаге) → напомнить о текущем → предложить следующий →
## обычные реплики по этапу (до спуска в Рубеж, после, после своего квеста), каждая третья — слух.

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


## У торговца сначала выбор «Поговорить / Торговать / Уйти» (раньше, пока был открыт его квест, лавка не
## открывалась вовсе — у Марты и Ильзы до конца обоих квестов); «Поговорить» — квесты и обычные реплики.
func talk() -> void:
	if DATA.SHOPS.has(villager_id):
		var question := _next_line()
		_idle_i += 1   # «Поговорить» без квестов скажет уже следующую реплику, а не ту же
		ask(question, PackedStringArray(["Поговорить", DATA.SHOPS[villager_id]["talk"], "Уйти"]), func(i):
			if i == 0 and not _quest_talk():
				_idle()
			elif i == 1:
				open_shop())
		return
	if not _quest_talk():
		_idle()


## Квестовая часть разговора: сдать, напомнить, выдать следующий квест. false — квестовых дел нет.
func _quest_talk() -> bool:
	for id in _quests():
		if not QuestState.active.has(id) or QuestState.is_done(id):
			continue
		var steps: Array = QuestState.steps(id)
		var i: int = QuestState.step(id)
		if steps[i]["event"] == "talk:" + villager_id:
			if i == steps.size() - 1:
				_finish(id)
			else:
				say(PackedStringArray(DATA.QUESTS[id]["offer"]), func(): QuestState.notify("talk:" + villager_id))
			return true
		say(PackedStringArray(DATA.QUESTS[id]["remind"]))
		return true
	for id in _quests():
		if not QuestState.active.has(id) and _available(id):
			QuestState.start(id)
			say(PackedStringArray(DATA.QUESTS[id]["offer"]), func(): QuestState.notify("talk:" + villager_id))
			return true
	return false


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


## Следующий квест жителя — после того, как предыдущие его квесты сданы.
func _available(id: String) -> bool:
	for other in _quests():
		if other == id:
			return true
		if not QuestState.is_done(other):
			return false
	return true


## Реплика по этапу (без показа) — для вопроса «Торговать / Поговорить».
func _next_line() -> String:
	var pool: Array = _info.get(_stage(), ["…"])
	return pool[_idle_i % pool.size()]


func _stage() -> String:
	var stage := "first"
	for id in _quests() + ([_info["late_after"]] if _info.has("late_after") else []):
		if QuestState.active.has(id) and QuestState.is_done(id):
			stage = "late"
	if stage == "first" and QuestState.active.has("chapter1") and QuestState.step("chapter1") >= 2:
		stage = "after"
	return stage


func _idle() -> void:
	var pool: Array = _info.get(_stage(), ["…"])
	var line: String = pool[_idle_i % pool.size()]
	if _idle_i % 3 == 2 and not _info.get("rumors", []).is_empty():
		var rumors: Array = _info["rumors"]
		line = "Слыхал? " + rumors[int(_idle_i / 3.0) % rumors.size()]
	_idle_i += 1
	say(PackedStringArray([line]))


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
	PlayerState.take("quest:%s:%d" % [id, choice])
	# Шаг закрывается сразу, вместе с наградой: сохранение посреди заключительных реплик не оставит квест
	# с отданными вещами, но несданным.
	QuestState.notify("talk:" + villager_id)
	say(PackedStringArray(branch.get("lines", [])))
