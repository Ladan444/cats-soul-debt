extends SceneTree
## Камера, миниатюра и экранные эффекты (C01–C13): настройки камеры и пресеты, DOF,
## экранный шейдер, фоторежим (пауза, своя камера, снимок PNG, форматы, шаг кадра).
## Запуск (в окне — нужен настоящий кадр для снимка):
##   powershell -File Tools/godot_run.ps1 test Tools/godot/tests/camera_fx_test.gd

var fails: Array[String] = []

# Автозагрузки в -s не видны при компиляции — берём из дерева.
var _Settings: Node
var _SaveGame: Node
var _ScreenFX: Node
var _PhotoMode: Node


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func wait(s: float) -> void:
	await create_timer(s).timeout


func shot_dir() -> String:
	var f := load("res://scripts/core/user_files.gd")
	return f.path("screenshots/")


func pngs() -> PackedStringArray:
	var dir := DirAccess.open(shot_dir())
	var names := PackedStringArray()
	if dir == null:
		return names
	for f in dir.get_files():
		if f.to_lower().ends_with(".png"):
			names.append(f)
	return names


func clear_shots() -> void:
	var dir := DirAccess.open(shot_dir())
	if dir == null:
		return
	for f in pngs():
		dir.remove(f)


func find_row(menu: Control, label: String) -> SettingRow:
	for n in menu.find_children("*", "SettingRow", true, false):
		if n.label == label:
			return n
	return null


