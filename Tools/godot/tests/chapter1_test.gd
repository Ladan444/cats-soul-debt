extends SceneTree
## Сквозной тест Главы 1 (Литература/CHAPTER1.md): новая игра → таверна (Рэй у кровати) → разговор с графом →
## знамя из казармы Рубежа → граф → душа Йорга → граф (выбор: отдать) → три части ключа → шкатулка и медальон →
## граф → мост открыт → Большой зал → финал → «Конец Главы 1» → главное меню.
## Скриншоты — Арт/Скриншоты/ch1_*.png (только в окне). Перемещения — телепортом (это тест сюжета, не карты).
## Запуск: Godot_console --resolution 1280x720 --path Game/CatsSoulDebt -s <абсолютный путь к этому файлу>

const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/"
var errors := 0
var quests: Node
var ps: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		errors += 1


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")


func wait(s: float) -> void:
	await create_timer(s).timeout


func wait_scene(file: String, timeout := 10.0) -> bool:
	var t := 0.0
	while t < timeout:
		await process_frame
		t += 1.0 / 60.0
		if current_scene and current_scene.scene_file_path.ends_with(file):
			await wait(1.0)
			return true
	return false


func step() -> int:
	return quests.step("chapter1")


## Пролистать все реплики (и выбрать вариант choice, если спросят).
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


func talk_velmor(choice := 0) -> void:
	var v: Node = current_scene.get_node("Velmor")
	v.talk()
	await wait(0.2)
	await talk_through(choice)
	await wait(0.3)
	# Выбор души запускает следующую реплику — дочитать и её.
	await talk_through(choice)
	await wait(0.2)


func take(story_name: String) -> void:
	var n: Node = current_scene.get_node_or_null("Combat/" + story_name)
	check(n != null, "находка %s есть на этаже" % story_name)
	if n:
		n.interact()
		await wait(0.2)
		await talk_through()


func go(scene: String, file: String) -> void:
	change_scene_to_file(scene)
	await wait_scene(file)


func _run() -> void:
	quests = root.get_node("QuestState")
	ps = root.get_node("PlayerState")
	var save := root.get_node("SaveGame")

	print("— Пролог")
	save.new_game(1, load("res://scripts/ui/main_menu.gd").GAME_SCENE)
	check(await wait_scene("tavern.tscn"), "новая игра — в таверне")
	var player: Node3D = current_scene.get_node("Player")
	var bed: Vector3 = current_scene.get_node("Geometry/spawn-start").global_position
	check(player.global_position.distance_to(bed) < 1.5, "Рэй просыпается у кровати")
	check(ps.souls.is_empty() and ps.hotbar_skills[0] == null, "в начале нет душ и сил")
	check(step() == 0, "задание: поговорить с графом")
	await shot("ch1_tavern")
	await talk_velmor()
	check(step() == 1, "граф дал поручение «знамя» (шаг %d)" % step())
	await shot("ch1_velmor")

	print("— Знамя")
	await go("res://scenes/levels/rubezh_f1.tscn", "rubezh_f1.tscn")
	await take("Story_banner_third_company")
	check(step() == 2, "знамя взято (шаг %d)" % step())
	await go("res://scenes/levels/tavern.tscn", "tavern.tscn")
	await talk_velmor()
	check(step() == 3, "знамя отдано (шаг %d)" % step())
	check(current_scene.get_node("Geometry/Banner").visible, "знамя висит над камином")

	print("— Души")
	await go("res://scenes/levels/rubezh_f1.tscn", "rubezh_f1.tscn")
	await take("Story_soul_jorg")
	check(ps.has_soul(&"soul_jorg") and ps.hotbar_skills[0] != null, "душа Йорга с Рэем, её сила в хотбаре")
	check(step() == 4, "душа найдена (шаг %d)" % step())
	await shot("ch1_soul")
	await go("res://scenes/levels/tavern.tscn", "tavern.tscn")
	await talk_velmor(0)
	check(ps.souls[0]["state"] == 1, "душа отдана графу (выбор)")
	check(ps.hotbar_skills[0] != null, "сила души осталась у Рэя")
	check(step() == 5, "граф дал поручение «шкатулка» (шаг %d)" % step())

	print("— Сокровищница")
	await go("res://scenes/levels/rubezh_f1.tscn", "rubezh_f1.tscn")
	for k in current_scene.get_node("Combat").get_children():
		if String(k.name).begins_with("Bigkey"):
			k.global_position = current_scene.get_node("Player").global_position
	await wait(0.6)
	check(ps.count_of(load("res://data/items/key_treasury.tres")) == 1, "ключ сокровищницы собран")
	await take("Story_velmor_casket")
	await take("Story_liara_medallion")
	check(step() == 6, "шкатулка взята (шаг %d)" % step())
	check(ps.count_of(load("res://data/items/liara_medallion.tres")) == 1, "медальон Лиары у Рэя")
	await go("res://scenes/levels/tavern.tscn", "tavern.tscn")
	await talk_velmor()
	check(step() == 7, "граф ждёт в Большом зале (шаг %d)" % step())

	print("— Финал")
	await go("res://scenes/levels/rubezh_f1.tscn", "rubezh_f1.tscn")
	player = current_scene.get_node("Player")
	var story_door: Node = null
	for n in current_scene.find_children("*", "LevelDoor", true, false):
		if n.get("kind") == "story":
			story_door = n
	check(story_door != null and story_door.can_interact(), "дверь моста к Большому залу открывается")
	if story_door:
		story_door.interact()
	var finale: Node3D = current_scene.get_node("Chapter1Finale")
	player.global_position = finale.global_position + Vector3(0, 0.5, 4.0)
	await wait(1.6)
	await shot("ch1_finale_start")
	# Читаем реплики, пока не появится Покупатель (кадр с ним), потом — до конца.
	var buyer_shot := false
	for i in 14:
		await wait(0.5)
		var box: Node = current_scene.get_node("DialogueBox")
		if not buyer_shot and box.is_active() and box.get("_name").text == "???":
			await shot("ch1_finale_buyer")
			buyer_shot = true
		await talk_through()
	await wait(1.0)
	await shot("ch1_finale_water")
	await wait(3.5)
	check(quests.is_done("chapter1"), "Глава 1 пройдена")
	await shot("ch1_end_card")
	var end_screen := false
	for i in 60:
		for c in root.get_children():
			if c.get_script() and String(c.get_script().resource_path).ends_with("chapter_end_screen.gd"):
				end_screen = true
		if end_screen:
			break
		await wait(0.25)
	check(end_screen, "после финала — титры и «Ждите продолжения»")
	check(FileAccess.file_exists(save.PATH) and "\"chapter1\": %d" % quests.steps("chapter1").size() in FileAccess.get_file_as_string(save.PATH).replace("	", "").replace("
", ""), "после финала записано сохранение с пройденной главой")

	print("=== ОШИБОК: %d ===" % errors)
	quit(errors)
