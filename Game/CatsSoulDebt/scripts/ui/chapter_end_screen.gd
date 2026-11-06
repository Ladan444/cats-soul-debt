class_name ChapterEndScreen
extends CanvasLayer
## Экран после финала главы: «Конец Главы 1» → титры с именами разработчиков → «Ждите продолжения…» и кнопка
## «В главное меню». Показывается сразу после финала (chapter1_finale.gd) и при «Продолжить» из главного меню,
## если сохранение — после финала (решение автора 2026-10-27). Enter/Esc/клик пропускают титры.

const FONT_GOLD := Color("e8c870")
const INK := Color("e6d6b0")
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const SCROLL_SPEED := 14.0   ## UI-пикселей в секунду

var _root: UIScaler
var _scroll_tween: Tween
var _skipped := false
var _intro_tween: Tween
var _intro := true
var _credits: Label
var _final_box: Control
var _menu_button: ClawButton


## Открыть поверх текущей сцены.
## intro = false — когда перед этим уже показали карточку «Конец Главы 1» (финал): сразу титры.
static func open(tree: SceneTree, intro := true) -> void:
	var screen := ChapterEndScreen.new()
	screen._intro = intro
	tree.root.add_child(screen)


## Сохранение — после финала главы 1 (задание chapter1 пройдено)? «Продолжить» тогда ведёт сюда, а не в сцену.
static func save_is_finished() -> bool:
	if not FileAccess.file_exists(SaveGame.PATH):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var active: Dictionary = data.get("quests", {}).get("active", {})
	return int(active.get("chapter1", -1)) >= QuestState.QUESTS["chapter1"]["steps"].size()


## Текст титров и экрана «Авторы» (одна копия на оба места). Состав — по Проект/LEGAL.md; подписываем
## никами (решение автора, окончательное): настоящие имена в игре не указываются.
static func credits_text() -> String:
	return ("Долг Кошачьей Души
Бета 0.0.3

"
		+ "Идея, мир, сюжет, арт-дирекшн
Ladan444

"
		+ "Сценарий
s1k1game

"
		+ "Художница
Waisy Strall

"
		+ "Код и инструменты
с помощью Claude

"
		+ "Часть арта — временные генерации ИИ,
они будут заменены рисунками художников.

"
		+ "Шрифты Public Pixel и First Time Writing — GGBotNet (CC0)
"
		+ "Движок — Godot Engine (лицензия MIT, © Juan Linietsky, Ariel Manzur и разработчики Godot)

"
		+ "Музыка (OpenGameArt.org)
" + Audio.music_credits() + "

"
		+ "Звуки — Kenney (CC0), OpenGameArt.org
"
		+ "Модели — Quaternius (Medieval Village MegaKit, Ultimate Stylized Nature Pack), KayKit (CC0)

"
		+ "Спасибо, что дошли до конца.")


func _ready() -> void:
	layer = 40
	add_to_group("scene_transition")
	process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(black)
	_root = UIScaler.new()
	_root.min_canvas = Vector2(400, 240)
	black.add_child(_root)
	_play.call_deferred()


func _play() -> void:
	if not _intro:
		_start_credits()
		return
	var title := _label("Конец Главы 1", 16, FONT_GOLD)
	title.modulate.a = 0.0
	_center(title, _root.size.y / 2.0 - 8)
	_root.add_child(title)
	var t := create_tween()
	t.tween_property(title, "modulate:a", 1.0, 1.5)
	t.tween_interval(2.5)
	t.tween_property(title, "modulate:a", 0.0, 1.0)
	_intro_tween = t
	await t.finished
	if _skipped or not is_inside_tree():
		return
	_start_credits()


func _start_credits() -> void:
	_credits = _label(credits_text(), 8, INK)
	_credits.autowrap_mode = TextServer.AUTOWRAP_WORD
	_credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var w := minf(_root.size.x - 60.0, 360.0)
	_credits.custom_minimum_size.x = w
	_credits.size = Vector2(w, 0)
	_credits.position = Vector2(floorf((_root.size.x - w) / 2.0), _root.size.y)
	_root.add_child(_credits)
	await get_tree().process_frame   # высота текста известна после раскладки
	if _skipped or not is_instance_valid(_credits):
		return   # титры пропустили в первый кадр — _credits уже освобождён
	var h := _credits.get_combined_minimum_size().y
	var dist := _root.size.y + h
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_credits, "position:y", -h, dist / SCROLL_SPEED)
	_scroll_tween.tween_callback(_show_final)


func _show_final() -> void:
	if _final_box != null:
		return
	_skipped = true
	if _scroll_tween:
		_scroll_tween.kill()
	if _credits:
		_credits.queue_free()
	_final_box = Control.new()
	_final_box.size = _root.size
	_final_box.modulate.a = 0.0
	_root.add_child(_final_box)
	var head := _label("Ждите продолжения…", 16, FONT_GOLD)
	_center(head, _root.size.y / 2.0 - 30)
	_final_box.add_child(head)
	var sub := _label("Глава 2 ещё пишется. Ваше сохранение ждёт — «Продолжить» вернёт сюда.", 8, INK)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.custom_minimum_size.x = minf(_root.size.x - 60.0, 300.0)
	sub.size = Vector2(sub.custom_minimum_size.x, 0)
	sub.position = Vector2(floorf((_root.size.x - sub.custom_minimum_size.x) / 2.0), _root.size.y / 2.0 + 4)
	_final_box.add_child(sub)
	_menu_button = ClawButton.new("В главное меню")
	_menu_button.size = Vector2(110, 12)
	_menu_button.position = Vector2(floorf((_root.size.x - 110) / 2.0), _root.size.y / 2.0 + 40)
	_menu_button.pressed.connect(_to_menu)
	_final_box.add_child(_menu_button)
	create_tween().tween_property(_final_box, "modulate:a", 1.0, 1.0)
	_menu_button.grab_focus()


func _input(event: InputEvent) -> void:
	# Пока кнопки «В главное меню» нет, экран забирает Enter/Esc/клик/кнопку геймпада себе (иначе они «нажимали»
	# пункт меню под экраном) и пропускает карточку и титры.
	if _final_box != null:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") 			or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		if _credits != null:
			_show_final()
		elif _intro_tween != null and _intro_tween.is_valid():
			_intro_tween.kill()
			_intro_tween = null
			_start_credits()


func _to_menu() -> void:
	Engine.time_scale = 1.0
	var tree := get_tree()
	var scene := tree.current_scene
	var already_in_menu := scene != null and scene.scene_file_path == MAIN_MENU
	queue_free()
	if not already_in_menu:
		tree.change_scene_to_file(MAIN_MENU)
	elif scene:
		# Кнопка с фокусом исчезла — возвращаем фокус пунктам главного меню (иначе клавиатура и геймпад мертвы).
		var menu := scene.find_child("MainMenu", true, false)
		if menu and menu.has_method("_back_to_menu"):
			menu.call_deferred("_back_to_menu")


func _center(l: Label, y: float) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, y)
	l.size = Vector2(_root.size.x, 18)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("2a1e18"))
	l.add_theme_constant_override("outline_size", 2)
	return l
