extends SceneTree
## Жители Брода в мире (scenes/levels/world.tscn): шесть жителей стоят на земле у своих мест, дом Лиары,
## квест Хорста «Клещи оружейника» от выдачи до награды (место, враги, находка, выбор), квест Ильзы — выбор
## «только лодочку». Скриншоты жителей — в Арт/Скриншоты. Состояние игры после теста восстанавливается.
## Запуск (в окне): Godot_console --resolution 1280x720 --path Game/CatsSoulDebt -s <абсолютный путь к файлу>

const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/villager_%s.png"
const IDS := ["horst", "marta", "ilza", "hans", "oda", "klaus", "mika"]

var fails := 0
var player: Node3D
var quests: Node
var ps: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func wait(sec: float) -> void:
	await create_timer(sec).timeout


func talk_through(choice := 0) -> void:
	var box: Node = current_scene.get_node("DialogueBox")
	for i in 60:
		if not box.is_active():
			return
		if not box.get("_options").is_empty():
			box.call("_choose", choice)
		else:
			box.advance()
		await wait(0.05)


func talk(id: String, choice := 0) -> void:
	var v: Node = current_scene.get_node("Villagers/Villager_" + id)
	v.talk()
	await wait(0.2)
	await talk_through(choice)
	await wait(0.3)
	await talk_through(choice)
	await wait(0.2)


func go(at: Vector3) -> void:
	player.global_position = at + Vector3(0, 0.5, 0)
	current_scene.get_node("Camera3D").call("snap_to_target")
	await wait(0.6)


