class_name Interactable
extends Node3D
## Основа предметов мира, с которыми действуют «Действием» (E / A / лапа на экране): двери, сундуки.
## Рядом с Рэем над предметом — подсказка с клавишей. persist_id — ключ в PlayerState.taken:
## сделанное (открытая дверь, пустой сундук) остаётся таким и после смерти и загрузки.

const FONT := preload("res://assets/fonts/public_pixel/PublicPixel.ttf")

@export var interact_range: float = 2.0
@export var persist_id: String = ""
@export var prompt_height: float = 2.0

var prompt: Label3D
var _player: Node3D
var _near: bool = false


func _ready() -> void:
	prompt = Label3D.new()
	prompt.font = FONT
	prompt.font_size = 16
	prompt.pixel_size = 0.011
	prompt.outline_size = 4
	prompt.outline_modulate = Color("1e1614")
	prompt.modulate = Color("e6d6b0")
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt.no_depth_test = true
	prompt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	prompt.position.y = prompt_height
	prompt.visible = false
	add_child(prompt)


func is_done() -> bool:
	return persist_id != "" and PlayerState.is_taken(persist_id)


func mark_done() -> void:
	if persist_id != "":
		PlayerState.take(persist_id)


## Текст подсказки; пусто — подсказки нет.
func prompt_text() -> String:
	return ""


## Можно ли сейчас действовать (иначе подсказка — только надпись, «Действие» не срабатывает).
func can_interact() -> bool:
	return false


func interact() -> void:
	pass


## «E — открыть» с клавишей текущего устройства (при касании — без клавиши).
func with_key(action_text: String) -> String:
	var k := InputGlyphs.label(&"interact")
	return ("%s — %s" % [k, action_text]) if k != "" else action_text.left(1).to_upper() + action_text.substr(1)


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	var d := _player.global_position - global_position
	d.y = 0
	_near = d.length() < interact_range and _player.is_alive()
	var text := prompt_text() if _near else ""
	prompt.visible = text != ""
	if prompt.visible:
		prompt.text = text


func _unhandled_input(event: InputEvent) -> void:
	# Пока Рэй занят (реплики, переход между локациями) — не действовать: на геймпаде «Действие» и «Далее» —
	# одна кнопка A, и нажатие могло и пролистать реплику, и открыть дверь рядом.
	if _player and _player.get("input_locked"):
		return
	if _near and event.is_action_pressed("interact") and can_interact():
		interact()
		get_viewport().set_input_as_handled()
