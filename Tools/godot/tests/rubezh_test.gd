extends SceneTree
## Тест этажа 1 Рубежа: ключ К1 → дверь оружейной, сундук, засов «в одну сторону», ложная стена от удара,
## три части ключа → сокровищница, сохранение открытого и подобранного.
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


func wait(s: float) -> void:
	await create_timer(s).timeout


func press(action: StringName) -> void:
	for p in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = p
		root.push_input(e)


func go(at: Vector3, facing := Vector3.FORWARD) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.set("_facing", facing)
	player.set("_invulnerable", 100.0)
	await wait(0.25)


func door(nm: String) -> Node3D:
	return scene.get_node("Ctl" + nm) as Node3D


func by_script(script_end: String) -> Array:
	return scene.find_children("*", "", true, false).filter(func(n): return n.get_script() and n.get_script().resource_path.ends_with(script_end))


func load_level() -> void:
	change_scene_to_file("res://scenes/levels/rubezh_f1.tscn")
	await wait(0.8)
	scene = current_scene
	player = scene.get_node("Player")
	# Враги не мешают проверке механик.
	for e in get_nodes_in_group("enemies"):
		e.set_physics_process(false)


func _run() -> void:
	ps = root.get_node("PlayerState")
	ps.reset()
	await load_level()
	var k1: int = ps.call("count_of", load("res://data/items/key_rubezh_k1.tres"))
	ok(k1 == 0, "в начале ключа К1 нет")

	print("— Ключ К1 и оружейная")
	var keys := by_script("key_pickup.gd")
	var key_k1 = keys.filter(func(k): return k.key_label == "К1")[0]
	await go(key_k1.global_position)
	await wait(0.3)
	ok(ps.count_of(load("res://data/items/key_rubezh_k1.tres")) == 1, "ключ К1 подобран")
	var armory := door("Door-key-barracks-armory")
	await go(armory.global_position + Vector3(0, 0, 1.4))
	ok(String(armory.prompt.text).contains("открыть"), "подсказка у двери: «%s»" % armory.prompt.text)
	press(&"interact")
	await wait(1.0)
	ok(armory.get("_open"), "оружейная открыта")
	ok(ps.count_of(load("res://data/items/key_rubezh_k1.tres")) == 0, "ключ потрачен")

	print("— Сундук")
	var chests := by_script("chest.gd")
	var chest: Node3D = chests[0]
	var helios0: int = ps.helios
	await go(chest.global_position + Vector3(0, 0, 1.2))
	press(&"interact")
	await wait(1.5)
	ok(chest.get("_opened"), "сундук открыт (%s)" % chest.get("contents"))
	# Монеты разлетаются из сундука — подойти к каждой (за секунду у сундука собираются не всегда).
	await wait(1.0)
	for coin in get_nodes_in_group("helios_pickups"):
		if is_instance_valid(coin):
			await go((coin as Node3D).global_position)
			await wait(0.3)
	ok(ps.helios > helios0 or chest.get("contents") == "настойки", "награда получена: гелиосы %d → %d" % [helios0, ps.helios])

	print("— Засов в одну сторону (затопленный зал → ворота)")
	var bolt := door("Door-oneway-flooded-gate")
	await go(bolt.global_position + Vector3(-1.4, 0, 0))  # со стороны ворот
	press(&"interact")
	await wait(0.5)
	ok(not bolt.get("_open"), "со стороны ворот не открыть: «%s»" % bolt.prompt.text)
	await go(bolt.global_position + Vector3(1.4, 0, 0))   # со стороны зала
	press(&"interact")
	await wait(1.0)
	ok(bolt.get("_open"), "из зала засов отодвинут")

	print("— Ложная стена (костница → ниша)")
	var secret := door("Door-secret-ossuary-niche")
	await go(secret.global_position + Vector3(0, 0, 1.3), Vector3.FORWARD)
	press(&"attack")
	await wait(1.0)
	ok(secret.get("_open"), "стена рухнула от удара")

	print("— Ключ сокровищницы из трёх частей")
	# Все три части — на этаже 1 (Глава 1: часть 2/3 перенесена в Затопленный зал).
	var parts: Array = keys.filter(func(k): return is_instance_valid(k) and k.key_label.begins_with("часть"))
	ok(parts.size() == 3, "на этаже 1 три части ключа (%d)" % parts.size())
	var part_item: Resource = load("res://data/items/key_treasury_part.tres")
	var treasury := door("Door-bigkey-mess-treasury")
	for i in parts.size():
		await go(parts[i].global_position)
		await wait(0.3)
		if i == 1:
			ok(ps.count_of(part_item) == 2, "собраны 2 части из 3 (%d)" % ps.count_of(part_item))
			await go(treasury.global_position + Vector3(0, 0, 1.4))
			press(&"interact")
			await wait(0.6)
			ok(not treasury.get("_open"), "без целого ключа заперто: «%s»" % treasury.prompt.text)
	ok(ps.count_of(load("res://data/items/key_treasury.tres")) == 1, "три части собрались в ключ сокровищницы")
	await go(treasury.global_position + Vector3(0, 0, 1.4))
	press(&"interact")
	await wait(1.0)
	ok(treasury.get("_open"), "сокровищница открыта")

	print("— Сохранение")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ps.to_dict()))
	ps.reset()
	ps.from_dict(saved)
	await load_level()
	ok(door("Door-key-barracks-armory").get("_open"), "оружейная открыта после загрузки")
	ok(door("Door-secret-ossuary-niche").get("_open"), "тайник открыт после загрузки")
	ok(by_script("chest.gd")[0].get("_opened"), "сундук пуст после загрузки")
	ok(by_script("key_pickup.gd").filter(func(k): return not k.is_queued_for_deletion()).is_empty(), "ключи не появились снова")

	print("\n=== ОШИБОК: %d ===" % fails.size())
	for f in fails:
		print("FAIL ", f)
	ps.reset()
	quit(1 if fails.size() > 0 else 0)
