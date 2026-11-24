class_name TutorialHints
extends Control
## Ненавязчивые подсказки управления в начале игры. Плашка внизу над хотбаром с картинками клавиш
## (KeyGlyph — клавиатура/геймпад сами меняются), появляется по первой подходящей ситуации и гаснет,
## когда игрок сделал нужное. Каждая подсказка показывается один раз: показанное хранится в PlayerState.taken
## («hint:<id>») — новая игра начинает обучение заново, сохранение его помнит.
## Выключается в настройках («Подсказки обучения»). Живёт в HUD; пока открыто меню (пауза), стоит.
##
## Текст: «{действие}» — картинка клавиши этого действия, «{move}» — четыре клавиши движения (или стик).

const PLANK := preload("res://assets/ui/plank.png")
const SHOW_TIME := 9.0       ## сколько висит подсказка, если игрок так и не сделал нужное
const GAP_TIME := 2.5        ## пауза между подсказками
const CHECK_STEP := 0.25     ## как часто проверять условия появления
const WALK_FOR_RUN := 25.0   ## метров ходьбы до подсказки про бег

## id → {text, order}. Когда показывать — в _trigger(), чем гасить — в _satisfied().
const HINTS := {
	"move": {"text": "Идти: {move}"},
	"interact": {"text": "{interact} — поговорить и осмотреть"},
	"run": {"text": "Бег: {run}   Рывок: {dash}"},
	"run_empty": {"text": "Рэй выдохся — пара секунд шагом, и бег вернётся"},
	"attack": {"text": "Удар: {attack}"},
	"dash": {"text": "Рывок: {dash} — уклонись от удара"},
	"book": {"text": "Новая вещь! Книга: {inventory}"},
	"map": {"text": "Карта этажа: {journal}. Миникарта — в углу"},
	"death": {"text": "Потерянные гелиосы лежат там, где ты пал — вернись за ними"},
	"lantern": {"text": "Фонарь душ — место возрождения. Зажги: {interact}"},
}
## Очередь проверки: раньше — важнее.
const ORDER := ["death", "lantern", "attack", "dash", "interact", "book", "map", "move", "run", "run_empty"]

var _plank: NinePatchRect
var _row: HBoxContainer
var _current: String = ""
var _shown_for: float = 0.0
var _gap: float = 0.0
var _timer: float = 0.0
var _scene_time: float = 0.0
var _walked: float = 0.0
var _last_pos := Vector3.INF
var _inventory_count: int = 0
var _new_item: bool = false
var _attacked_at: float = -1.0
var _player: Node3D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plank = NinePatchRect.new()
	_plank.texture = PLANK
	for side in ["left", "right", "top", "bottom"]:
		_plank.set("patch_margin_" + side, 7)
	_plank.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_plank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plank.visible = false
	add_child(_plank)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 3)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plank.add_child(_row)
	_inventory_count = _count_items()
	PlayerState.items_changed.connect(_on_items_changed)
	InputGlyphs.device_changed.connect(func(_g): if _current != "": _build(_current))


func _count_items() -> int:
	var n := 0
	for e in PlayerState.inventory:
		n += int(e["count"])
	return n


func _on_items_changed() -> void:
	var n := _count_items()
	if n > _inventory_count and _scene_time > 1.0:
		_new_item = true
	_inventory_count = n


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_scene_time += delta
	_track_player()
	if _attacked_at < 0.0 and Input.is_action_just_pressed("attack"):
		_attacked_at = _scene_time   # первый удар игрока — после него подсказка про рывок
	if _current != "":
		_shown_for += delta
		if _satisfied(_current) or _shown_for >= SHOW_TIME:
			_finish(true)
		elif not _can_show():
			_finish(false)   # прервали (диалог, смерть, выключили в настройках) — не засчитываем, покажем позже
		return
	_gap = maxf(_gap - delta, 0.0)
	_timer -= delta
	if _timer > 0.0 or _gap > 0.0:
		return
	_timer = CHECK_STEP
	if not _can_show():
		return
	for id in ORDER:
		if not PlayerState.is_taken("hint:" + id) and _trigger(id):
			_show(id)
			return


func _enabled() -> bool:
	return bool(Settings.get_value("tutorial_hints"))


func _can_show() -> bool:
	if not _enabled() or _player == null or not is_instance_valid(_player):
		return false
	if _player.get("input_locked") or (_player.has_method("is_alive") and not _player.call("is_alive")):
		return false
	return true