func _run() -> void:
	quests = root.get_node("QuestState")
	ps = root.get_node("PlayerState")
	var saved_quests: Dictionary = quests.to_dict()
	var saved_player: Dictionary = ps.to_dict()
	root.get_node("TimeOfDay").set_hour(11.0)
	change_scene_to_file("res://scenes/levels/world.tscn")
	await wait(4.0)
	player = current_scene.get_node("Player")
	var space := player.get_world_3d().direct_space_state
	for id in IDS:
		var v: Node3D = current_scene.get_node_or_null("Villagers/Villager_" + id)
		check(v != null, "житель %s на месте" % id)
		if v == null:
			continue
		# Луч сверху (мимо коллизии самого жителя): первое, что он задевает, — рельеф, а не крыша дома.
		var own: Array[RID] = []
		for b in v.find_children("*", "StaticBody3D", true, false):
			own.append((b as StaticBody3D).get_rid())
		var q := PhysicsRayQueryParameters3D.create(v.global_position + Vector3(0, 30, 0), v.global_position - Vector3(0, 5, 0), 1, own)
		var hit := space.intersect_ray(q)
		check(not hit.is_empty() and String(hit.collider.name).begins_with("Terrain"),
			"%s стоит на земле, не в доме (%s)" % [id, hit.collider.name if hit else "—"])
		await go(v.global_position + Vector3(0, 0, 2.5))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT % id)
	check(current_scene.get_node_or_null("Villagers/LiaraHouse") != null, "дом Лиары: воспоминания у двери")

	# Квест Хорста: выдача → шахта (враги) → находка → выбор «отдать всё».
	quests.reset_quest("horst_tongs")
	quests.active.erase("horst_tongs")
	var horst: Node3D = current_scene.get_node("Villagers/Villager_horst")
	await go(horst.global_position + Vector3(0, 0, 1.5))
	await talk("horst")
	check(quests.active.has("horst_tongs") and quests.step("horst_tongs") == 1, "Хорст выдал квест (шаг 1: шахта)")
	var rt: Node = current_scene.get_node("Villagers")
	var mine: Vector3 = rt.get("_sites")["mine"]
	await go(mine)
	await wait(1.0)
	check(quests.step("horst_tongs") == 2, "у шахты шаг «место» закрыт")
	var enemies := 0
	for n in current_scene.get_children():
		if String(n.name).begins_with("QuestEnemy_horst_tongs"):
			enemies += 1
	check(enemies == 2, "у шахты появились враги квеста: %d" % enemies)
	var nav_ok := false
	for i in 40:
		await wait(0.25)
		var ln := current_scene.get_node_or_null("LocalNavigation/Nav_mine") as NavigationRegion3D
		if ln and ln.navigation_mesh.get_polygon_count() > 0:
			nav_ok = true
			break
	check(nav_ok, "у шахты испечена навигация для врагов")
	ps.god_mode = true
	var prop: Node = rt.get_node_or_null("QuestProp_horst_tongs_0")
	check(prop != null, "ларь с клещами у шахты")
	if prop:
		await go(prop.global_position)
		prop.interact()
		await wait(0.3)
		await talk_through()
	var tongs = load("res://scripts/data/content_db.gd").item(&"horst_tongs")
	check(ps.count_of(tongs) == 1 and quests.step("horst_tongs") == 3, "клещи у Рэя, шаг — вернуться к Хорсту")
	var helios_before: int = ps.helios
	await go(horst.global_position + Vector3(0, 0, 1.5))
	await talk("horst", 0)
	check(quests.is_done("horst_tongs"), "квест Хорста сдан")
	check(ps.helios == helios_before + 15 and ps.count_of(tongs) == 0, "награда: +15 гелиосов, клещи отданы")
	ps.god_mode = false

	# Второй квест Хорста открылся; торговля: улучшение меча у Хорста, покупка у Марты.
	await talk("horst")
	check(quests.active.has("horst_blade"), "после первого квеста Хорст дал второй («Сталь третьей роты»)")
	var cdb = load("res://scripts/data/content_db.gd")
	ps.add_helios(200, false)
	var shop_scene := current_scene
	horst.call("open_shop")
	await wait(0.3)
	var shop: Node = shop_scene.get_node("ShopScreen")
	check(shop.call("is_open") and paused, "у Хорста открылась кузница, игра на паузе")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT % "shop_horst")
	var entries: Array = shop.call("_entries")
	check(entries.size() == 1 and entries[0]["kind"] == "upgrade", "кузница предлагает улучшение меча")
	if entries.size() == 1:
		shop.call("_deal", entries[0])
	var weapon = ps.equipment.get("weapon")
	check(weapon != null and String(weapon.id) == "sword_garrison_2", "меч улучшен и надет: %s" % (weapon.id if weapon else "—"))
	# Со 2-го улучшения нужен росток каменной ивы (BALANCE.md 3.2): без него — ни гелиосов, ни меча не берут.
	ps.add_helios(500, false)
	var sprout = cdb.item(&"stone_willow_sprout")
	var helios_forge: int = ps.helios
	entries = shop.call("_entries")
	if entries.size() == 1:
		shop.call("_deal", entries[0])
	weapon = ps.equipment.get("weapon")
	check(String(weapon.id) == "sword_garrison_2" and ps.helios == helios_forge, "без ростка каменной ивы меч не улучшается")
	ps.add_item(sprout, 1)
	entries = shop.call("_entries")
	if entries.size() == 1:
		shop.call("_deal", entries[0])
	weapon = ps.equipment.get("weapon")
	check(String(weapon.id) == "sword_garrison_3" and ps.count_of(sprout) == 0 and ps.helios == helios_forge - 180,
		"с ростком — меч 3-го уровня, росток и 180 гелиосов потрачены")
	shop.call("close")
	var marta: Node3D = current_scene.get_node("Villagers/Villager_marta")
	marta.call("open_shop")
	await wait(0.3)
	var brew = cdb.item(&"marta_brew")
	var had: int = ps.count_of(brew)
	for e in shop.call("_entries"):
		if e["item"] == brew:
			shop.call("_deal", e)
	check(ps.count_of(brew) == had + 1, "у Марты куплен взвар")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT % "shop_marta")
	shop.call("close")
	check(not paused, "торговля закрыта, игра идёт")

	# Воспоминание у дома Лиары.
	var house: Node = current_scene.get_node("Villagers/LiaraHouse")
	house.interact()
	await wait(0.3)
	var box: Node = current_scene.get_node("DialogueBox")
	check(box.is_active(), "у двери Лиары — воспоминание соседа")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT % "liara_memory")
	await talk_through()

	# Духи у фонарей душ: проводник у каждого фонаря, у зажжённого открывает карту; призрак — подсказка и обмен.
	var guides := 0
	for n in rt.get_children():
		if String(n.name).begins_with("Guide_"):
			guides += 1
	check(guides == current_scene.get_node("Lanterns").get_child_count(), "проводник у каждого фонаря: %d" % guides)
	var lantern: Node = current_scene.get_node("Lanterns/SoulLantern_01")
	var was_lit: bool = lantern.get("lit")
	lantern.set("lit", false)
	var guide: Node3D = rt.get_node("Guide_01")
	await go(guide.global_position + Vector3(0, 0, 2.0))
	guide.call("talk")
	await wait(0.3)
	check(box.is_active() and box.get("_options").is_empty(), "у спящего фонаря проводник только говорит")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT % "guide")
	await talk_through()
	lantern.set("lit", true)
	guide.call("talk")
	await wait(0.3)
	await talk_through(0)
	await wait(0.3)
	var wmap: Node = current_scene.get_tree().get_first_node_in_group("world_map")
	check(wmap != null and wmap.call("is_open"), "у зажжённого фонаря проводник открыл карту мира")
	if wmap:
		wmap.call("close_map")
		await wait(0.2)
	var spirit: Node3D = rt.call("place_spirit", "spirit", "01")
	check(spirit != null, "призрак у зажжённого фонаря")
	if spirit:
		await go(spirit.global_position + Vector3(0, 0, 2.0))
		spirit.call("talk")
		await wait(0.3)
		await talk_through(0)        # «Спросить о тайниках» → подсказка
		await wait(0.3)
		var hint: String = spirit.call("_hint")
		print("   подсказка: ", hint)
		check(hint != "", "призрак подсказывает: %s" % hint.left(40))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT % "spirit")
		await talk_through()
		spirit.call("talk")
		await wait(0.3)
		await talk_through(1)        # «Меняться»
		await wait(0.3)
		var sshop: Node = current_scene.get_node("ShopScreen")
		check(sshop.call("is_open") and sshop.call("_entries").size() == 3, "у призрака — обмен на три редкие вещи")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT % "shop_spirit")
		sshop.call("close")
	lantern.set("lit", was_lit)

	quests.from_dict(saved_quests)
	ps.from_dict(saved_player)
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
