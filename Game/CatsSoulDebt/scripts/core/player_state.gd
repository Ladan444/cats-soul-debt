extends Node
## Состояние Рэя (автозагрузка PlayerState): здоровье, энергия души, отметки смерти, гелиосы,
## инвентарь, экипировка, души и хотбар. HUD и меню только читают его и подписываются на сигналы.
## Правила — CANON.md и UI_SPEC.md.

signal hp_changed(hp: float, max_hp: float)
signal energy_changed(energy: float, max_energy: float)
signal deaths_changed(deaths: int)
signal helios_changed(helios: int, delta: int)
signal died(death_number: int, lost_helios: int)
## После девятой смерти за спуск Рэя выбрасывает на Перепутье.
signal crossroads_reached
## Не хватило энергии души на действие.
signal energy_denied
signal skill_used(index: int)
signal item_used(index: int)
signal eating_started(item: ItemData)
signal eating_cancelled
## Изменились инвентарь, экипировка, души или хотбар.
signal items_changed
signal stats_changed
signal lantern_lit(key: String)

## Мастер-меню отладки (Cheats): бессмертие — урон не проходит.
var god_mode: bool = false

const MAX_DEATHS := 9
## Доля гелиосов спуска, теряемая за смерть, по сложности (решение автора).
const LOSS_BY_DIFFICULTY := [0.5, 0.75, 0.9]
## Доля потерянного, которая остаётся лежать на месте смерти — случайная в этих пределах (решение автора).
const DROP_SHARE_MIN := 0.35
const DROP_SHARE_MAX := 0.75
const BASE_HP := 100.0
const BASE_ENERGY := 100.0
const BASE_DAMAGE := 0.0
## Слоты экипировки: оружие, плащ, доспех, амулет, две реликвии (UI_SPEC, раздел 3).
const EQUIP_SLOTS := ["weapon", "cloak", "armor", "amulet", "relic_1", "relic_2"]
const EQUIP_SLOT_NAMES := ["Оружие", "Плащ", "Доспех", "Амулет", "Реликвия", "Реликвия"]

## Стартовый набор новой игры (демо-содержимое, res://data/).
const START_INVENTORY := {
	"sword_garrison": 1, "cloak_garrison": 1, "armor_leather": 1, "amulet_lake_stone": 1,
	"relic_patch": 1, "relic_whetstone": 1, "tincture_liara": 3, "marsh_herb": 5,
	"note_unsigned": 1,
}
const START_EQUIPMENT := {"weapon": "sword_garrison", "cloak": "cloak_garrison"}
## Глава 1 (CHAPTER1.md): Рэй начинает без душ — силы приходят с именными душами, найденными в Рубеже.
const START_SOULS := []
const START_HOTBAR_SKILLS := ["", "", "", ""]
const START_HOTBAR_ITEMS := ["tincture_liara", "", "", ""]

## Восстановление энергии в секунду и задержка перед ним после траты.
@export var energy_regen: float = 14.0
@export var energy_regen_delay: float = 0.8

var max_hp: float = BASE_HP
var max_energy: float = BASE_ENERGY
var damage_bonus: float = BASE_DAMAGE
var defense: float = 0.0
var hp: float
var energy: float
## Еда, которую Рэй сейчас ест (start_use), иначе null.
var eating: ItemData
var deaths: int = 0
var helios: int = 0
## Гелиосы, найденные в текущем спуске: только они теряются при смерти.
var run_helios: int = 0
var difficulty: int = 1
## Отметки смертей этого спуска для карты журнала: {"pos": Vector3, "number": int, "helios": int, "scene": String}.
## helios — сколько утерянных гелиосов ещё лежит на месте (0 — подобраны).
var death_marks: Array[Dictionary] = []
## Зажжённые фонари душ ("сцена:имя узла") и тот, у которого Рэй возрождается.
var lit_lanterns: Array[String] = []
var checkpoint: String = ""
## Текущая глава сюжета (реплики Стража Перекрёстка и т. п.) и сколько раз Рэй был на Перепутье.
var chapter: int = 1
var crossroads_visits: int = 0
## Что в мире уже сделано навсегда: открытые двери, пустые сундуки, подобранные ключи ("сцена:узел").
var taken: Array[String] = []