func _track_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		_last_pos = Vector3.INF
		return
	if _last_pos != Vector3.INF:
		var d := _player.global_position - _last_pos
		d.y = 0.0
		if d.length() < 3.0:   # рывок телепорта/возрождения в ходьбу не считается
			_walked += d.length()
	_last_pos = _player.global_position


func _near(group: StringName, radius: float, alive_only := false) -> bool:
	for n in get_tree().get_nodes_in_group(group):
		if not (n is Node3D) or not n.is_visible_in_tree():
			continue
		if alive_only and n.has_method("is_alive") and not n.call("is_alive"):
			continue
		var d: Vector3 = n.global_position - _player.global_position
		d.y = 0.0
		if d.length() < radius:
			return true
	return false


func _trigger(id: String) -> bool:
	var scene := get_tree().current_scene
	var path: String = scene.scene_file_path if scene else ""
	match id:
		"move":
			return _scene_time > 1.5 and PlayerState.deaths == 0
		"interact":
			return _near(&"npcs", 2.6)
		"run":
			return _walked > WALK_FOR_RUN and PlayerState.is_taken("hint:move")
		"run_empty":
			return bool(_player.get("winded"))
		"attack":
			return _near(&"enemies", 9.0, true)
		"dash":
			return _attacked_at >= 0.0 and _scene_time - _attacked_at > 1.2 and _near(&"enemies", 12.0, true)
		"book":
			return _new_item
		"map":
			return "rubezh" in path and _scene_time > 3.0
		"death":
			return PlayerState.deaths >= 1 and _scene_time > 2.5
		"lantern":
			return _near(&"soul_lanterns", 5.0)
	return false


## Игрок сделал то, о чём подсказка.
func _satisfied(id: String) -> bool:
	match id:
		"move":
			return Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.3 and _shown_for > 1.0
		"interact":
			return Input.is_action_just_pressed("interact")
		"run":
			return Input.is_action_pressed("run") or Input.is_action_just_pressed("dash")
		"run_empty":
			return not bool(_player.get("winded"))
		"attack":
			return Input.is_action_just_pressed("attack")
		"dash":
			return Input.is_action_just_pressed("dash")
		"book":
			return Input.is_action_just_pressed("inventory")
		"map":
			return Input.is_action_just_pressed("journal")
		"death":
			return _shown_for > 6.0
		"lantern":
			return Input.is_action_just_pressed("interact") and _shown_for > 1.0
	return false


func _show(id: String) -> void:
	_current = id
	_shown_for = 0.0
	_build(id)
	_plank.modulate.a = 0.0
	_plank.visible = true
	create_tween().tween_property(_plank, "modulate:a", 1.0, 0.35)


func _finish(counted: bool) -> void:
	var id := _current
	_current = ""
	_gap = GAP_TIME
	if id == "book":
		_new_item = false
	if counted:
		PlayerState.take("hint:" + id)
	var t := create_tween()
	t.tween_property(_plank, "modulate:a", 0.0, 0.4)
	t.tween_callback(func(): if _current == "": _plank.visible = false)


func _build(id: String) -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	var text: String = HINTS[id]["text"]
	var rest := text
	while true:
		var a := rest.find("{")
		if a < 0:
			_add_text(rest)
			break
		_add_text(rest.substr(0, a))
		var b := rest.find("}", a)
		_add_glyph(rest.substr(a + 1, b - a - 1))
		rest = rest.substr(b + 1)
	_row.reset_size()
	var pad := Vector2(12, 9)
	_plank.size = _row.size + pad * 2.0
	_row.position = pad
	_layout()


func _layout() -> void:
	if _plank == null:
		return
	_plank.position = Vector2(floorf((size.x - _plank.size.x) / 2.0), size.y - 80.0 - _plank.size.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _add_text(s: String) -> void:
	if s == "":
		return
	var l := Label.new()
	l.text = s
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", Color("e6d6b0"))
	l.add_theme_color_override("font_outline_color", Color("2a1e18"))
	l.add_theme_constant_override("outline_size", 2)
	_row.add_child(l)


func _add_glyph(action: String) -> void:
	if action == "move":
		if InputGlyphs.touch:
			_add_text("джойстик слева")
		elif InputGlyphs.gamepad:
			_add_text("левый стик")
		else:
			for a in [&"move_up", &"move_left", &"move_down", &"move_right"]:
				_row.add_child(KeyGlyph.new(a))
		return
	if InputGlyphs.label(StringName(action)) == "":
		_add_text("кнопка на экране")   # касание: подписей клавиш нет
		return
	_row.add_child(KeyGlyph.new(StringName(action)))
