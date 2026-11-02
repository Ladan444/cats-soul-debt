extends SceneTree
## Тест навигатора (Waypoints): маршрут по дорогам между местами, привязка целей квестов к местам мира,
## своя метка. Запуск (в окне): godot_run.ps1 test Tools/godot/tests/waypoints_test.gd

var fails: Array[String] = []
var W: GDScript


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	W = load("res://scripts/ui/waypoints.gd")
	var pois: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_routes.json"))["pois"]
	var tavern := Vector2(pois["tavern"]["at"][0], pois["tavern"]["at"][1])
	var shrine := Vector2(pois["shrine"]["at"][0], pois["shrine"]["at"][1])
	var rubezh := Vector2(pois["rubezh"]["at"][0], pois["rubezh"]["at"][1])
	var mine := Vector2(pois["mine"]["at"][0], pois["mine"]["at"][1])
	for pair in [["таверна → святилище", tavern, shrine], ["таверна → Рубеж", tavern, rubezh], ["таверна → шахта", tavern, mine]]:
		var r: PackedVector2Array = W.find_route(pair[1], pair[2])
		var straight: float = (pair[1] as Vector2).distance_to(pair[2])
		var len: float = W.length_of(r)
		print("    %s: %d точек, %.0f м (напрямик %.0f)" % [pair[0], r.size(), len, straight])
		ok(r.size() >= 3, "%s — маршрут по дорогам (есть промежуточные точки)" % pair[0])
		ok(len >= straight and len < straight * 2.6 + 400.0, "%s — длина разумная" % pair[0])
		ok(r[0] == pair[1] and r[r.size() - 1] == pair[2], "%s — начинается и кончается в заданных точках" % pair[0])
	# Мосты: путь на другой берег реки существует (граф связный между деревней и лагерем у главного моста).
	var camp := Vector2(pois["hunters"]["at"][0], pois["hunters"]["at"][1])
	var rc: PackedVector2Array = W.find_route(tavern, camp)
	ok(W.length_of(rc) < tavern.distance_to(camp) * 2.2, "таверна → лагерь (через главный мост) — не гигантский крюк")
	# Игра: мир, цель шага главного задания, метка.
	root.get_node("SaveGame").new_game(1, "res://scenes/levels/world.tscn")
	await wait(3.0)
	var t: Array = W.targets(self)
	print("    целей: ", t.size(), " ", t)
	ok(W.in_world(self), "в сцене мира")
	var tg: Dictionary = W.main_target(self)
	ok(not tg.is_empty(), "у первого шага «Поговорить с графом» есть цель (граф в таверне)")
	var route: PackedVector2Array = W.route(self)
	ok(route.size() >= 2, "маршрут до цели построен (%d точек)" % route.size())
	W.custom = shrine
	var tg2: Dictionary = W.main_target(self)
	ok(tg2.get("kind", "") == "custom", "своя метка важнее задания")
	W.custom = null
	root.get_viewport().get_texture().get_image().save_png("C:/Temp/waypoints_minimap.png")
	print("=== ОШИБОК: %d ===" % fails.size())
	quit(1 if fails.size() > 0 else 0)