## Инвентарь: [{"item": ItemData, "count": int}], экипировка: слот -> ItemData.
var inventory: Array[Dictionary] = []
var equipment: Dictionary = {}
## Собранные души: [{"soul": SoulData, "state": SoulData.State}].
var souls: Array[Dictionary] = []
## Хотбар: 4 скилла и 4 предмета (null — пусто).
var hotbar_skills: Array = [null, null, null, null]
var hotbar_items: Array = [null, null, null, null]

var _cooldowns: Dictionary = {}  # id скилла -> секунд осталось
var _regen_wait: float = 0.0


func _ready() -> void:
	reset()


## Чистое состояние для новой игры: стартовый набор, полное здоровье.
func reset() -> void:
	eating = null
	deaths = 0
	helios = 0
	run_helios = 0
	death_marks.clear()
	lit_lanterns.clear()
	checkpoint = ""
	chapter = 1
	crossroads_visits = 0
	taken.clear()
	_cooldowns.clear()
	inventory.clear()
	equipment.clear()
	souls.clear()
	for id in START_INVENTORY:
		add_item(ContentDB.item(id), START_INVENTORY[id], false)
	for slot in START_EQUIPMENT:
		equipment[slot] = ContentDB.item(START_EQUIPMENT[slot])
	for id in START_SOULS:
		souls.append({"soul": ContentDB.soul(id), "state": SoulData.State.COLLECTED})
	for i in 4:
		hotbar_skills[i] = ContentDB.skill(START_HOTBAR_SKILLS[i]) if START_HOTBAR_SKILLS[i] != "" else null
		hotbar_items[i] = ContentDB.item(START_HOTBAR_ITEMS[i]) if START_HOTBAR_ITEMS[i] != "" else null
	recompute_stats()
	hp = max_hp
	energy = max_energy
	_emit_all()


# --- Инвентарь и экипировка --------------------------------------------------

func count_of(item: ItemData) -> int:
	for e in inventory:
		if e["item"] == item:
			return e["count"]
	return 0


func add_item(item: ItemData, count: int = 1, notify: bool = true) -> void:
	if item == null:
		return
	for e in inventory:
		if e["item"] == item and item.max_stack > 1:
			e["count"] = mini(e["count"] + count, item.max_stack)
			if notify:
				items_changed.emit()
			return
	for i in (count if item.max_stack <= 1 else 1):
		inventory.append({"item": item, "count": 1 if item.max_stack <= 1 else mini(count, item.max_stack)})
	if notify:
		items_changed.emit()


## Убирает предмет (одну стопку или count штук). Надетое снимается, из хотбара — убирается.
func remove_item(item: ItemData, count: int = 1) -> void:
	for i in inventory.size():
		var e: Dictionary = inventory[i]
		if e["item"] != item:
			continue
		e["count"] -= count
		if e["count"] <= 0:
			inventory.remove_at(i)
			if count_of(item) == 0:
				for slot in equipment.keys():
					if equipment[slot] == item:
						equipment.erase(slot)
				for h in 4:
					if hotbar_items[h] == item:
						hotbar_items[h] = null
			recompute_stats()
		items_changed.emit()
		return


## Слот экипировки для предмета: реликвия — в первый свободный из двух.
func slot_for(item: ItemData) -> String:
	match item.slot:
		ItemData.Slot.WEAPON: return "weapon"
		ItemData.Slot.CLOAK: return "cloak"
		ItemData.Slot.ARMOR: return "armor"
		ItemData.Slot.AMULET: return "amulet"
		ItemData.Slot.RELIC: return "relic_2" if equipment.has("relic_1") and not equipment.has("relic_2") else "relic_1"
	return ""


func is_equipped(item: ItemData) -> bool:
	return equipment.values().has(item)


