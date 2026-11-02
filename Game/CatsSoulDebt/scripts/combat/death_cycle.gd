extends CanvasLayer
## Цикл смерти, простая версия (COMBAT_SPEC, раздел 5): при смерти Рэя — затемнение,
## утерянные гелиосы ложатся на месте смерти, Рэй возрождается у последнего зажжённого
## фонаря душ — и в другой локации тоже: тогда переход туда (решение автора 2026-10-29); без зажжённых
## фонарей — в начале локации. Враги появляются снова. После девятой смерти — Перепутье.
## Фонари и кучки гелиосов хранит PlayerState — при загрузке сохранения они восстанавливаются.

@export var player_path: NodePath

const CROSSROADS_SCENE := "res://scenes/levels/crossroads.tscn"
const FADE_OUT := 0.7
const HOLD := 0.4
const FADE_IN := 0.6

var _player: Node3D
var _start_point: Vector3
var _checkpoint: SoulLantern
var _black: ColorRect
var _busy: bool = false
## Рэй погиб в другой локации, чем его фонарь: сцену фонаря загрузили — поставить Рэя к фонарю.
## Статическая — переживает смену сцены.
static var respawn_pending: bool = false


func _ready() -> void:
	layer = 12
	_black = ColorRect.new()
	_black.color = Color(0.02, 0.01, 0.03, 0.0)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_player = get_node_or_null(player_path) as Node3D
	if _player:
		_start_point = _player.global_position
	PlayerState.died.connect(_on_died)
	for lantern in get_tree().get_nodes_in_group("soul_lanterns"):
		lantern.lit_up.connect(func(l): _checkpoint = l)
		if lantern.key() == PlayerState.checkpoint:
			_checkpoint = lantern
	_restore_piles.call_deferred()
	if respawn_pending:
		respawn_pending = false
		_arrive_at_checkpoint.call_deferred()


## После перехода к фонарю другой локации: встать у фонаря, камера — сразу за Рэем, проявление из черноты.
func _arrive_at_checkpoint() -> void:
	if _checkpoint and _player:
		_player.global_position = _checkpoint.respawn_point()
		_player.velocity = Vector3.ZERO
		var cam := get_viewport().get_camera_3d()
		if cam and cam.has_method("snap_to_target"):
			cam.snap_to_target()
		if _player.has_method("set_dead"):
			_player.set_dead(false)  # пара секунд передышки, как при обычном возрождении
	_black.color.a = 1.0
	create_tween().tween_property(_black, "color:a", 0.0, FADE_IN)


## Сцена фонаря-чекпойнта (ключ фонаря — «путь сцены:имя узла»), если он в другой локации; иначе "".
func _checkpoint_elsewhere() -> String:
	var key := PlayerState.checkpoint
	if _checkpoint != null or key == "" or key.rfind(":") <= 0:
		return ""
	var scene := key.substr(0, key.rfind(":"))
	var here := owner.scene_file_path if owner else ""
	return scene if scene != here and ResourceLoader.exists(scene) else ""


## Куда вернётся Рэй.
func respawn_point() -> Vector3:
	return _checkpoint.respawn_point() if _checkpoint else _start_point


## Кучки утерянных гелиосов из прошлых смертей этого спуска (после загрузки сохранения).
func _restore_piles() -> void:
	var scene_path := owner.scene_file_path if owner else ""
	for i in PlayerState.death_marks.size():
		var mark: Dictionary = PlayerState.death_marks[i]
		if mark["helios"] > 0 and mark.get("scene", "") == scene_path:
			_spawn_pile(i)


func _spawn_pile(index: int) -> void:
	var mark: Dictionary = PlayerState.death_marks[index]
	var pile := HeliosPickup.spawn(_player.get_parent(), mark["pos"], mark["helios"], true)
	pile.mark_index = index


func _on_died(_death_number: int, _lost: int) -> void:
	if _busy or _player == null:
		return
	_busy = true
	_player.set_dead(true)
	# Девятая смерть за спуск — Перепутье (CANON): долгое затемнение и другая сцена.
	if PlayerState.deaths >= PlayerState.MAX_DEATHS:
		var to_crossroads := create_tween()
		to_crossroads.tween_property(_black, "color:a", 1.0, FADE_OUT * 2.0)
		to_crossroads.tween_interval(HOLD)
		to_crossroads.tween_callback(func(): get_tree().change_scene_to_file(CROSSROADS_SCENE))
		return
	# Утерянная добыча — на месте смерти (последняя отметка в PlayerState).
	if not PlayerState.death_marks.is_empty() and PlayerState.death_marks.back()["helios"] > 0:
		_spawn_pile(PlayerState.death_marks.size() - 1)
	var t := create_tween()
	t.tween_property(_black, "color:a", 1.0, FADE_OUT)
	t.tween_interval(HOLD)
	t.tween_callback(_respawn)
	t.tween_property(_black, "color:a", 0.0, FADE_IN)
	t.tween_callback(func(): _busy = false)


func _respawn() -> void:
	var elsewhere := _checkpoint_elsewhere()
	if elsewhere != "":
		respawn_pending = true
		SaveGame.pending_position = null
		get_tree().change_scene_to_file(elsewhere)
		return
	_player.global_position = respawn_point()
	_player.velocity = Vector3.ZERO
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.respawn()
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method("snap_to_target"):
		cam.snap_to_target()
	_player.set_dead(false)
