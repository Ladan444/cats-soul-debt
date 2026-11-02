extends SceneTree
## Возрождение у последнего зажжённого фонаря — и в другой локации (решение автора 2026-10-29): Рэй зажёг фонарь
## на арене, погиб в Рубеже, где фонарей не зажигал, — просыпается у фонаря арены; кучка утерянного — в Рубеже.
## Запуск: godot_run.ps1 htest Tools/godot/tests/respawn_test.gd

const ARENA := "res://tests/test_arena.tscn"
const RUBEZH := "res://scenes/levels/rubezh_f1.tscn"

var errors := 0


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("OK   " if cond else "FAIL ") + what)
	if not cond:
		errors += 1


func _run() -> void:
	var ps := root.get_node("PlayerState")
	ps.reset()
	ps.light_lantern(ARENA + ":SoulLanternLake")
	ps.add_helios(40)
	change_scene_to_file(RUBEZH)
	for i in 40:
		await physics_frame
	var player: Node3D = current_scene.get_node("Player")
	var died_at := player.global_position
	ps.damage(10000, died_at)
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == ARENA, "после смерти в Рубеже — переход к фонарю арены (%s)" % current_scene.scene_file_path)
	var lantern: Node3D = current_scene.get_node("Combat/SoulLanternLake")
	player = current_scene.get_node("Player")
	var d: float = player.global_position.distance_to(lantern.respawn_point())
	check(d < 0.6, "Рэй у фонаря (%.2f м)" % d)
	check(player.is_alive(), "Рэй жив и управляем")
	var marks: Array = ps.death_marks
	check(not marks.is_empty() and marks.back().get("scene", "") == RUBEZH, "кучка утерянного осталась в Рубеже")
	# Обычный случай не сломан: фонарь в этой же сцене — без смены сцены.
	ps.damage(10000, player.global_position)
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == ARENA, "фонарь в той же сцене — остаёмся на месте")
	d = current_scene.get_node("Player").global_position.distance_to(lantern.respawn_point())
	check(d < 0.6, "и снова у фонаря (%.2f м)" % d)
	print("=== ОШИБОК: %d ===" % errors)
	quit(errors)
