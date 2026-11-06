extends Node
## Автозагрузка QuestState: задания и их шаги. Пока минимальная основа (для мастер-меню отладки);
## сюжетные задания пишутся вместе с автором и вносятся в CANON.md.
## Шаг закрывается сам по событию (notify) или вручную (complete_step). Сохраняется в SaveGame (ключ «quests»).

signal changed

## Задания: id → название и шаги. Шаг: текст и событие, которое его закрывает:
## «scene:<имя файла сцены>», «lantern_lit», «talk:<кто>», «item:<id предмета>», «soul», «place:<место>», «chapter_end».
## Глава 1 — по сценарию Литература/CHAPTER1.md (черновик, правит автор).
const QUESTS := {
	"chapter1": {
		"title": "Глава 1. Долг",
		"steps": [
			{"text": "Поговорить с графом у стойки таверны", "event": "talk:velmor"},
			{"text": "Принести знамя третьей роты из казармы Рубежа", "event": "item:banner_third_company"},
			{"text": "Отдать знамя графу", "event": "talk:velmor"},
			{"text": "Найти в Рубеже душу павшего товарища", "event": "soul"},
			{"text": "Вернуться к графу", "event": "talk:velmor"},
			{"text": "Собрать ключ сокровищницы и забрать шкатулку графа", "event": "item:velmor_casket"},
			{"text": "Отнести шкатулку графу", "event": "talk:velmor"},
			{"text": "Прийти в Большой зал Рубежа, к кругу печати", "event": "place:great_hall"},
			{"text": "…", "event": "chapter_end"},
		],
	},
}

## Все задания: сюжетные (QUESTS) + побочные квесты жителей (scripts/data/village_quests.gd).
var defs: Dictionary = {}
## id → индекс текущего шага (равен числу шагов — задание выполнено).
var active: Dictionary = {}
var _scene: String = ""


func _ready() -> void:
	defs = QUESTS.duplicate(true)
	var village: Dictionary = load("res://scripts/data/village_quests.gd").QUESTS
	for id in village:
		defs[id] = village[id]
	PlayerState.lantern_lit.connect(func(_key): notify("lantern_lit"))


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	var path := scene.scene_file_path if scene else ""
	if path != _scene:
		_scene = path
		if path != "":
			notify("scene:" + path.get_file().get_basename())


func reset() -> void:
	active.clear()
	changed.emit()


func start(id: String) -> void:
	if defs.has(id) and not active.has(id):
		active[id] = 0
		_settle(id)
		changed.emit()


func steps(id: String) -> Array:
	return defs[id]["steps"]


func title(id: String) -> String:
	return defs[id]["title"]


func is_done(id: String) -> bool:
	return active.get(id, 0) >= steps(id).size()


## Номер текущего шага (-1 — задание не начато).
func step(id: String) -> int:
	return active.get(id, -1)


## Текущее событие-ожидание задания («talk:velmor»…) — для подсказок и реплик.
func waiting_for(id: String) -> String:
	if not active.has(id) or is_done(id):
		return ""
	return steps(id)[active[id]]["event"]


func current_step_text(id: String) -> String:
	return "выполнено" if is_done(id) else steps(id)[active[id]]["text"]


func complete_step(id: String) -> void:
	if active.has(id) and not is_done(id):
		active[id] += 1
		_settle(id)
		changed.emit()


## Шаги «принести вещь» и «найти душу» закрываются и задним числом: игрок мог найти вещь раньше,
## чем задание её попросило (подобрал знамя до разговора с графом, шкатулку — до поручения).
## Событие тогда уже прошло, и без этой проверки задание застряло бы навсегда.
func _settle(id: String) -> void:
	while not is_done(id):
		var event: String = steps(id)[active[id]]["event"]
		var have := false
		if event.begins_with("item:"):
			var item := ContentDB.item(StringName(event.trim_prefix("item:")))
			have = item != null and PlayerState.count_of(item) > 0
		elif event == "soul":
			have = not PlayerState.souls.is_empty()
		if not have:
			return
		active[id] += 1


func reset_quest(id: String) -> void:
	if active.has(id):
		active[id] = 0
		changed.emit()


## Событие игры: закрывает текущий шаг каждого задания, который его ждёт.
func notify(event: String) -> void:
	for id in active:
		if not is_done(id) and steps(id)[active[id]]["event"] == event:
			complete_step(id)


## Услышан слух: засчитывается, только пока какое-то задание собирает слухи (шаг «rumors:<сколько>»), по разу.
func notify_rumor(rumor_id: String) -> bool:
	var key := "rumor:" + rumor_id
	if PlayerState.is_taken(key):
		return false
	var waiting := false
	for id in active:
		if not is_done(id) and String(steps(id)[active[id]]["event"]).begins_with("rumors:"):
			waiting = true
	if not waiting:
		return false
	PlayerState.take(key)
	var heard := PlayerState.taken.filter(func(k): return k.begins_with("rumor:")).size()
	for id in active.keys():
		if not is_done(id):
			var event := String(steps(id)[active[id]]["event"])
			if event.begins_with("rumors:") and heard >= int(event.trim_prefix("rumors:")):
				complete_step(id)
	return true


## Вещь нужна, чтобы сдать взятый квест (finish → give): её нельзя выбросить или продать — иначе квест не сдать,
## а находка уже не вернётся (звёздный мох Марты: выбросил — квест и вторая лавка навсегда закрыты).
func needs_item(item_id: String) -> bool:
	for id in active:
		if is_done(id):
			continue
		var fin: Dictionary = defs.get(id, {}).get("finish", {})
		for branch in fin.get("options", []) + [fin.get("if_flag", {}), fin.get("else", {})]:
			if item_id in branch.get("give", []):
				return true
	return false


func to_dict() -> Dictionary:
	return {"active": active.duplicate()}


func from_dict(d: Dictionary) -> void:
	active.clear()
	var a: Dictionary = d.get("active", {})
	for id in a:
		if defs.has(id):
			active[id] = int(a[id])
			_settle(id)
	changed.emit()
