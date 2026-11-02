extends SceneTree
## Новые враги (COMBAT_SPEC 3а, BALANCE 3.7): квалд — щит, выбивание щита, грязь (замедление, ослепление);
## кобольды — засада, тактика стаи, бегство, последний исчезает без награды; голем — удар по земле с оглушением,
## валун по метке, стойкость. Тестовая карта, зона Рубежа (её враги убираются).
## Запуск: godot_run.ps1 htest Tools/godot/tests/new_enemies_test.gd (в окне — test: ещё и скриншоты).

const OUT := "C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/enemy_%s.png"

var errors := 0
var ps: Node
var player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("OK   " if cond else "FAIL ") + what)
	if not cond:
		errors += 1


func wait(s: float) -> void:
	await create_timer(s).timeout


func spawn(script_path: String, pos: Vector3, props := {}) -> Node3D:
	var body := CharacterBody3D.new()
	body.set_script(load(script_path))
	for k in props:
		body.set(k, props[k])
	current_scene.get_node("Combat").add_child(body)
	body.global_position = pos
	return body


func put_player(at: Vector3) -> void:
	player.global_position = at + Vector3(0, 0.2, 0)
	player.velocity = Vector3.ZERO
	await physics_frame


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT % name)


func clear_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	await physics_frame


func _run() -> void:
	ps = root.get_node("PlayerState")
	ps.reset()
	change_scene_to_file("res://tests/test_arena.tscn")
	for i in 40:
		await physics_frame
	player = current_scene.get_node("Player")
	await clear_enemies()
	ps.god_mode = true
	await _kvald()
	await clear_enemies()
	await _kobolds()
	await clear_enemies()
	await _golem()
	ps.god_mode = false
	print("=== ОШИБОК: %d ===" % errors)
	quit(errors)


func _kvald() -> void:
	await put_player(Vector3(-3, 0, 0))
	var k := spawn("res://scripts/combat/kvald.gd", Vector3(-1, 0, 0))
	await wait(0.3)
	k.set_state("chase")
	k.look_towards(Vector3.LEFT)  # смотрит на Рэя
	var front: float = k.take_hit({"damage": 10.0, "dir": Vector3.RIGHT})
	check(is_equal_approx(front, 3.0), "квалд: удар в щит спереди — 30 %% (%s)" % front)
	k.look_towards(Vector3.LEFT)
	var back: float = k.take_hit({"damage": 10.0, "dir": Vector3.LEFT})
	check(is_equal_approx(back, 10.0), "квалд: удар сзади — полный (%s)" % back)
	k.look_towards(Vector3.LEFT)
	k.set_state("chase")
	k.take_hit({"damage": 5.0, "dir": Vector3.RIGHT, "heavy": true})
	check(k.state == "broken", "квалд: тяжёлый удар выбивает щит (%s)" % k.state)
	await put_player(Vector3(-6, 0, 0))
	player.set("_invulnerable", 0.0)
	k.call("_throw_mud")
	await wait(1.0)
	check(player.is_slowed() and player.is_blinded(), "грязь квалда: Рэй замедлен и ослеплён")
	await shot("kvald_mud")
	k.set_physics_process(false)  # иначе через 5 с бросит снова
	await wait(3.6)
	check(not player.is_slowed() and not player.is_blinded(), "через 3 с грязь сходит")
	k.set_physics_process(true)
	# Сам по себе: подходит и колет или кидает грязь.
	var seen := {}
	for i in 60:
		seen[k.state] = true
		await wait(0.1)
	check(seen.has("windup") or seen.has("throw"), "квалд сам нападает: %s" % ", ".join(seen.keys()))


