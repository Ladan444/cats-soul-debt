extends SceneTree
## Зелья Ларпа (BALANCE 3.4а, NPC_DRAFTS «Рецепты»): каждое лечит и даёт свой эффект, лучше настоек Марты.
## Эффект снимается по времени и при смерти, в сохранение не попадает, старое сохранение загружается.
## Запуск: powershell -File Tools/godot_run.ps1 htest Tools/godot/tests/larp_potions_test.gd

var errors := 0
var ps: Node
var tod: Node
var player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("OK   " if cond else "FAIL ") + what)
	if not cond:
		errors += 1


func wait(s: float) -> void:
	await create_timer(s).timeout


## Выпить зелье с низким здоровьем: возвращает, сколько вылечило.
func drink(id: String) -> float:
	var item: ItemData = load("res://data/items/%s.tres" % id)
	ps.add_item(item, 1)
	ps.hp = 10.0
	var count0: int = ps.count_of(item)
	check(ps.start_use(item), "%s: выпито" % id)
	check(ps.count_of(item) == count0 - 1, "%s: склянка потрачена" % id)
	check(item.description.contains("%d HP" % int(item.heal)), "%s: лечение есть в описании" % id)
	return ps.hp - 10.0


## Истечение: дать эффекту почти кончиться и подождать.
func expire(kind: StringName) -> void:
	ps.buffs[kind]["left"] = 0.05
	await wait(0.2)


## Скорость идущего Рэя вправо, м/с.
func walk_speed_now() -> float:
	Input.action_press("move_right")
	await wait(0.5)
	var v: float = absf(player.velocity.x)
	Input.action_release("move_right")
	await wait(0.2)
	return v


func _run() -> void:
	ps = root.get_node("PlayerState")
	tod = root.get_node("TimeOfDay")
	ps.reset()
	change_scene_to_file("res://tests/test_arena.tscn")
	for i in 40:
		await physics_frame
	player = current_scene.get_node("Player")
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	await physics_frame
	player.global_position = Vector3(0, 0.2, 0)
	var brew: ItemData = load("res://data/items/marta_brew.tres")
	var tincture: ItemData = load("res://data/items/tincture_liara.tres")

	# Тоник: лечит сильнее взвара Марты.
	var healed: float = await drink("larp_tonic")
	check(is_equal_approx(healed, 80.0) and healed > brew.heal, "тоник лечит 80, взвар Марты %d" % int(brew.heal))

	# Бодрящий настой: энергия сразу и вдвое быстрее восстанавливается.
	ps.energy = 0.0
	healed = await drink("larp_vigor")
	check(is_equal_approx(healed, 40.0) and healed > tincture.heal, "настой лечит 40, настойка Лиары %d" % int(tincture.heal))
	check(is_equal_approx(ps.energy, 60.0), "настой: +60 энергии (%s)" % ps.energy)
	ps.energy = 0.0
	await wait(1.0)
	var fast: float = ps.energy
	check(fast > ps.energy_regen * 1.5, "настой: энергия копится вдвое быстрее (%.1f за 1 с)" % fast)
	await expire(&"regen")
	check(ps.buff_power(&"regen") == 0.0, "настой: эффект снят по времени")
	ps.energy = 0.0
	await wait(1.0)
	check(ps.energy < fast * 0.7, "настой: восстановление снова обычное (%.1f)" % ps.energy)

	# Каменная кожа: защита растёт, урон на треть меньше, потом всё как было.
	var def0: float = ps.defense
	await drink("larp_stoneskin")
	check(is_equal_approx(ps.defense, def0 + 50.0), "каменная кожа: защита +50 (%s → %s)" % [def0, ps.defense])
	ps.hp = 100.0
	ps.damage(30.0, player.global_position)
	var with_skin: float = 100.0 - ps.hp
	await expire(&"defense")
	check(is_equal_approx(ps.defense, def0), "каменная кожа: защита вернулась по времени (%s)" % ps.defense)
	ps.hp = 100.0
	ps.damage(30.0, player.global_position)
	var without: float = 100.0 - ps.hp
	check(with_skin < without * 0.75, "каменная кожа: удар солдата %.1f вместо %.1f" % [with_skin, without])

	# Лёгкий шаг: Рэй реально идёт быстрее.
	var v0: float = await walk_speed_now()
	await drink("larp_swift")
	var v1: float = await walk_speed_now()
	check(v1 > v0 * 1.25, "лёгкий шаг: скорость %.2f → %.2f" % [v0, v1])
	await expire(&"speed")
	var v2: float = await walk_speed_now()
	check(is_equal_approx(v2, v0), "лёгкий шаг: скорость вернулась по времени (%.2f)" % v2)

	# Ночной глаз: свет вокруг Рэя ночью, днём гаснет.
	tod.paused = true
	await drink("larp_nightsight")
	tod.set_hour(1.0)
	await wait(0.1)
	var light: OmniLight3D = player.get("_night_light")
	check(light != null and light.visible and light.light_energy > 1.0, "ночной глаз: ночью светло")
	tod.set_hour(12.0)
	await wait(0.1)
	check(not light.visible, "ночной глаз: днём свет не нужен")
	tod.set_hour(1.0)
	await expire(&"night")
	await wait(0.1)
	check(not light.visible, "ночной глаз: свет погас по времени")
	tod.paused = false

	# Сердце зимы: удары созданий тумана вдвое слабее, остальные как обычно.
	await drink("larp_frost")
	ps.hp = 100.0
	player.set("_invulnerable", 0.0)
	player.take_hit({"damage": 40.0, "dir": Vector3.RIGHT, "knockback": 0.0, "mist": true})
	var mist: float = 100.0 - ps.hp
	ps.hp = 100.0
	player.set("_invulnerable", 0.0)
	player.take_hit({"damage": 40.0, "dir": Vector3.RIGHT, "knockback": 0.0})
	var plain: float = 100.0 - ps.hp
	check(is_equal_approx(mist, plain * 0.5), "сердце зимы: туман %.1f, обычный удар %.1f" % [mist, plain])
	await expire(&"mist")
	ps.hp = 100.0
	player.set("_invulnerable", 0.0)
	player.take_hit({"damage": 40.0, "dir": Vector3.RIGHT, "knockback": 0.0, "mist": true})
	check(is_equal_approx(100.0 - ps.hp, plain), "сердце зимы: эффект снят по времени")
	player.set("_invulnerable", 5.0)

	# Сохранение: эффекты не пишутся, загрузка снимает, старое сохранение без них загружается.
	var stone: ItemData = load("res://data/items/larp_stoneskin.tres")
	ps.hp = 100.0
	ps.add_buff(stone.buff, stone.buff_power, stone.buff_time, stone.name)
	var defended: float = ps.defense
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ps.to_dict()))
	check(not saved.has("buffs"), "эффекты в сохранение не попадают")
	ps.from_dict(saved)
	check(ps.buffs.is_empty() and ps.defense < defended, "после загрузки эффектов нет, защита обычная (%s)" % ps.defense)
	saved.erase("hp")
	ps.from_dict(saved)
	check(ps.buffs.is_empty(), "старое сохранение загружается")

	# Смерть снимает всё.
	for kind in [&"defense", &"speed", &"regen", &"night", &"mist"]:
		ps.add_buff(kind, 1.0, 60.0, "зелье")
	ps.damage(100000.0, player.global_position)
	check(ps.buffs.is_empty(), "смерть снимает все эффекты")
	check(is_equal_approx(ps.defense, def0), "защита после смерти обычная (%s)" % ps.defense)

	print("=== ОШИБОК: %d ===" % errors)
	quit(errors)
