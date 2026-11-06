class_name ItemData
extends Resource
## Предмет инвентаря (UI_SPEC, раздел 3).

enum Category { EQUIPMENT, CONSUMABLE, MATERIAL, KEY }
## Слоты экипировки Рэя: оружие, плащ, доспех, амулет, две реликвии.
enum Slot { NONE, WEAPON, CLOAK, ARMOR, AMULET, RELIC }

const CATEGORY_NAMES := ["Снаряжение", "Расходник", "Материал", "Ключевой предмет"]
const SLOT_NAMES := ["", "Оружие", "Плащ", "Доспех", "Амулет", "Реликвия"]

@export var id: StringName
@export var name: String
@export var category: Category = Category.MATERIAL
@export var slot: Slot = Slot.NONE
@export var icon: Texture2D
@export_multiline var description: String
## Для реликвий — короткая история павшего владельца.
@export_multiline var owner_story: String
## Бонусы при экипировке: max_hp, max_energy, damage, defense.
@export var stats: Dictionary = {}
## Расходники: сколько HP восстанавливает.
@export var heal: float = 0.0
## Расходники: сколько энергии души восстанавливает.
@export var energy: float = 0.0
## Еда: сколько секунд Рэй ест (удар по нему прерывает, предмет не тратится). 0 — мгновенно (настойки).
@export var use_time: float = 0.0
## Зелья Ларпа: бафф на время (PlayerState.add_buff). Виды: defense — к защите, speed и regen — доля прибавки
## к скорости и восстановлению энергии, night — яркость света вокруг Рэя ночью, mist — доля снижения урона от тумана.
@export var buff: StringName
@export var buff_power: float = 0.0
@export var buff_time: float = 0.0
@export var max_stack: int = 1
## Ключевые предметы: id записи журнала, которую можно открыть.
@export var journal_entry: StringName


func type_line() -> String:
	if category == Category.EQUIPMENT:
		return SLOT_NAMES[slot]
	return CATEGORY_NAMES[category]


## Строки бонусов для описания: «Урон +4», «HP +10»...
func stat_lines() -> PackedStringArray:
	var names := {"damage": "Урон", "defense": "Защита", "max_hp": "HP", "max_energy": "Энергия души"}
	var lines := PackedStringArray()
	for key in stats:
		lines.append("%s %+d" % [names.get(key, key), stats[key]])
	return lines
