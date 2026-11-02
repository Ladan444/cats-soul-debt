extends Node3D
## Перепутье (CANON, «Механика смерти»; решение автора): после девятой смерти Рэй выходит из тумана
## к столбу с табличками. Подойдя к Стражу Перекрёстка, слышит беседу главы (data/crossroads),
## затем экран гаснет и Рэй просыпается в таверне — начинается новый спуск, отметки обнулены.

const TAVERN_SCENE := "res://scenes/levels/tavern.tscn"
const LINES_PATH := "res://data/crossroads/chapter_%d.tres"
const SPEAKER := "Страж Перекрёстка"
const TALK_RANGE := 2.6
const FADE := 1.2

@export var player_path: NodePath
@export var guardian_path: NodePath
@export var dialogue_path: NodePath

var _player: CharacterBody3D
var _guardian: Node3D
var _dialogue: DialogueBox
var _black: ColorRect
var _talked: bool = false
var _time: float = 0.0


func _ready() -> void:
	_player = get_node(player_path)
	_guardian = get_node(guardian_path)
	_dialogue = get_node(dialogue_path)
	_dialogue.finished.connect(_wake_up)
	var guardian_sprite: Sprite3D = _guardian.get_node("Sprite3D")
	CombatFX.setup_sprite(guardian_sprite)
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	_black = ColorRect.new()
	_black.color = Color(0.02, 0.02, 0.02, 1.0)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_black)
	# Рэй «приходит в себя» на дороге: из темноты, пару мгновений без управления.
	_player.input_locked = true
	var t := create_tween()
	t.tween_property(_black, "color:a", 0.0, FADE)
	t.tween_callback(func(): _player.input_locked = false)


func _physics_process(delta: float) -> void:
	_time += delta
	# Страж чуть покачивается, опираясь на посох.
	_guardian.get_node("Sprite3D").position.y = 0.7 + sin(_time * 1.3) * 0.02
	if _talked or _player.input_locked:
		return
	var d := _guardian.global_position - _player.global_position
	d.y = 0
	if d.length() < TALK_RANGE:
		_talked = true
		_player.input_locked = true
		_player.set("_facing", d.normalized())
		_dialogue.play(SPEAKER, _lines())


## Беседа текущей главы для этого визита (по кругу).
func _lines() -> PackedStringArray:
	var path := LINES_PATH % PlayerState.chapter
	if not ResourceLoader.exists(path):
		path = LINES_PATH % 1
	var data: GuardianLines = load(path)
	return data.conversation(PlayerState.crossroads_visits)


func _wake_up() -> void:
	var t := create_tween()
	t.tween_property(_black, "color:a", 1.0, FADE)
	t.tween_callback(func():
		PlayerState.wake_after_crossroads()
		SaveGame.pending_position = null
		get_tree().change_scene_to_file(TAVERN_SCENE))
