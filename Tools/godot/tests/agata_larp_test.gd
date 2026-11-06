extends SceneTree
## Агата и Ларп (NPC_DRAFTS.md, «Агата и Ларп»): жители стоят на земле, три квеста Агаты (ночная находка, «спустя сутки»,
## пять слухов, сдача ночью), алхимический стол, цикл заказов Ларпа, репутация, лавка Агаты по репутации,
## сохранение репутации и суток. Скриншоты — в Арт/Скриншоты. Состояние игры после теста восстанавливается.
## Запуск (в окне): Godot_console --resolution 1280x720 --path Game/CatsSoulDebt -s <абсолютный путь к файлу>

const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/villager_%s.png"

var fails := 0
var player: Node3D
var quests: Node
var ps: Node
var tod: Node
var cdb
var rt: Node


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
	for i in 80:
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


func item(id: String):
	return cdb.item(StringName(id))


func count(id: String) -> int:
	return ps.count_of(item(id))


func _run() -> void:
	quests = root.get_node("QuestState")
	ps = root.get_node("PlayerState")
	tod = root.get_node("TimeOfDay")
	cdb = load("res://scripts/data/content_db.gd")
	var saved_quests: Dictionary = quests.to_dict()
	var saved_player: Dictionary = ps.to_dict().duplicate(true)
	var saved_time: Dictionary = tod.to_dict()
	for id in ["agata_feather", "agata_rumors", "agata_potion", "larp_order_1", "larp_order_2", "larp_order_6"]:
		quests.active.erase(id)
	for k in ["rumor:salt", "rumor:iron", "rumor:flour", "rumor:boats", "rumor:cloaked"]:
		ps.taken.erase(k)
	ps.reputation.clear()
	ps.quest_days.clear()
	quests.active.erase("chapter1")
	quests.start("chapter1")   # Q8: с активной Главой 1 квесты жителей выдаются и сдаются
	tod.paused = true
	tod.set_hour(11.0)
	change_scene_to_file("res://scenes/levels/world.tscn")
	await wait(4.0)
	player = current_scene.get_node("Player")
	rt = current_scene.get_node("Villagers")
	var space := player.get_world_3d().direct_space_state

	# --- Жители стоят на земле ---
	for id in ["agata", "larp", "merchant"]:
		var v: Node3D = current_scene.get_node_or_null("Villagers/Villager_" + id)
		check(v != null, "житель %s на месте" % id)
		if v == null:
			continue
		var own: Array[RID] = []
		for b in v.find_children("*", "StaticBody3D", true, false):
			own.append((b as StaticBody3D).get_rid())
		var q := PhysicsRayQueryParameters3D.create(v.global_position + Vector3(0, 30, 0), v.global_position - Vector3(0, 5, 0), 1, own)
		var hit := space.intersect_ray(q)
		check(not hit.is_empty() and String(hit.collider.name).begins_with("Terrain"),
			"%s стоит на земле, не в доме (%s) на (%.1f, %.1f)" % [id, hit.collider.name if hit else "—", v.global_position.x, v.global_position.z])
		await go(v.global_position + Vector3(0, 0, 3.0))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT % id)
	var agata: Node3D = current_scene.get_node("Villagers/Villager_agata")
	var larp: Node3D = current_scene.get_node("Villagers/Villager_larp")
	var data = load("res://scripts/data/village_quests.gd")

	# --- Агату можно найти только ночью ---
	tod.set_hour(12.0)
	await process_frame
	check(not agata.visible and not agata.can_interact(), "днём (12:00) Агаты нет")
	tod.set_hour(23.0)
	await process_frame
	check(agata.visible and agata.can_interact(), "ночью (23:00) Агата на месте")
	tod.set_hour(11.0)
	await process_frame

	# --- Агата, квест 1: перо только ночью ---
	await go(agata.global_position + Vector3(0, 0, 1.5))
	await talk("agata")
	check(quests.active.has("agata_feather") and quests.step("agata_feather") == 1, "Агата выдала «Поиск черноты» (шаг: святилище)")
	var shrine: Vector3 = rt.get("_sites")["shrine"]
	await go(shrine)
	await wait(1.0)
	check(quests.step("agata_feather") == 2, "у святилища шаг «место» закрыт")
	var prop: Node = rt.get_node_or_null("QuestProp_agata_feather_0")
	check(prop != null, "перо на камне у святилища")
	tod.set_hour(11.0)
	await wait(0.3)
	check(prop != null and not prop.can_interact(), "днём (11:00) перо не берётся")
	tod.set_hour(2.0)
	await wait(0.3)
	check(prop != null and prop.can_interact(), "ночью (02:00) перо можно взять")
	ps.god_mode = true
	if prop:
		await go(prop.global_position)
		prop.interact()
		await wait(0.3)
		await talk_through()
	check(count("raven_feather") == 1 and quests.step("agata_feather") == 3, "перо у Рэя, шаг — вернуть Агате")
	var helios_0: int = ps.helios
	await go(agata.global_position + Vector3(0, 0, 1.5))
	await talk("agata")
	check(quests.is_done("agata_feather"), "«Поиск черноты» сдан")
	check(ps.helios == helios_0 + 75 and count("raven_feather") == 0, "награда: +75 гелиосов, перо отдано")
	check(ps.reputation_of("smugglers") == 5, "репутация контрабандистов +5")

	# --- Лавка Агаты открылась по репутации ---
	var rep_question: String = agata.call("_next_line")
	check(agata.call("_shop_allowed"), "лавка Агаты открыта (репутация ≥ 5)")
	agata.call("open_shop")
	await wait(0.3)
	var shop: Node = current_scene.get_node("ShopScreen")
	check(shop.call("is_open") and shop.call("_entries").size() == 4, "в лавке Агаты — четыре товара")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT % "shop_agata")
	shop.call("close")
	ps.reputation.clear()
	check(not agata.call("_shop_allowed"), "без репутации лавка Агаты закрыта")
	ps.reputation["smugglers"] = 5

	# --- Квест 2: «спустя сутки», пять слухов ---
	await talk("agata")
	check(not quests.active.has("agata_rumors"), "в тот же день «Собор слухов?» не выдан")
	tod.day += 1
	await talk("agata")
	check(quests.active.has("agata_rumors") and quests.step("agata_rumors") == 1, "через сутки Агата выдала «Собор слухов?»")
	var rumor_ids := ["marta", "horst", "hans", "oda", "merchant"]
	for k in rumor_ids.size():
		var who: Node3D = current_scene.get_node("Villagers/Villager_" + rumor_ids[k])
		await go(who.global_position + Vector3(0, 0, 1.5))
		await talk(rumor_ids[k])
		var heard: int = ps.taken.filter(func(t): return t.begins_with("rumor:")).size()
		check(heard == k + 1, "слух %d/5 от %s услышан" % [k + 1, rumor_ids[k]])
	check(quests.step("agata_rumors") == 2, "пять слухов собраны — шаг «рассказать Агате»")
	await talk("merchant")   # повторно тот же слух не засчитывается
	check(ps.taken.filter(func(t): return t.begins_with("rumor:")).size() == 5, "слух засчитывается один раз")
	helios_0 = ps.helios
	await go(agata.global_position + Vector3(0, 0, 1.5))
	await talk("agata")
	check(quests.is_done("agata_rumors"), "«Собор слухов?» сдан")
	check(ps.helios == helios_0 + 50 and count("black_rose") == 1 and ps.reputation_of("smugglers") == 10,
		"награда: +50 гелиосов, чёрная роза, репутация 10")

	# --- Квест 3: ингредиенты → Ларп → варка → сдача ночью ---
	tod.day += 1
	await talk("agata")
	check(quests.active.has("agata_potion") and quests.step("agata_potion") == 1, "Агата выдала «Алхимик из меня…»")
	check(count("agata_ingredients") == 1 and count("agata_recipe") == 1, "свёрток и рецепт Агаты у Рэя")
	await go(larp.global_position + Vector3(0, 0, 1.5))
	# Q9: пока шаг — «поговорить с Ларпом», рецепт Агаты за столом недоступен, ингредиенты не тратятся.
	check(not larp.call("_brewable").has("agata_unknown"), "Q9: до шага варки рецепт Агаты за столом недоступен")
	await talk("larp")
	check(count("agata_ingredients") == 1 and quests.step("agata_potion") == 2, "Q9: первый визит — разговор, а не варка (вещи целы)")
	check(quests.step("agata_potion") == 2, "Ларп принял ингредиенты и рецепт (шаг: варка)")
	check(not quests.active.has("larp_order_1"), "за визит с вещами Агаты заказ Ларпа ещё не выдан")
	var brewable: Array = larp.call("_brewable")
	check(brewable == ["agata_unknown"], "за столом доступен только рецепт Агаты: %s" % str(brewable))
	var done_brew: bool = larp.call("brew", "agata_unknown")
	await wait(0.2)
	await talk_through()
	check(done_brew and count("unknown_potion") == 2, "сварено два неизвестных зелья")
	check(quests.step("agata_potion") == 3 and count("agata_ingredients") == 0, "ингредиенты израсходованы, шаг — отнести ночью")
	# Q10: одну склянку можно выпить, последнюю (для Агаты) — нет.
	var unk = item("unknown_potion")
	var hp_before: float = ps.hp
	ps.hp = 10.0
	check(ps.start_use(unk) and count("unknown_potion") == 1, "Q10: первую склянку выпить можно")
	check(not ps.start_use(unk) and count("unknown_potion") == 1, "Q10: последнюю склянку для сдачи выпить нельзя")
	ps.hp = hp_before
	ps.add_item(unk, 1)   # вторая склянка на выходе (Рэй «выпил» свою) — вернуть для проверки награды
	tod.set_hour(12.0)
	helios_0 = ps.helios
	await go(agata.global_position + Vector3(0, 0, 1.5))
	await talk("agata")
	check(not quests.is_done("agata_potion") and ps.helios == helios_0, "днём Агата сдачу не принимает")
	tod.set_hour(1.0)
	await talk("agata")
	check(quests.is_done("agata_potion"), "ночью зелье сдано")
	check(ps.helios == helios_0 + 100 and count("unknown_potion") == 1 and ps.reputation_of("smugglers") == 15,
		"награда: +100 гелиосов, одно зелье осталось, репутация 15")

	# --- Цикл заказов Ларпа ---
	tod.set_hour(11.0)
	await go(larp.global_position + Vector3(0, 0, 1.5))
	await talk("larp")
	check(quests.active.has("larp_order_1") and quests.step("larp_order_1") == 1, "Ларп выдал первый заказ (тоник)")
	for id in ["marsh_herb", "spring_water", "honey"]:
		ps.add_item(item(id), 1)
	check(larp.call("_brewable").has("larp_tonic"), "за столом доступен тоник")
	check(larp.call("brew", "larp_tonic"), "тоник сварен")
	await wait(0.2)
	await talk_through()
	check(count("larp_tonic") == 2 and quests.step("larp_order_1") == 2, "две склянки, шаг — сдать заказ")
	helios_0 = ps.helios
	await talk("larp")
	check(quests.is_done("larp_order_1"), "первый заказ сдан")
	check(ps.helios == helios_0 + 55 and ps.reputation_of("peasants") == 5 and count("larp_tonic") == 1,
		"награда: +55 гелиосов, репутация крестьян 5, склянка осталась")
	await talk("larp")
	check(not quests.active.has("larp_order_2"), "в тот же день второй заказ не выдан")
	tod.day += 1
	await talk("larp")
	check(quests.active.has("larp_order_2"), "на следующие сутки — второй заказ")
	# Круг: пролистать заказы до конца и убедиться, что цикл начинается заново.
	for n in range(2, 7):
		var qid := "larp_order_%d" % n
		if not quests.active.has(qid):
			tod.day += 1
			await talk("larp")
		check(quests.active.has(qid), "заказ %d выдан" % n)
		var potion := String(data.QUESTS[qid]["finish"]["options"][0]["give"][0])
		for ing in data.RECIPES[potion]["inputs"]:
			ps.add_item(item(ing), 1)
		larp.call("brew", potion)
		await wait(0.2)
		await talk_through()
		await talk("larp")
		check(quests.is_done(qid), "заказ %d сдан" % n)
	check(ps.reputation_of("peasants") == 30, "шесть заказов: репутация крестьян 30")
	tod.day += 1
	await talk("larp")
	check(quests.active.has("larp_order_1") and quests.step("larp_order_1") == 1, "после шестого заказа круг начался заново (тоник)")
	ps.god_mode = false

	# --- Находимость и знакомство: слухи у обычных жителей, строки репутации в книге ---
	check(ps.is_taken("met:agata") and ps.is_taken("met:larp"), "знакомство с Агатой и Ларпом записано (строки репутации в книге)")
	check(" ".join(data.VILLAGERS["klaus"]["rumors"]).contains("Под мостом"), "слух Клауса ведёт к Агате (под мостом у хижины)")
	check(" ".join(data.VILLAGERS["marta"]["rumors"]).contains("Ларп"), "слух Марты ведёт к Ларпу (южнее колодца)")
	var chatter: String = " ".join(data.QUEST_RUMORS["merchant"]["lines"]) + " ".join(data.VILLAGERS["merchant"]["first"])
	check(not chatter.contains("окупател"), "болтовня купца без слова «покупатель» (не путать с Покупателем из канона)")

	# --- Сохранение: репутация, дни, сутки ---
	var snap: Dictionary = ps.to_dict().duplicate(true)
	var tsnap: Dictionary = tod.to_dict()
	var rep_before: int = ps.reputation_of("smugglers")
	ps.reputation.clear()
	ps.quest_days.clear()
	ps.from_dict(snap)
	tod.from_dict(tsnap)
	check(ps.reputation_of("smugglers") == rep_before and ps.reputation_of("peasants") == 30, "репутация переживает сохранение")
	check(ps.quest_days.has("agata_potion") and int(tsnap["day"]) == tod.day, "сутки и дни сдачи переживают сохранение")
	check(ps.is_taken("rumor:cloaked"), "услышанные слухи переживают сохранение")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT % "larp_end")

	tod.paused = false
	quests.from_dict(saved_quests)
	ps.from_dict(saved_player)
	tod.from_dict(saved_time)
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
