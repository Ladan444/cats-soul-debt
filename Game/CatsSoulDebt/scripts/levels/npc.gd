class_name Npc
extends Interactable
## Житель, с которым говорят «Действием»: спрайт-лист (как у Рэя, кадры idle), поворачивается к Рэю,
## реплики — через окно реплик сцены (DialogueBox). Что сказать — решает talk(): по умолчанию строки lines;
## у сюжетных жителей talk() переопределён (граф — velmor_npc.gd). npc_id — для событий заданий «talk:<id>».

@export var npc_id: String = ""
@export var display_name: String = ""
@export var sheet: Texture2D
@export var hframes: int = 4
@export var vframes: int = 21
@export var lines: PackedStringArray = []

var sprite: DirectionalSprite
var _talking: bool = false


func _ready() -> void:
	super()
	prompt_height = 2.4
	interact_range = 2.2
	add_to_group("npcs")
	sprite = DirectionalSprite.new()
	sprite.texture = sheet
	# DirectionalSprite сам считает строки листа: анимаций × 3 вида. Житель играет только idle, но в списке
	# должны быть все строки листа (у листа боя их 21 = 7 анимаций), иначе ячейка растянется на соседние кадры.
	sprite.columns = hframes
	var anims: Array[Dictionary] = [{"name": "idle", "frames": 4, "fps": 4.0, "loop": true}]
	for i in range(1, vframes / sprite.directions):
		anims.append({"name": "_row%d" % i, "frames": 1, "fps": 1.0, "loop": false})
	sprite.animations = anims
	sprite.pixel_size = 0.025
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.position.y = 0.9
	add_child(sprite)
	CombatFX.setup_sprite(sprite)
	sprite.play("idle")
	# Препятствие: сквозь жителя не пройти.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	shape.shape = cap
	shape.position.y = 0.7
	body.add_child(shape)
	add_child(body)


func prompt_text() -> String:
	return "" if _talking else with_key("говорить")


func can_interact() -> bool:
	return not _talking


func _process(delta: float) -> void:
	super(delta)
	if _player and _near:
		var to := _player.global_position - global_position
		to.y = 0
		if to.length_squared() > 0.01:
			sprite.face(to.normalized())


func interact() -> void:
	talk()


## Разговор. Переопределяется; по умолчанию — строки lines.
func talk() -> void:
	say(lines)


## Показать реплики; on_done — что сделать после них.
func say(text: PackedStringArray, on_done: Callable = Callable()) -> void:
	var box := dialogue_box()
	if box == null or text.is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	_lock(true)
	box.finished.connect(func():
		_lock(false)
		if on_done.is_valid():
			on_done.call(), CONNECT_ONE_SHOT)
	box.play(display_name, text)


## Вопрос с вариантами; on_choice(номер).
func ask(question: String, options: PackedStringArray, on_choice: Callable) -> void:
	var box := dialogue_box()
	if box == null:
		on_choice.call(0)
		return
	_lock(true)
	box.chosen.connect(func(i):
		_lock(false)
		on_choice.call(i), CONNECT_ONE_SHOT)
	box.ask(display_name, question, options)


func dialogue_box() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("DialogueBox") if scene else null


func _lock(on: bool) -> void:
	_talking = on
	var p := get_tree().get_first_node_in_group("player")
	if p:
		p.set("input_locked", on)
