class_name Chapter1Finale
extends Node3D
## Финал Главы 1 в Большом зале, у круга печати (Литература/CHAPTER1.md, черновик).
## Рэй входит в зал на шаге «к кругу» → граф снимает перчатку, показывает строку контракта,
## из темноты выходит Покупатель, медальон теплеет, поднимается вода и фиолетовый туман → «Конец Главы 1»
## → главное меню. Задание получает события «place:great_hall» и «chapter_end».

const VELMOR_SHEET := preload("res://assets/sprites/velmor/velmor_combat.png")
const BUYER := preload("res://assets/sprites/story/buyer_silhouette.png")
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
## Сцена начинается, когда Рэй подошёл к кругу на это расстояние (граф стоит в центре круга).
const RADIUS := 5.0

var _player: Node3D
var _started := false
var _velmor: Sprite3D
var _buyer: Sprite3D


func _ready() -> void:
	_build_circle()
	_velmor = _sprite(VELMOR_SHEET, 4, 21, Vector3(0, 0.9, -0.5))
	_buyer = _sprite(BUYER, 1, 1, Vector3(2.6, 1.1, -2.6))
	_buyer.modulate = Color(1, 1, 1, 0)


## Круг печати из чёрного камня (CANON): тёмный диск, по краю — тусклое фиолетовое кольцо из пиксельных рун.
func _build_circle() -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.6
	cyl.bottom_radius = 3.6
	cyl.height = 0.08
	cyl.radial_segments = 24
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.07, 0.07, 0.09)
	stone.roughness = 0.4
	cyl.material = stone
	disc.mesh = cyl
	disc.position.y = 0.04
	add_child(disc)
	var rune := StandardMaterial3D.new()
	rune.albedo_color = Color(0.55, 0.3, 0.85)
	rune.emission_enabled = true
	rune.emission = Color(0.55, 0.3, 0.85)
	rune.emission_energy_multiplier = 1.5
	for i in 18:
		var a := TAU * i / 18.0
		var r := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.35 if i % 2 == 0 else 0.15, 0.02, 0.15)
		box.material = rune
		r.mesh = box
		r.position = Vector3(cos(a) * 3.1, 0.09, sin(a) * 3.1)
		r.rotation.y = -a
		add_child(r)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.55, 0.3, 0.85)
	glow.light_energy = 1.2
	glow.omni_range = 6.0
	glow.position.y = 0.6
	add_child(glow)


func _sprite(tex: Texture2D, h: int, v: int, pos: Vector3) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = h
	s.vframes = v
	s.pixel_size = 0.025
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.position = pos
	s.visible = false
	add_child(s)
	return s


func _process(_delta: float) -> void:
	if _started:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	var d := _player.global_position - global_position
	d.y = 0
	# «chapter_end» — сохранились посреди финала (закрыли окно): сцену нужно сыграть заново, иначе глава
	# застрянет на последнем шаге навсегда.
	var waiting := QuestState.waiting_for("chapter1")
	if d.length() < RADIUS and waiting in ["place:great_hall", "chapter_end"]:
		_started = true
		QuestState.notify("place:great_hall")
		_play()


func _play() -> void:
	_player.set("input_locked", true)
	var box := get_tree().current_scene.get_node_or_null("DialogueBox")
	_velmor.visible = true
	_velmor.modulate = Color(1, 1, 1, 0)
	await create_tween().tween_property(_velmor, "modulate:a", 1.0, 1.2).finished
	var given := PlayerState.souls.filter(func(e): return e["state"] == SoulData.State.GIVEN).size()
	await _say(box, "Граф Вельмор", [
		"Вот и всё, Рэй. Знамя. Шкатулка." + (" Души." if given > 0 else ""),
		"(Граф медленно стягивает перчатку. На ладони светятся строки — тот самый контракт.)",
		"Ты так и не дочитал. Здесь, внизу, мелко. Я всегда пишу мелко.",
		"«…по уплате долга душа заёмщика переходит в распоряжение заимодавца».",
		"Долг погашен." if given > 0 else "Неважно, отдал ли ты мне души. Главное — подпись.",
	])
	_buyer.visible = true
	await create_tween().tween_property(_buyer, "modulate:a", 1.0, 2.0).finished
	await _say(box, "Граф Вельмор", ["Сделка честная. Он сам подписал."])
	await _say(box, "???", ["Девять жизней… и десятая, взаймы. Я долго ждал этого тела."])
	if PlayerState.count_of(ContentDB.item(&"liara_medallion")) > 0:
		await _say(box, "Рэй", ["(Медальон в руке становится горячим. Чей-то смех — далеко, будто под водой.)"])
	_rise_water()
	await get_tree().create_timer(3.0, false).timeout
	QuestState.notify("chapter_end")
	# Сохранение после финала: «Продолжить» из меню ведёт на экран «Ждите продолжения» (ChapterEndScreen).
	SaveGame.save(get_tree().current_scene.scene_file_path, _player.global_position)
	_end_card()


func _say(box: Node, speaker: String, lines: Array) -> void:
	if box == null:
		await get_tree().create_timer(1.0).timeout
		return
	box.play(speaker, PackedStringArray(lines))
	await box.finished


## Вода из трещин круга, фиолетовый туман Хозяина, тряска.
func _rise_water() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 24)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.12, 0.45, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.4, 0.15, 0.6)
	m.emission_energy_multiplier = 0.6
	plane.material = m
	water.mesh = plane
	water.position.y = -0.5
	add_child(water)
	create_tween().tween_property(water, "position:y", 1.8, 3.0)
	CombatFX.shake(0.8)
	var env := get_viewport().world_3d.environment
	if env == null:
		var we := get_tree().current_scene.get_node_or_null("Atmosphere") as WorldEnvironment
		env = we.environment if we else null
	if env:
		var t := create_tween().set_parallel()
		t.tween_property(env, "fog_light_color", Color(0.45, 0.12, 0.6), 2.5)
		t.tween_property(env, "fog_density", 0.08, 2.5)
	for i in 6:
		CombatFX.burst(global_position + Vector3(randf_range(-4, 4), 0.2, randf_range(-4, 4)), Color(0.6, 0.3, 0.9), Vector3.UP, 20, 3.0, 1.0, 0.1, 1.2)


## Чёрный экран, «Конец Главы 1», затем титры и «Ждите продолжения» (ChapterEndScreen).
func _end_card() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.add_to_group("scene_transition")
	get_tree().root.add_child(layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	var label := Label.new()
	label.text = "Конец Главы 1\n\nДолг"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_override("font", CombatFX.FONT)
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color("e8c870"))
	label.modulate.a = 0.0
	layer.add_child(label)
	var t := layer.create_tween()
	t.tween_property(black, "color:a", 1.0, 2.0)
	t.tween_property(label, "modulate:a", 1.0, 1.5)
	t.tween_interval(3.0)
	t.tween_callback(func():
		Engine.time_scale = 1.0
		layer.queue_free()
		ChapterEndScreen.open(get_tree(), false))