func _run() -> void:
	_Settings = root.get_node("Settings")
	_SaveGame = root.get_node("SaveGame")
	_ScreenFX = root.get_node("ScreenFX")
	_PhotoMode = root.get_node("PhotoMode")
	_Settings.set_value("tutorial_hints", false)
	clear_shots()

	# --- C01: значения по умолчанию и действия ввода ---
	ok(is_equal_approx(float(_Settings.get_value("camera_pitch")), 39.0), "наклон по умолчанию 39°")
	ok(is_equal_approx(float(_Settings.get_value("camera_distance")), 14.2), "дистанция по умолчанию 14,2 м")
	ok(InputMap.has_action("photo_mode") and InputMap.has_action("photo_step"), "действия фоторежима в InputMap")
	ok(_ScreenFX is CanvasLayer and _ScreenFX.layer == 0, "экранные эффекты на слое 0, ниже HUD")
	ok(_ScreenFX.get_child(0) is ColorRect, "у эффектов полноэкранный ColorRect")

	# --- C01/C02: камера уровня слушает настройки ---
	_SaveGame.new_game(1, "res://scenes/levels/tavern.tscn")
	await wait(2.0)
	var cam := current_scene.get_node("Camera3D")
	var off: Vector3 = cam.offset
	ok(absf(off.y - sin(deg_to_rad(39.0)) * 14.2) < 0.02, "offset.y из наклона и дистанции")
	ok(absf(off.z - cos(deg_to_rad(39.0)) * 14.2) < 0.02, "offset.z из наклона и дистанции")
	ok(absf(rad_to_deg(cam.rotation.x) + 39.0) < 0.5, "камера смотрит вниз на 39°")
	ok(is_equal_approx(cam.fov, 30.0), "FOV 30 из настроек")

	_Settings.set_value("camera_pitch", 60.0)
	await wait(0.1)
	ok(cam.offset.y > off.y and cam.offset.z < off.z, "наклон 60°: камера выше и ближе по глубине")
	ok(absf(rad_to_deg(cam.rotation.x) + 60.0) < 0.5, "поворот камеры обновился вместе с наклоном")

	# --- C01: высота — отдельный рычаг (поднимает камеру, не отдаляя её) ---
	_Settings.set_value("camera_pitch", 39.0)
	await wait(0.1)
	var base_y: float = cam.offset.y
	var base_z: float = cam.offset.z
	var base_tilt: float = rad_to_deg(cam.rotation.x)
	_Settings.set_value("camera_height", 2.5)
	await wait(0.1)
	ok(absf(cam.offset.y - (base_y + 2.5)) < 0.02, "высота 2,5 м поднимает камеру ровно на 2,5 м")
	ok(absf(cam.offset.z - base_z) < 0.02, "высота не отдаляет камеру")
	ok(rad_to_deg(cam.rotation.x) < base_tilt - 1.0, "камера доворачивается, чтобы Рэй остался в кадре")
	_Settings.set_value("camera_height", 0.0)
	await wait(0.1)
	ok(absf(cam.offset.y - base_y) < 0.02, "высота 0 возвращает прежний вид")

	_Settings.apply_camera_preset(3)   # «Сверху»
	ok(is_equal_approx(float(_Settings.get_value("camera_pitch")), 58.0), "пресет пишет наклон")
	ok(is_equal_approx(float(_Settings.get_value("camera_distance")), 13.0), "пресет пишет дистанцию")
	ok(is_equal_approx(float(_Settings.get_value("camera_height")), 1.5), "пресет пишет высоту")
	ok(int(_Settings.get_value("camera_preset")) == 3, "выбранный пресет запомнен")
	_Settings.apply_camera_preset(1)   # «Диорама» — как в игре

	# --- V: следующий вид камеры по кругу ---
	ok(InputMap.has_action("camera_view"), "действие camera_view в InputMap")
	var v := InputEventAction.new()
	v.action = "camera_view"
	v.pressed = true
	root.push_input(v)
	await wait(0.2)
	ok(int(_Settings.get_value("camera_preset")) == 2, "V переключает на следующий вид")
	ok(is_equal_approx(cam.fov, 32.0), "вместе с видом меняется FOV")
	_Settings.apply_camera_preset(4)
	root.push_input(v)
	await wait(0.2)
	ok(int(_Settings.get_value("camera_preset")) == 1, "после последнего вида V возвращает к первому")
	_Settings.apply_camera_preset(1)

	# --- предпросмотр: камера едет сразу, даже когда игра на паузе ---
	var pos_before: Vector3 = cam.global_position
	paused = true
	_Settings.set_value("camera_pitch", 70.0)
	await wait(0.6)
	ok(cam.global_position.distance_to(pos_before) > 0.5, "на паузе камера всё равно переезжает")
	paused = false
	_Settings.set_value("camera_pitch", 39.0)
	await wait(0.2)

	# --- C07: миниатюра (near+far DOF камеры) ---
	var attrs := cam.attributes as CameraAttributesPractical
	ok(attrs != null, "у камеры CameraAttributesPractical")
	ok(attrs.dof_blur_near_enabled and attrs.dof_blur_far_enabled, "DOF включён с двух сторон")
	ok(attrs.dof_blur_amount > 0.03 and attrs.dof_blur_amount <= 0.1, "сила DOF в разумных пределах (%.3f)" % attrs.dof_blur_amount)
	var strong: float = attrs.dof_blur_amount
	_Settings.set_value("miniature", 1.0)
	await wait(0.1)
	ok(attrs.dof_blur_amount > strong, "сильная миниатюра размывает больше")
	_Settings.set_value("miniature", 0.0)
	await wait(0.1)
	ok(not attrs.dof_blur_near_enabled and attrs.dof_blur_amount == 0.0, "миниатюра 0 выключает DOF")
	_Settings.set_value("miniature", 0.8)

	# --- C08: блум живёт в Environment и слушает ползунок ---
	var env_node := current_scene.find_children("*", "WorldEnvironment", true, false)
	var env: Environment = null
	if env_node.size() > 0:
		env = (env_node[0] as WorldEnvironment).environment
	ok(env != null, "в уровне есть WorldEnvironment")
	if env:
		_Settings.set_value("fx_bloom", 1.0)
		await wait(0.1)
		ok(env.glow_bloom > 0.2, "блум 100%% даёт заметное свечение (%.2f)" % env.glow_bloom)
		_Settings.set_value("fx_bloom", 0.0)
		await wait(0.1)
		ok(env.glow_bloom == 0.0 and env.glow_hdr_threshold > 0.99, "блум 0 выключает растекание")
		_Settings.set_value("fx_bloom", 0.35)

	# --- C13: пресет «слабый ПК» ---
	_Settings.set_value("fx_quality", 1)
	await wait(0.1)
	ok(attrs.dof_blur_amount == 0.0, "«слабый ПК» выключает DOF")
	_Settings.set_value("fx_quality", 0)

	# --- C06/C08: экранный шейдер живёт и не закрывает кадр ---
	await wait(0.4)
	ok(_ScreenFX.call("is_active"), "эффекты включились в уровне")
	await RenderingServer.frame_post_draw
	var shot: Image = root.get_texture().get_image()
	var mid := shot.get_pixel(shot.get_width() / 2, shot.get_height() / 2)
	ok(mid.v > 0.02, "экран не закрыт чёрным: центр кадра светлый")
	shot.save_png("C:/Temp/camera_fx_tavern.png")

	# --- настройки камеры в меню ---
	var menu: Control = load("res://scripts/ui/settings_menu.gd").new()
	root.add_child(menu)
	menu.call("open")   # open() сам строит вкладку «Изображение»
	await wait(0.2)
	var pitch_row := find_row(menu, "Наклон камеры")
	ok(pitch_row != null, "в настройках есть ползунок наклона камеры")
	if pitch_row:
		pitch_row.call("_set_value", 50.0)
		await wait(0.1)
		ok(is_equal_approx(float(_Settings.get_value("camera_pitch")), 50.0), "ползунок пишет наклон в Settings")
		ok(int(_Settings.get_value("camera_preset")) == 0, "ручная правка сбрасывает пресет на «Свои»")
	var preset_row := find_row(menu, "Вид камеры")
	ok(preset_row != null and preset_row.options.size() == 5, "пять пунктов вида камеры")

	# Предпросмотр: на строке камеры пергамент тает, на обычной — снова плотный.
	if pitch_row:
		pitch_row.grab_focus()
		await wait(0.6)
		var paper := menu.get("_panel") as NinePatchRect
		ok(paper.self_modulate.a < 0.6, "на строке камеры панель светлеет (%.2f)" % paper.self_modulate.a)
	var res_row := find_row(menu, "Разрешение")
	if res_row:
		res_row.grab_focus()
		await wait(0.6)
		var paper2 := menu.get("_panel") as NinePatchRect
		ok(paper2.self_modulate.a > 0.9, "на обычной строке панель снова плотная")
	menu.queue_free()
	_Settings.apply_camera_preset(1)

	# --- C03–C05, C11, C12: фоторежим ---
	ok(not _PhotoMode.call("is_open"), "фоторежим закрыт")
	_PhotoMode.call("open")
	await wait(0.4)
	ok(_PhotoMode.call("is_open"), "фоторежим открылся")
	ok(paused, "игра на паузе")
	var pcam = _PhotoMode.get("_cam")
	ok(pcam != null and pcam.current, "своя камера фоторежима стала главной")
	var hud := current_scene.get_node("HUD") as CanvasLayer
	ok(not hud.visible, "HUD спрятан")
	ok(_PhotoMode.find_child("PhotoUI", true, false).visible, "интерфейс фоторежима виден")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Temp/camera_fx_ui.png")

	# Поворот и зум камеры.
	var yaw0: float = _PhotoMode.get("_yaw")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = Vector2(300, 300)
	root.push_input(wheel)
	await wait(0.2)
	ok(float(_PhotoMode.get("_distance")) > 12.0, "колесо отдаляет камеру")
	ok(is_equal_approx(float(_PhotoMode.get("_yaw")), yaw0), "колесо не крутит камеру")

	# Снимок 16:9.
	_PhotoMode.call("take_shot")
	await wait(0.6)
	var files := pngs()
	ok(files.size() >= 1, "снимок сохранён в user://screenshots")
	if files.size() >= 1:
		var img := Image.load_from_file(shot_dir() + files[0])
		ok(img != null and not img.is_empty(), "снимок читается как PNG")
		if img:
			var aspect := float(img.get_width()) / float(img.get_height())
			ok(absf(aspect - 16.0 / 9.0) < 0.02, "снимок 16:9 (%.2f)" % aspect)
			img.save_png("C:/Temp/camera_fx_photo.png")

	# Снимок 1:1 — обрезается по центру.
	_PhotoMode.set("_format", 2)
	_PhotoMode.call("take_shot")
	await wait(0.6)
	files = pngs()
	var square := ""
	for f in files:
		if f > square:
			square = f
	var sq := Image.load_from_file(shot_dir() + square)
	ok(sq != null and absf(float(sq.get_width()) / float(sq.get_height()) - 1.0) < 0.02, "снимок 1:1 обрезан по центру")
	_PhotoMode.set("_format", 0)

	# Шаг кадра (C11): мир сдвигается ровно на кадр и снова замирает.
	var pos0: Vector3 = current_scene.get_node("Player").global_position
	_PhotoMode.call("step_frame")
	await wait(0.3)
	ok(paused, "после шага кадра пауза вернулась")
	ok(current_scene.get_node("Player").global_position.distance_to(pos0) < 0.5, "игрок не убежал за шаг кадра")

	# Галерея (C12).
	_PhotoMode.call("_show_gallery", true)
	await wait(0.2)
	var grid := _PhotoMode.find_child("Gallery", true, false)
	ok(grid != null and grid.visible, "галерея открывается")
	var thumbs := 0
	for n in grid.find_children("*", "TextureButton", true, false):
		thumbs += 1
	for n in grid.find_children("*", "Button", true, false):
		if n.icon != null:
			thumbs += 1
	ok(thumbs >= 1, "в галерее есть превью снимков (%d)" % thumbs)

	_PhotoMode.call("close")
	await wait(0.3)
	ok(not _PhotoMode.call("is_open"), "фоторежим закрылся")
	ok(not paused, "пауза снята")
	ok(hud.visible, "HUD вернулся")
	ok(cam.current, "игровая камера снова главная")

	clear_shots()
	print("=== ОШИБОК: %d ===" % fails.size())
	quit(1 if fails.size() > 0 else 0)