func equip(item: ItemData, slot: String = "") -> void:
	if item == null or item.category != ItemData.Category.EQUIPMENT:
		return
	if slot == "":
		slot = slot_for(item)
	for s in equipment.keys():  # один и тот же предмет не надевается дважды
		if equipment[s] == item:
			equipment.erase(s)
	equipment[slot] = item
	recompute_stats()
	items_changed.emit()


func unequip(slot: String) -> void:
	equipment.erase(slot)
	recompute_stats()
	items_changed.emit()


## Пересчёт характеристик от экипировки.
func recompute_stats() -> void:
	var bonus := {"max_hp": 0.0, "max_energy": 0.0, "damage": 0.0, "defense": 0.0}
	for item in equipment.values():
		for key in item.stats:
			bonus[key] = bonus.get(key, 0.0) + float(item.stats[key])
	max_hp = BASE_HP + bonus["max_hp"]
	max_energy = BASE_ENERGY + bonus["max_energy"]
	damage_bonus = BASE_DAMAGE + bonus["damage"]
	defense = bonus["defense"]
	hp = minf(hp, max_hp)
	energy = minf(energy, max_energy)
	stats_changed.emit()
	hp_changed.emit(hp, max_hp)
	energy_changed.emit(energy, max_energy)


# --- Души и хотбар -------------------------------------------------------------

func set_soul_state(soul: SoulData, state: SoulData.State) -> void:
	for e in souls:
		if e["soul"] == soul:
			e["state"] = state
	items_changed.emit()


func has_soul(id: StringName) -> bool:
	return souls.any(func(e): return e["soul"].id == id)


## Найдена душа: она у Рэя, её сила — в первую свободную ячейку хотбара (если ещё не там).
func collect_soul(id: StringName) -> SoulData:
	var soul := ContentDB.soul(id)
	if soul == null or has_soul(id):
		return soul
	souls.append({"soul": soul, "state": SoulData.State.COLLECTED})
	if soul.skill and not hotbar_skills.has(soul.skill):
		var free := hotbar_skills.find(null)
		if free >= 0:
			hotbar_skills[free] = soul.skill
	items_changed.emit()
	return soul


## Души, ещё не отданные графу и не освобождённые.
func souls_with_ray() -> Array:
	return souls.filter(func(e): return e["state"] == SoulData.State.COLLECTED).map(func(e): return e["soul"])


func assign_skill(index: int, skill: SkillData) -> void:
	for i in 4:
		if hotbar_skills[i] == skill:
			hotbar_skills[i] = null
	hotbar_skills[index] = skill
	items_changed.emit()


func assign_item(index: int, item: ItemData) -> void:
	for i in 4:
		if hotbar_items[i] == item:
			hotbar_items[i] = null
	hotbar_items[index] = item
	items_changed.emit()


func use_skill(index: int) -> bool:
	var s: SkillData = hotbar_skills[index]
	if s == null or _cooldowns.get(s.id, 0.0) > 0.0:
		return false
	if not spend_energy(s.energy_cost):
		return false
	_cooldowns[s.id] = s.cooldown
	skill_used.emit(index)
	return true


func use_item(index: int) -> bool:
	var it: ItemData = hotbar_items[index]
	if it == null or count_of(it) <= 0 or it.category != ItemData.Category.CONSUMABLE:
		return false
	if not start_use(it):
		return false
	item_used.emit(index)
	return true


## Начать использовать расходник: настойка — сразу, еда — Рэй ест use_time секунд (ведёт Player:
## по окончании finish_eating, удар или рывок — cancel_eating, предмет тогда не тратится).
func start_use(item: ItemData) -> bool:
	# Без Рэя в сцене есть некому (и некому закончить) — тогда сразу.
	if item.use_time <= 0.0 or get_tree().get_first_node_in_group("player") == null:
		consume(item)
		return true
	if eating != null:
		return false
	eating = item
	eating_started.emit(item)
	return true


func finish_eating() -> void:
	if eating != null and count_of(eating) > 0:
		consume(eating)
	eating = null


func cancel_eating() -> void:
	if eating != null:
		eating = null
		eating_cancelled.emit()