func _kobolds() -> void:
	await put_player(Vector3(-7, 0, 0))
	var pack := []
	for p in [Vector3(3, 0, 3), Vector3(5, 0, -3), Vector3(6, 0, 2)]:
		pack.append(spawn("res://scripts/combat/kobold.gd", p, {"pack_id": "t"}))
	await wait(0.3)
	check(pack.all(func(k): return not k.is_alive()), "кобольды в засаде не видны и не бьются")
	await wait(1.5)
	var sink: float = pack.map(func(k): return absf(k.global_position.y - k.spawn_position.y)).max()
	check(sink < 0.3, "в засаде кобольды стоят на земле, а не проваливаются (%.2f м)" % sink)
	await put_player(Vector3(0, 0, 1))
	await wait(0.3)
	check(pack.all(func(k): return k.is_alive() and k.state == "chase"), "Рэй подошёл — стая выскочила разом")
	await shot("kobold_ambush")
	# Тактика стаи: расставим вручную и спросим урон удара.
	var at := Vector3(0, 0, 1)
	await put_player(at)
	pack[0].global_position = at + Vector3(1, 0, 0)
	pack[1].global_position = at + Vector3(10, 0, 0)
	pack[2].global_position = at + Vector3(10, 0, 3)
	check(is_equal_approx(pack[0].pack_damage(), 15.0), "один кобольд у Рэя — 15 (%s)" % pack[0].pack_damage())
	pack[1].global_position = at + Vector3(-1, 0, 0)
	check(is_equal_approx(pack[0].pack_damage(), 22.5), "двое с разных сторон — 22,5 (%s)" % pack[0].pack_damage())
	pack[2].global_position = at + Vector3(0, 0, 1)
	check(is_equal_approx(pack[0].pack_damage(), 30.0), "трое вокруг — 30, потолок +100 %% (%s)" % pack[0].pack_damage())
	pack[1].global_position = at + Vector3(1.2, 0, 0.3)
	pack[2].global_position = at + Vector3(10, 0, 3)
	check(is_equal_approx(pack[0].pack_damage(), 15.0), "союзник с той же стороны бонуса не даёт (%s)" % pack[0].pack_damage())
	# Бегство и исчезновение последнего.
	pack[0].take_hit({"damage": 16.0, "dir": Vector3.RIGHT})
	check(pack[0].state == "flee", "кобольд при HP ≤ 30 %% убегает (%s)" % pack[0].state)
	pack[1].take_hit({"damage": 100.0, "dir": Vector3.RIGHT})
	await wait(0.2)
	var coins_before := get_nodes_in_group("helios_pickups").size()
	pack[2].take_hit({"damage": 16.0, "dir": Vector3.RIGHT})
	await wait(0.2)
	check(pack[2].dead and not pack[2].visible, "последний живой кобольд скрылся в дыму")
	check(get_nodes_in_group("helios_pickups").size() == coins_before, "сбежавший — без награды")
	await put_player(Vector3(-7, 0, 0))  # подальше — иначе стая сразу выскочит снова
	pack[2].respawn()
	await wait(0.1)
	check(not pack[2].is_alive(), "после возрождения врагов кобольд снова в засаде")


func _golem() -> void:
	await put_player(Vector3(-5, 0, 0))
	var g := spawn("res://scripts/combat/mine_golem.gd", Vector3(-3, 0, 0))
	await wait(0.3)
	player.set("_invulnerable", 0.0)
	g.set_state("chase")
	g.call("_start_slam")
	await wait(1.3)
	check(float(player.get("_hurt_time")) > 0.5, "удар голема по земле оглушил Рэя (%s с)" % player.get("_hurt_time"))
	var p0 := player.global_position
	Input.action_press("move_left")
	await wait(0.4)
	Input.action_release("move_left")
	check(player.global_position.distance_to(p0) < 0.2, "оглушённый Рэй не двигается")
	await shot("golem_slam")
	await wait(1.0)
	# Валун: летит в место, где стоял Рэй; ушёл — промах.
	await put_player(Vector3(4, 0, 0))
	player.set("_invulnerable", 0.0)
	ps.god_mode = false
	ps.hp = 100.0
	g.set_state("lift")
	await wait(1.05)
	await shot("golem_boulder")
	await wait(1.0)
	check(ps.hp < 100.0, "валун попал по стоявшему Рэю (HP %s)" % ps.hp)
	ps.hp = 100.0
	player.set("_invulnerable", 0.0)
	g.set_state("lift")
	await wait(1.1)
	await put_player(Vector3(7, 0, 4))
	await wait(1.0)
	check(is_equal_approx(ps.hp, 100.0), "Рэй ушёл из метки — валун мимо")
	ps.god_mode = true
	# Стойкость: обычные удары не сбивают, накопленные 40 % HP — шатается.
	g.set_state("windup")
	g.take_hit({"damage": 20.0, "dir": Vector3.RIGHT})
	check(g.state == "windup", "один удар замах голема не сбивает")
	g.take_hit({"damage": 41.0, "dir": Vector3.RIGHT})
	check(g.state == "stagger", "набрав 40 %% HP за 3 с — шатается (%s)" % g.state)
	var boss := spawn("res://scripts/combat/mine_golem.gd", Vector3(4, 0, -3), {"boss": true})
	await wait(0.2)
	check(is_equal_approx(boss.max_hp, 400.0) and is_equal_approx(boss.hp, 400.0), "мини-босс: 400 HP")
