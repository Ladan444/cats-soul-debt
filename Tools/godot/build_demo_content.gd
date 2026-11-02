extends SceneTree
## Создаёт демо-содержимое для меню персонажа: предметы, скиллы, души (res://data/...).
## ВНИМАНИЕ: перезаписывает файлы с теми же id. Тексты — заглушки на основе CANON.md, их пишет автор.
## Запуск: Game/Godot_v4.7.2-stable_win64_console.exe --headless --path Game/CatsSoulDebt -s Tools/godot/build_demo_content.gd

const ITEM := "res://scripts/data/item_data.gd"
const SKILL := "res://scripts/data/skill_data.gd"
const SOUL := "res://scripts/data/soul_data.gd"
const UI := "res://assets/ui/"

# Категории и слоты — как в ItemData (Category: EQUIPMENT=0, CONSUMABLE=1, MATERIAL=2, KEY=3;
# Slot: NONE=0, WEAPON=1, CLOAK=2, ARMOR=3, AMULET=4, RELIC=5).
const ITEMS := [
	{"id": "sword_garrison", "name": "Меч гарнизона", "category": 0, "slot": 1, "icon": "icon_sword.png",
		"description": "Короткий железный меч Каменного Рубежа. Потёртый, но надёжный.", "stats": {"damage": 10}},
	{"id": "cloak_garrison", "name": "Плащ гарнизона", "category": 0, "slot": 2, "icon": "icon_cloak.png",
		"description": "Выцветший зелёный плащ с капюшоном и заплаткой на локте.", "stats": {"defense": 2}},
	{"id": "armor_leather", "name": "Кожаный нагрудник", "category": 0, "slot": 3, "icon": "icon_armor.png",
		"description": "Нагрудник из толстой кожи с железными пластинами.", "stats": {"defense": 5, "max_hp": 10}},
	{"id": "amulet_lake_stone", "name": "Оберег из озёрного камня", "category": 0, "slot": 4, "icon": "icon_amulet.png",
		"description": "Гладкий камень со дна Тихой Воды в латунной оправе. Тёплый на ощупь.", "stats": {"max_energy": 15}},
	{"id": "relic_patch", "name": "Нашивка с волком", "category": 0, "slot": 5, "icon": "icon_relic.png",
		"description": "Нашивка гарнизона: волк и шеврон.", "stats": {"defense": 1, "max_hp": 5},
		"owner_story": "Чья-то нашивка, сорванная с рукава в Ночь Рубежа. Кому она принадлежала, Рэй ещё не вспомнил."},
	{"id": "relic_whetstone", "name": "Точильный камень", "category": 0, "slot": 5, "icon": "icon_whetstone.png",
		"description": "Стёрт почти до половины.", "stats": {"damage": 2},
		"owner_story": "Хозяин точил им меч каждый вечер перед дозором. Утром после Ночи Рубежа камень нашли без него."},
	{"id": "tincture_liara", "name": "Настойка Лиары", "category": 1, "icon": "icon_item_placeholder.png",
		"description": "Горькая настойка по рецепту Лиары. Восстанавливает 30 HP.", "heal": 30.0, "max_stack": 9},
	{"id": "marsh_herb", "name": "Болотная трава", "category": 2, "icon": "icon_herb.png",
		"description": "Растёт у кромки Тихой Воды. Пригодится для настоек.", "max_stack": 99},
	{"id": "note_unsigned", "name": "Записка без подписи", "category": 3, "icon": "icon_letter.png",
		"description": "Найдена в казарме. Почерк незнакомый.", "journal_entry": "note_unsigned"},
	{"id": "key_treasury", "name": "Ключ от сокровищницы", "category": 3, "icon": "icon_key.png",
		"description": "Тяжёлый латунный ключ. Рэй уже открывал им дверь — ради Лиары."},
]

const SKILLS := [
	{"id": "ghost_step", "name": "Призрачный шаг", "energy_cost": 25.0, "cooldown": 3.0,
		"description": "Рывок сквозь врагов, не получая урона."},
	{"id": "echo_strike", "name": "Эхо удара", "energy_cost": 40.0, "cooldown": 6.0,
		"description": "Удар повторяется призрачным эхом через мгновение."},
	{"id": "watch_mark", "name": "Метка часового", "energy_cost": 30.0, "cooldown": 4.0,
		"description": "Отмечает врага: следующий удар по нему сильнее."},
]

const SOULS := [
	{"id": "soul_third_company", "name": "Солдат третьей роты", "company": "Третья рота", "skill": "ghost_step",
		"memory": "Он всегда первым бросался в пролом и последним уходил с поста."},
	{"id": "soul_gate_guard", "name": "Страж северных ворот", "company": "Пятая рота", "skill": "echo_strike",
		"memory": "Его удар слышали на другом конце двора — эхо гуляло между стенами."},
	{"id": "soul_tower_watch", "name": "Часовой с башни", "company": "Седьмая рота", "skill": "watch_mark",
		"memory": "Он замечал всё, что двигалось у воды. Кроме того, что поднялось из неё."},
]


func _initialize() -> void:
	for dir in ["res://data/items", "res://data/skills", "res://data/souls"]:
		DirAccess.make_dir_recursive_absolute(dir)
	var count := 0
	for d in ITEMS:
		var it: Resource = load(ITEM).new()
		for key in d:
			it.set(key, load(UI + d[key]) if key == "icon" else d[key])
		count += int(ResourceSaver.save(it, "res://data/items/%s.tres" % d["id"]) == OK)
	var skills := {}
	for d in SKILLS:
		var s: Resource = load(SKILL).new()
		for key in d:
			s.set(key, d[key])
		s.set("icon", load(UI + "icon_skill_%s.png" % d["id"]))
		var path := "res://data/skills/%s.tres" % d["id"]
		count += int(ResourceSaver.save(s, path) == OK)
		skills[d["id"]] = path
	for d in SOULS:
		var soul: Resource = load(SOUL).new()
		for key in d:
			soul.set(key, load(skills[d[key]]) if key == "skill" else d[key])
		count += int(ResourceSaver.save(soul, "res://data/souls/%s.tres" % d["id"]) == OK)
	print("сохранено ресурсов: ", count)
	quit()
