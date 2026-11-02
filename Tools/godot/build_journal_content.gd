extends SceneTree
## Создаёт стартовое содержимое журнала: записи, досье, карту тестовой локации (res://data/journal, res://data/maps).
## ВНИМАНИЕ: перезаписывает файлы с теми же id. Тексты — черновики по CANON.md; пишет и правит их автор.
## Запуск: Game/Godot_v4.7.2-stable_win64_console.exe --headless --path Game/CatsSoulDebt -s Tools/godot/build_journal_content.gd

const ENTRY := "res://scripts/data/journal_entry.gd"
const MAP := "res://scripts/data/journal_map.gd"

# author: RAY=0, LIARA=1, COMMANDER=2, VELMOR=3, UNKNOWN=4; section: RECORDS=0, PEOPLE=1.
const ENTRIES := [
	{"id": "ray_debt", "title": "Долг", "author": 0, "chapter": 1,
		"text": "Граф говорит, что долг — просто слово. Но жизнь, которую я ношу, не моя. Десятая, взятая взаймы в Ночь Рубежа. Пока я её отрабатываю, ношу ему вещи из склепа.\n\nКонтракт я так и не дочитал."},
	{"id": "ray_nine_marks", "title": "Девять отметок", "author": 0, "chapter": 1,
		"text": "В ту ночь я умер девять раз. Теперь каждая смерть внизу — отметка на счёте. Просыпаюсь у фонаря душ, если успел его зажечь. После девятой меня выбрасывает на Перепутье.\n\nКаждый раз что-то остаётся в воде."},
	{"id": "liara_patients", "title": "Страница из книги писаря", "author": 1, "chapter": 1,
		"text": "Р. опять принёс травы из сокровищницы. Сказала ему, что это не лечится. Он не слушает.\n\nЗаписать в журнал гарнизона: недостача — две склянки, сушёный корень. Виновного не нашли."},
	{"id": "order_charter", "title": "Приказ по гарнизону", "author": 2, "chapter": 1, "sealed": true,
		"text": "«Ограждение возводится для защиты, а не для славы». Устав Рубежа, первая строка.\n\nПриближаться к печати без приказа запрещено. Нарушивший будет наказан по уставу."},
	{"id": "note_unsigned", "title": "Записка без подписи", "author": 4, "chapter": 1, "unlocked_by_default": true,
		"text": "Белый снова ходил к печати ночью. Доложить?\n\nНет. Пусть ходит."},
	{"id": "person_ray", "title": "Рэй", "section": 1, "author": 0, "portrait": "res://assets/sprites/ray/ray_anim.png",
		"text": "Младший из девятижизненных. Солдат гарнизона Каменного Рубежа. Шрам на щеке — с первой ночи на посту.\n\nЖиву на десятой жизни."},
	{"id": "person_liara", "title": "Лиара", "section": 1, "author": 0, "portrait": "res://assets/sprites/liara/liara_anim.png",
		"text": "Целительница и писарь гарнизона. Единственная, кто смеётся над моей выправкой.\n\nОна больна, и мы оба это знаем."},
	{"id": "person_velmor", "title": "Граф Вельмор", "section": 1, "author": 0, "portrait": "res://assets/sprites/velmor/velmor_anim.png",
		"text": "Трактирщик Ивового Брода. Печёт пироги, лечит скот, ни разу не взял плату вперёд.\n\nНикогда не снимает перчаток."},
]

const MAP_ROOMS := [
	{"id": "tavern", "name": "Таверна графа", "world": Rect2(-24, -7, 16, 14),
		"note": "Тепло, свечи на каждом столе. Граф говорит, что мне здесь всегда рады.",
		"features": [{"type": "fire", "pos": Vector2(-20, -6)}, {"type": "door", "pos": Vector2(-8, 4.5)}]},
	{"id": "rubezh", "name": "Верхние залы Рубежа", "world": Rect2(-8, -7, 16, 14),
		"note": "Факелы горят холодным светом. С потолка капает, на колоннах мох.",
		"features": [{"type": "door", "pos": Vector2(8, 4.5)}]},
	{"id": "shore", "name": "Берег Тихой Воды", "world": Rect2(8, -7, 8, 14),
		"note": "Кристаллы светятся фиолетовым. Вода не шевелится, даже если бросить камень."},
	{"id": "pier", "name": "Причал", "world": Rect2(16, -1.25, 12, 2.5), "hinted": true,
		"note": "Три фонаря душ. В конце — круг из чёрного камня.",
		"features": [{"type": "lantern", "pos": Vector2(18, 1.15)}, {"type": "lantern", "pos": Vector2(21.5, -1.15)},
			{"type": "lantern", "pos": Vector2(25, 1.15)}, {"type": "seal", "pos": Vector2(27, 0)}]},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/journal")
	DirAccess.make_dir_recursive_absolute("res://data/maps")
	var count := 0
	for i in ENTRIES.size():
		var d: Dictionary = ENTRIES[i]
		var e: Resource = load(ENTRY).new()
		e.set("order", i)
		for key in d:
			if key == "portrait":
				e.set("portrait_sheet", load(d[key]))
			else:
				e.set(key, d[key])
		count += int(ResourceSaver.save(e, "res://data/journal/%s.tres" % d["id"]) == OK)
	var m: Resource = load(MAP).new()
	m.set("id", &"test_map")
	m.set("title", "Брод — Рубеж — Тихая Вода")
	var rooms: Array[Dictionary] = []
	rooms.assign(MAP_ROOMS)
	m.set("rooms", rooms)
	count += int(ResourceSaver.save(m, "res://tests/test_arena_map.tres") == OK)
	print("сохранено ресурсов: ", count)
	quit()