## Использовать расходник сразу (настойки; еда — через start_use).
func consume(item: ItemData) -> void:
	if item.heal > 0.0:
		heal(item.heal)
	if item.energy > 0.0:
		energy = minf(energy + item.energy, max_energy)
		energy_changed.emit(energy, max_energy)
	var slot_index := hotbar_items.find(item)
	remove_item(item, 1)
	if slot_index >= 0 and hotbar_items[slot_index] == null:
		# Закончившийся расходник остаётся в ячейке хотбара (счётчик 0), чтобы не назначать заново.
		hotbar_items[slot_index] = item
		items_changed.emit()


## 0..1 — оставшаяся доля перезарядки скилла в ячейке хотбара.
func skill_cooldown_ratio(index: int) -> float:
	var s: SkillData = hotbar_skills[index]
	if s == null or s.cooldown <= 0.0:
		return 0.0
	return _cooldowns.get(s.id, 0.0) / s.cooldown


func _process(delta: float) -> void:
	for id in _cooldowns.keys():
		_cooldowns[id] = maxf(0.0, _cooldowns[id] - delta)
	if _regen_wait > 0.0:
		_regen_wait -= delta
	elif energy < max_energy:
		energy = minf(energy + energy_regen * delta, max_energy)
		energy_changed.emit(energy, max_energy)


# --- Здоровье, энергия, смерть -------------------------------------------------

## Урон по Рэю; at — где он стоит (если удар смертельный — туда ляжет утерянная добыча).
func damage(amount: float, at: Vector3 = Vector3.INF) -> void:
	if hp <= 0.0 or god_mode:
		return
	# Защита ослабляет урон: при защите 100 — вдвое.
	hp = maxf(hp - amount * 100.0 / (100.0 + defense), 0.0)
	hp_changed.emit(hp, max_hp)
	if hp == 0.0:
		die(at)


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)


## Тратит энергию души; false — если не хватает (тогда ничего не тратится).
func spend_energy(amount: float) -> bool:
	if energy < amount:
		energy_denied.emit()
		return false
	energy -= amount
	_regen_wait = energy_regen_delay
	energy_changed.emit(energy, max_energy)
	return true


func add_helios(amount: int, found_in_run: bool = true) -> void:
	helios += amount
	if found_in_run:
		run_helios += amount
	# Траты (лавка, кузница) уменьшают и найденное в спуске: потеря при смерти считается от run_helios
	# и иначе уводила кошелёк в минус (нашёл 100, отдал 90 за меч, умер — «−65»).
	run_helios = clampi(run_helios, 0, maxi(helios, 0))
	helios_changed.emit(helios, amount)


## Смерть в спуске: +1 отметка, потеря доли гелиосов спуска. Возвращает, сколько осталось лежать на месте.
## at — где умер Рэй (для карты журнала и утерянной добычи).
func die(at: Vector3 = Vector3.INF) -> int:
	deaths = mini(deaths + 1, MAX_DEATHS)
	var lost := int(round(run_helios * LOSS_BY_DIFFICULTY[difficulty]))
	run_helios -= lost
	helios -= lost
	var dropped := int(round(lost * randf_range(DROP_SHARE_MIN, DROP_SHARE_MAX)))
	if at.is_finite():
		var scene := get_tree().current_scene
		death_marks.append({"pos": at, "number": deaths, "helios": dropped,
			"scene": scene.scene_file_path if scene else ""})
	deaths_changed.emit(deaths)
	if lost > 0:
		helios_changed.emit(helios, -lost)
	died.emit(deaths, lost)
	# Возрождение у фонаря душ — пока сразу с полным здоровьем.
	hp = max_hp
	energy = max_energy
	hp_changed.emit(hp, max_hp)
	energy_changed.emit(energy, max_energy)
	if deaths >= MAX_DEATHS:
		crossroads_reached.emit()
	return dropped


## Утерянные гелиосы с места смерти index подобраны (кучка больше не появится).
func claim_death_mark(index: int) -> void:
	if index >= 0 and index < death_marks.size():
		death_marks[index]["helios"] = 0


func is_taken(key: String) -> bool:
	return taken.has(key)


func take(key: String) -> void:
	if not taken.has(key):
		taken.append(key)


