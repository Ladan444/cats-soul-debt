extends SceneTree
## Музыка (scripts/core/audio.gd): в мире днём и ночью — свои дорожки, бой (враг заметил Рэя) — боевая, после боя
## прежняя дорожка продолжается с того же места; прослушивание из мастер-меню (override); таверна; «Авторы» в меню.
## Рубеж: эхо шагов и ударов (реверберация шины SFX), пыль, дымка, капли со звуком; все звуки Audio.SFX загружаются.
## Скриншот Рубежа — Арт/Скриншоты/rubezh_atmosphere.png.
## Запуск (в окне): Godot_console --resolution 1280x720 --path Game/CatsSoulDebt -s <абсолютный путь к файлу>

var fails := 0
var audio: Node
var tod: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func wait(sec: float) -> void:
	await create_timer(sec).timeout


func playing_file() -> String:
	var p: AudioStreamPlayer = audio.get("_music")[audio.get("_music_i")]
	return p.stream.resource_path.get_file() if p.playing and p.stream else ""


func _run() -> void:
	audio = root.get_node("Audio")
	tod = root.get_node("TimeOfDay")
	var saved_hour: float = tod.hour
	var saved_paused: bool = tod.paused
	tod.paused = true
	tod.set_hour(12.0)
	change_scene_to_file("res://scenes/levels/world.tscn")
	await wait(3.0)
	check(audio.current_track() == "sylvan_waltz" and playing_file() == "sylvan_waltz.mp3",
		"мир днём: %s (%s)" % [audio.current_track(), playing_file()])
	tod.set_hour(23.0)
	await wait(2.5)
	check(audio.current_track() == "beyond_the_stars", "мир ночью: %s" % audio.current_track())
	await wait(2.0)

	# Враг, заметивший Рэя, рядом с ним — боевая дорожка.
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar state := \"chase\"\nvar dead := false\n"
	gs.reload()
	var foe := Node3D.new()
	foe.set_script(gs)
	foe.add_to_group("enemies")
	current_scene.add_child(foe)
	var player: Node3D = current_scene.get_node("Player")
	foe.global_position = player.global_position + Vector3(3, 0, 0)
	var night_player: AudioStreamPlayer = audio.get("_music")[audio.get("_music_i")]
	var night_pos := night_player.get_playback_position()
	await wait(1.2)
	check(audio.current_track() == "regular_battle", "враг заметил Рэя — боевая музыка: %s" % audio.current_track())
	foe.set("state", "idle")
	await wait(2.0)
	check(audio.current_track() == "regular_battle", "сразу после боя боевая ещё звучит (задержка)")
	await wait(4.5)
	check(audio.current_track() == "beyond_the_stars", "после боя — снова ночная: %s" % audio.current_track())
	var resumed: AudioStreamPlayer = audio.get("_music")[audio.get("_music_i")]
	check(resumed.get_playback_position() > night_pos, "ночная продолжилась с места (%.1f > %.1f с)" % [
		resumed.get_playback_position(), night_pos])
	foe.queue_free()

	# Прослушивание из мастер-меню.
	var cheats: Node = root.get_node("Cheats")
	cheats.call("_cycle_music", 1)
	await wait(0.8)
	var first: String = audio.current_track()
	cheats.call("_cycle_music", 1)
	await wait(0.8)
	check(audio.override != "" and audio.current_track() != first, "◀ ▶ перебирают дорожки: %s → %s" % [first, audio.current_track()])
	audio.override = "-"
	await wait(0.8)
	check(playing_file() == "" or audio.current_track() == "-", "«Тишина» глушит музыку")
	audio.override = ""
	await wait(0.8)
	check(audio.current_track() == "beyond_the_stars", "«По сцене» — снова музыка места")

	check(not audio.reverb_on(), "в мире эха нет")
	var bad := []
	for sfx_name in audio.SFX:
		for f in audio.SFX[sfx_name][0]:
			var path: String = "res://assets/audio/sfx/" + f + ("" if "." in f else ".ogg")
			if not ResourceLoader.exists(path):
				bad.append(path)
	check(bad.is_empty(), "все звуки на месте %s" % str(bad))

	# Рубеж: эхо, пыль, капли.
	change_scene_to_file("res://scenes/levels/rubezh_f1.tscn")
	await wait(3.0)
	check(audio.reverb_on(), "в Рубеже шаги и удары с эхом")
	var amb: Node = current_scene.get_node("Ambience")
	check(amb.get_node_or_null("Пыль") != null and amb.get_node_or_null("Дымка") != null, "в Рубеже пыль и дымка")
	var drops := 0
	for i in 30:
		await wait(0.1)
		for c in amb.get_children():
			if c is MeshInstance3D:
				drops += 1
	check(drops > 0, "с потолка падают капли (%d кадров с каплей)" % drops)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/Ladan444/Desktop/The cat's soul debt GAMEDEV/Арт/Скриншоты/rubezh_atmosphere.png")
	var soldier: Node = null
	for e in get_nodes_in_group("enemies"):
		if e.get("hit_sound") == "hit_armor":
			soldier = e
	check(soldier != null and soldier.get("aggro_sound") == "soldier_moan", "у Утопшего солдата свои звуки")

	# Таверна и меню.
	change_scene_to_file("res://scenes/levels/tavern.tscn")
	await wait(2.5)
	check(audio.current_track() == "old_tower_inn", "таверна: %s" % audio.current_track())
	check(audio.reverb_on(), "в таверне лёгкое эхо")
	await wait(2.0)
	# Назад в мир: фон (птицы и ветер) снова звучит — раньше после сцены без фона он молчал до конца игры.
	change_scene_to_file("res://scenes/levels/world.tscn")
	await wait(3.0)
	var amb_player: AudioStreamPlayer = audio.get("_ambient")[audio.get("_ambient_i")]
	check(amb_player.playing and amb_player.volume_db > -30.0, "таверна → мир: фон снова звучит (%.0f дБ)" % amb_player.volume_db)
	tod.set_hour(23.0)
	await wait(0.6)
	tod.set_hour(12.0)
	await wait(0.6)
	var music_players: Array = audio.get("_music")
	var both := 0
	for mp in music_players:
		if (mp as AudioStreamPlayer).playing:
			both += 1
	check(audio.current_track() == "sylvan_waltz" and both >= 1, "день → ночь → день быстро: дневная звучит")
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await wait(2.5)
	check(audio.current_track() == "death_path", "главное меню: %s" % audio.current_track())
	var found := false
	for l in current_scene.find_children("*", "Label", true, false):
		if "Otto Halmén" in (l as Label).text and "Matthew Pablo" in (l as Label).text:
			found = true
	check(found, "в «Авторах» перечислены авторы музыки")

	tod.set_hour(saved_hour)
	tod.paused = saved_paused
	print("ИТОГ: ", "всё хорошо" if fails == 0 else "ошибок %d" % fails)
	quit(fails)
