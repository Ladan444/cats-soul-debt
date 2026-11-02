extends SceneTree
## Поведенческий тест боя (COMBAT_SPEC) на тестовой карте: комбо по чучелу и солдату, удар солдата
## по Рэю, смерть врага и монеты, фонарь душ, смерть Рэя и возрождение, три скилла, прыжок Твари.
## Запуск: Godot_console --headless --path Game/CatsSoulDebt -s <абсолютный путь к этому файлу>

var fails: Array[String] = []
var ps: Node
var scene: Node
var player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	root.push_input(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	root.push_input(r)


func put_player(at: Vector3, facing: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.set("_facing", facing)
	await physics_frame
	await physics_frame


func _run() -> void:
	ps = root.get_node("PlayerState")
	node_added.connect(_on_node_added)
	ps.reset()
	change_scene_to_file("res://tests/test_arena.tscn")
	await wait(0.5)
	scene = current_scene
	player = scene.get_node("Player")
	var dummy := scene.get_node("Combat/TrainingDummy")
	var soldier := scene.get_node("Combat/DrownedSoldier0")
	var soldier2 := scene.get_node("Combat/DrownedSoldier1")
	var creature := scene.get_node("Combat/LakeCreature0")
	var lantern := scene.get_node("Combat/SoulLanternLake")
	print("урон Рэя: ", ps.damage_bonus)

	print("— Комбо по чучелу")
	var hits := [0]
	var orig_take: float = dummy.hp
	await put_player(dummy.global_position + Vector3(-1.0, 0, 0), Vector3.RIGHT)
	var numbers_before: int = _count_labels()
	for i in 3:
		press(&"attack")
		await wait(0.32)
	await wait(0.5)
	var numbers: int = _count_labels() - numbers_before
	ok(dummy.hp == orig_take, "чучело не умирает (hp %s)" % dummy.hp)
	ok(not player.is_attacking(), "комбо закончилось")
	print("  цифр урона над чучелом за комбо: ", numbers)

	print("— Комбо по Утопшему солдату")
	soldier2.global_position = Vector3(6, 0, 6)  # второй не мешает
	await put_player(soldier.global_position + Vector3(-1.1, 0, 0), Vector3.RIGHT)
	var hp0: float = soldier.hp
	player.set("_invulnerable", 5.0)  # удар солдата прервал бы комбо — здесь проверяем только урон
	for i in 3:
		press(&"attack")
		await wait(0.32)
	await wait(0.3)
	var dealt: float = hp0 - soldier.hp
	ok(is_equal_approx(dealt, ps.damage_bonus * 3.8), "три удара комбо: %s урона (ждали %s)" % [dealt, ps.damage_bonus * 3.8])

	print("— Удар солдата по Рэю")
	var php: float = ps.hp
	player.set("_invulnerable", 0.0)
	await put_player(soldier.global_position + Vector3(-1.0, 0, 0), Vector3.RIGHT)
	await wait(2.5)
	ok(ps.hp < php, "солдат замахнулся и попал: HP %s → %s" % [php, ps.hp])

	print("— Смерть солдата и монеты")
	ps.heal(1000)
	var helios0: int = ps.helios
	for i in 12:
		if soldier.dead:
			break
		player.set("_invulnerable", 5.0)
		await put_player(soldier.global_position + Vector3(-1.0, 0, 0), Vector3.RIGHT)
		press(&"attack")
		await wait(0.4)
	ok(soldier.dead, "солдат убит")
	var coins := root.get_tree().get_nodes_in_group("helios_pickups")
	ok(coins.size() > 0, "выпали монеты: %d" % coins.size())
	await wait(1.0)
	coins = root.get_tree().get_nodes_in_group("helios_pickups")
	for c in coins:
		await put_player(c.global_position, Vector3.RIGHT)
		await wait(0.2)
	ok(ps.helios > helios0, "монеты подобраны: %d → %d" % [helios0, ps.helios])

	print("— Фонарь душ")
	await put_player(lantern.global_position + Vector3(0, 0, 1.0), Vector3.FORWARD)
	await wait(0.1)
	press(&"interact")
	await wait(0.1)
	ok(lantern.lit, "фонарь зажжён")

	print("— Смерть Рэя и возрождение")
	var run_helios: int = ps.run_helios
	await put_player(Vector3(0, 0, 0), Vector3.RIGHT)
	ps.damage(10000, player.global_position)
	ok(not player.is_alive(), "Рэй мёртв")
	print("  отметка: ", ps.death_marks.back() if not ps.death_marks.is_empty() else "нет",
		"  монет на земле: ", root.get_tree().get_nodes_in_group("helios_pickups").size())
	await wait(2.2)
	ok(player.is_alive(), "Рэй возродился")
	ok(player.global_position.distance_to(lantern.respawn_point()) < 0.5, "у фонаря: %s" % player.global_position)
	ok(not soldier.dead and soldier.visible and soldier.hp == soldier.max_hp, "солдат вернулся")
	var piles := root.get_tree().get_nodes_in_group("helios_pickups").filter(func(p): return p.lost_pile)
	ok(run_helios == 0 or piles.size() == 1, "утерянные гелиосы лежат на месте смерти (спуск %d, куч %d)" % [run_helios, piles.size()])
	ok(ps.deaths == 1, "отметка смерти: %d" % ps.deaths)

	print("— Скиллы")
	# Силы приходят с именными душами (Глава 1): Финн — шаг, Йорг — эхо, Бруно — метка.
	for id in [&"soul_finn", &"soul_jorg", &"soul_bruno"]:
		ps.collect_soul(id)
	ok(ps.hotbar_skills[0] != null and ps.hotbar_skills[0].id == &"ghost_step", "душа Финна дала Призрачный шаг в ячейку 1")
	ps.energy = ps.max_energy
	await put_player(Vector3(-4, 0, 0), Vector3.RIGHT)
	var x0: float = player.global_position.x
	ps.use_skill(0)
	await physics_frame
	ok(player.get("_ghost"), "Призрачный шаг: Рэй призрачен")
	await wait(0.5)
	ok(not player.get("_ghost"), "Призрачный шаг закончился")
	print("  пролетел: %.2f м" % (player.global_position.x - x0))
	ok(player.global_position.x - x0 > 2.5, "Призрачный шаг длиннее обычного рывка")

	ps.energy = ps.max_energy
	await put_player(dummy.global_position + Vector3(-1.0, 0, 0), Vector3.RIGHT)
	var before: int = _count_labels()
	ps.use_skill(1)
	await wait(0.9)
	ok(_count_labels() - before >= 2, "Эхо удара: два попадания (цифр %d)" % (_count_labels() - before))

	ps.energy = ps.max_energy
	await put_player(creature.global_position + Vector3(-2.0, 0, 0), Vector3.RIGHT)
	ps.use_skill(2)
	await physics_frame
	ok(creature.get("_mark_time") > 0.0, "Метка часового на ближайшей Твари")
	var chp: float = creature.hp
	player.set("_invulnerable", 5.0)
	await put_player(creature.global_position + Vector3(-1.0, 0, 0), Vector3.RIGHT)
	press(&"attack")
	await wait(0.3)
	ok(creature.dead or is_equal_approx(chp - creature.hp, ps.damage_bonus * 2.0), "меченая Тварь получила ×2: %s" % (chp - creature.hp))

	print("— Тварь прыгает")
	var creature2 := scene.get_node("Combat/LakeCreature1")
	ps.heal(1000)
	player.set("_invulnerable", 0.0)
	await put_player(creature2.global_position + Vector3(-3.0, 0, 0), Vector3.RIGHT)
	var hp_before: float = ps.hp
	var states := {}
	for i in 60:
		states[creature2.state] = true
		await wait(0.1)
	print("  состояния Твари: ", states.keys())
	ok(states.has("leap"), "Тварь прыгнула")
	ok(ps.hp < hp_before or states.has("puddle"), "прыжок закончился лужей или попаданием")

	print("— Навигация: обход препятствий")
	var map_rid: RID = soldier.get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, Vector3(-16, 0, 4.5), Vector3(12, 0, 0), true)
	ok(path.size() >= 2 and path[path.size() - 1].distance_to(Vector3(12, 0, 0)) < 0.8, "путь из таверны на берег озера (%d точек)" % path.size())
	var around: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, Vector3(-13, 0, 4.0), Vector3(-13, 0, 1.0), true)
	var length := 0.0
	for i in range(1, around.size()):
		length += around[i - 1].distance_to(around[i])
	ok(length > 3.3, "путь вокруг стола длиннее прямой 3 м: %.2f" % length)
	# Солдат за столом таверны должен обойти его и дойти до Рэя.
	ps.heal(1000)
	soldier.global_position = Vector3(-13, 0, 4.0)
	soldier.spawn_position = Vector3(-13, 0, 4.0)
	soldier.set_state("chase")
	player.set("_invulnerable", 30.0)
	await put_player(Vector3(-13, 0, 1.0), Vector3.FORWARD)
	var reached := false
	for i in 80:
		await wait(0.1)
		player.global_position = Vector3(-13, 0, 1.0)
		if soldier.state in ["windup", "strike", "recover"]:
			reached = true
			break
	ok(reached, "солдат обошёл стол и замахнулся (позиция %s)" % soldier.global_position)
	player.set("_invulnerable", 0.0)

	print("— Блуждание по области")
	# Рэй далеко: солдат не стоит и не идёт на исходную точку, а бродит в пределах wander_radius.
	await put_player(Vector3(-30, 0, 4), Vector3.LEFT)
	soldier.set_state("idle")
	soldier.set("_wander_wait", 0.0)
	var moved := 0.0
	var farthest := 0.0
	var last: Vector3 = soldier.global_position
	for i in 100:
		await wait(0.1)
		player.global_position = Vector3(-30, 0, 4)
		moved += soldier.global_position.distance_to(last)
		last = soldier.global_position
		var off: Vector3 = soldier.global_position - soldier.spawn_position
		farthest = maxf(farthest, Vector2(off.x, off.z).length())
	ok(moved > 1.0, "солдат бродит (прошёл %.1f м за 10 с)" % moved)
	ok(farthest <= soldier.wander_radius + 0.8, "не выходит из своей области (дальше всего %.1f м)" % farthest)

	print("— Сохранение фонарей и кучек")
	# Ещё одна смерть с гелиосами в кармане, чтобы точно лежала кучка.
	ps.add_helios(20)
	await put_player(Vector3(1, 0, 3), Vector3.RIGHT)
	ps.damage(10000, player.global_position)
	await wait(2.2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ps.to_dict()))
	var piles_before := root.get_tree().get_nodes_in_group("helios_pickups").filter(func(p): return p.lost_pile).size()
	ps.from_dict(saved)
	change_scene_to_file("res://tests/test_arena.tscn")
	await wait(0.6)
	scene = current_scene
	player = scene.get_node("Player")
	ok(scene.get_node("Combat/SoulLanternLake").lit, "фонарь у озера зажжён после загрузки")
	ok(not scene.get_node("Combat/SoulLanternRubezh").lit, "фонарь Рубежа не зажжён")
	var piles_after := root.get_tree().get_nodes_in_group("helios_pickups").filter(func(p): return p.lost_pile)
	ok(piles_after.size() == piles_before and piles_before > 0, "кучки утерянного восстановлены: %d из %d" % [piles_after.size(), piles_before])
	ps.damage(10000, player.global_position)
	await wait(2.2)
	ok(player.global_position.distance_to(scene.get_node("Combat/SoulLanternLake").respawn_point()) < 0.5, "после загрузки возрождение у фонаря")
	if not piles_after.is_empty():
		var pile: Node3D = piles_after[0]
		var idx: int = pile.mark_index
		var h0: int = ps.helios
		player.set("_invulnerable", 5.0)
		await put_player(pile.global_position, Vector3.RIGHT)
		await wait(0.3)
		ok(ps.helios > h0 and ps.death_marks[idx]["helios"] == 0, "кучка подобрана и вычеркнута из отметки")

	# Еда (BALANCE.md): ест 1 с — лечит в конце; удар по Рэю прерывает, еда не тратится; фляга — вся энергия.
	var bun: ItemData = load("res://data/items/honey_bun.tres")
	ps.add_item(bun, 2)
	ps.hp = 40.0
	player.set("_invulnerable", 5.0)
	ok(ps.start_use(bun), "плюшка: Рэй начал есть")
	await wait(0.5)
	ok(is_equal_approx(ps.hp, 40.0) and ps.count_of(bun) == 2, "пока ест — ещё не вылечился")
	await wait(0.8)
	ok(is_equal_approx(ps.hp, 60.0) and ps.count_of(bun) == 1, "доел: +20 HP, плюшка потрачена (HP %s)" % ps.hp)
	ps.start_use(bun)
	await wait(0.3)
	player.set("_invulnerable", 0.0)
	player.take_hit({"damage": 5.0, "dir": Vector3.RIGHT})
	await wait(1.2)
	ok(ps.count_of(bun) == 1 and ps.eating == null, "удар прервал еду — плюшка цела")
	var flask: ItemData = load("res://data/items/klaus_flask.tres")
	ps.add_item(flask, 1)
	ps.energy = 0.0
	player.set("_invulnerable", 5.0)  # враги тестовой карты рядом — их удар законно прервал бы еду
	ps.start_use(flask)
	await wait(1.3)
	ok(is_equal_approx(ps.energy, ps.max_energy) and ps.count_of(flask) == 0, "фляга Клауса: вся энергия (%s)" % ps.energy)

	print("\n=== ОШИБОК: %d ===" % fails.size())
	for f in fails:
		print("FAIL ", f)
	ps.reset()
	quit(1 if fails.size() > 0 else 0)


## Сколько цифр урона (Label3D) появилось с начала теста — считаем при добавлении, они живут 0,7 с.
var _labels := 0


func _count_labels() -> int:
	return _labels


func _on_node_added(n: Node) -> void:
	if n is Label3D and n.get_parent() == current_scene:
		_labels += 1