## Фонарь душ зажжён — он же новая точка возрождения.
func light_lantern(key: String) -> void:
	if not lit_lanterns.has(key):
		lit_lanterns.append(key)
	checkpoint = key
	lantern_lit.emit(key)


## После Перепутья: Рэй просыпается в таверне целым, начинается новый спуск (CANON, «Механика смерти»).
## Зажжённые фонари остаются (решение автора).
func wake_after_crossroads() -> void:
	crossroads_visits += 1
	start_descent()
	hp = max_hp
	energy = max_energy
	hp_changed.emit(hp, max_hp)
	energy_changed.emit(energy, max_energy)


## Новый спуск: отметки сбрасываются, найденное ранее уже «своё».
func start_descent() -> void:
	deaths = 0
	run_helios = 0
	death_marks.clear()
	deaths_changed.emit(deaths)


# --- Сохранение ----------------------------------------------------------------

func to_dict() -> Dictionary:
	var equip := {}
	for slot in equipment:
		equip[slot] = String(equipment[slot].id)
	return {
		"hp": hp, "energy": energy, "deaths": deaths, "helios": helios, "run_helios": run_helios,
		"difficulty": difficulty,
		"inventory": inventory.map(func(e): return [String(e["item"].id), e["count"]]),
		"equipment": equip,
		"souls": souls.map(func(e): return [String(e["soul"].id), e["state"]]),
		"hotbar_skills": hotbar_skills.map(func(s): return String(s.id) if s else ""),
		"hotbar_items": hotbar_items.map(func(it): return String(it.id) if it else ""),
		"death_marks": death_marks.map(func(m): return [m["pos"].x, m["pos"].y, m["pos"].z, m["number"], m["helios"], m.get("scene", "")]),
		"lit_lanterns": lit_lanterns,
		"checkpoint": checkpoint,
		"chapter": chapter,
		"crossroads_visits": crossroads_visits,
		"taken": taken,
	}


func from_dict(d: Dictionary) -> void:
	reset()
	if d.has("inventory"):
		inventory.clear()
		for pair in d["inventory"]:
			var item := ContentDB.item(pair[0])
			if item:
				inventory.append({"item": item, "count": int(pair[1])})
		equipment.clear()
		for slot in d.get("equipment", {}):
			var item := ContentDB.item(d["equipment"][slot])
			if item:
				equipment[slot] = item
		souls.clear()
		for pair in d.get("souls", []):
			var soul := ContentDB.soul(pair[0])
			if soul:
				souls.append({"soul": soul, "state": int(pair[1])})
		var hs: Array = d.get("hotbar_skills", [])
		var hi: Array = d.get("hotbar_items", [])
		for i in 4:
			hotbar_skills[i] = ContentDB.skill(hs[i]) if i < hs.size() and hs[i] != "" else null
			hotbar_items[i] = ContentDB.item(hi[i]) if i < hi.size() and hi[i] != "" else null
	death_marks.clear()
	for m in d.get("death_marks", []):
		death_marks.append({"pos": Vector3(m[0], m[1], m[2]), "number": int(m[3]), "helios": int(m[4]),
			"scene": m[5] if m.size() > 5 else ""})
	lit_lanterns.assign(d.get("lit_lanterns", []))
	checkpoint = d.get("checkpoint", "")
	chapter = int(d.get("chapter", 1))
	crossroads_visits = int(d.get("crossroads_visits", 0))
	taken.assign(d.get("taken", []))
	recompute_stats()
	hp = minf(d.get("hp", max_hp), max_hp)
	energy = minf(d.get("energy", max_energy), max_energy)
	deaths = d.get("deaths", 0)
	helios = d.get("helios", 0)
	run_helios = d.get("run_helios", 0)
	if d.has("difficulty"):
		Settings.set_value("difficulty", int(d["difficulty"]))
	_emit_all()


func _emit_all() -> void:
	hp_changed.emit(hp, max_hp)
	energy_changed.emit(energy, max_energy)
	deaths_changed.emit(deaths)
	helios_changed.emit(helios, 0)
	items_changed.emit()
	stats_changed.emit()
