class_name StoryPickup
extends Interactable
## Сюжетная находка Главы 1 (Литература/CHAPTER1.md): вещь (знамя, шкатулка графа, медальон Лиары)
## или душа павшего товарища. «Действием» — подобрать: вещь в инвентарь, душа — к Рэю (её сила в хотбар).
## Задание узнаёт об этом событием «item:<id>» / «soul». После подбора — исчезает (persist_id).
## Подсказка над находкой и реплики (кто говорит и что) — в LINES.

## Что это: "item" или "soul"; content_id — id предмета или души в res://data/.
@export var kind: String = "item"
@export var content_id: StringName

## Реплики при подборе: [говорящий, строки]. Пусто — без реплик.
const LINES := {
	&"banner_third_company": ["Рэй", ["Знамя третьей роты. Обгорел только край.", "Ильза узнает его по вышивке."]],
	&"velmor_casket": ["Рэй", ["Шкатулка с гербом графа. Запечатана.", "Знак на крышке — как на его перчатках."]],
	&"liara_medallion": ["Рэй", ["Серебряное сердце. Тёплое.", "…Не помню, откуда он у меня.", "Почему-то не могу положить его обратно."]],
	&"soul_finn": ["Финн «Тихоход»", ["Рэй? Опять к печати идёшь?", "…Иди. Я никому не скажу. Я ведь никогда не говорил."]],
	&"soul_jorg": ["Йорг", ["Дверь… держу… уходите…", "Передай Ильзе письмо. Я не дописал про ярмарку."]],
	&"soul_bruno": ["Сержант Бруно", ["Строй держи, новобранец.", "Ты ведь так и не сказал мне, куда ходишь по ночам."]],
	# Росток каменной ивы у святилища (мир; реплика — решение автора 2026-10-27).
	&"stone_willow_sprout": ["Рэй", ["Росток каменной ивы. Листья твёрдые, как сланец.", "Хорст такой ждал."]],
}

## Душа → вещь, которую она передаёт Рэю вместе с собой.
const GIFTS := {&"soul_jorg": &"jorg_letter"}

var _visual: Node3D
var _glow: OmniLight3D


func _ready() -> void:
	super()
	prompt_height = 1.6
	interact_range = 1.8
	if is_done():
		queue_free()
		return
	_build_visual()


func prompt_text() -> String:
	return with_key("принять душу") if kind == "soul" else with_key("взять")


func can_interact() -> bool:
	return true


func interact() -> void:
	mark_done()
	var title := ""
	if kind == "soul":
		var soul := PlayerState.collect_soul(content_id)
		# Вещь, что душа передаёт Рэю (квесты жителей: письмо Йорга — для Ильзы).
		if GIFTS.has(content_id):
			var gift := ContentDB.item(GIFTS[content_id])
			if gift:
				PlayerState.add_item(gift, 1)
				QuestState.notify("item:" + String(GIFTS[content_id]))
		title = soul.name if soul else String(content_id)
		QuestState.notify("soul")
		CombatFX.burst(global_position + Vector3(0, 1.0, 0), Color("8fd8d0"), Vector3.UP, 30, 3.0, 2.0, 0.08, 1.0)
		Audio.play("lantern", global_position)
	else:
		var item := ContentDB.item(content_id)
		if item:
			PlayerState.add_item(item, 1)
			title = item.name
		QuestState.notify("item:" + String(content_id))
		Audio.play("pickup", global_position)
	CombatFX.float_text(global_position + Vector3(0, 2.0, 0), title, Color("e8c870"))
	_say()
	queue_free()


## Реплики находки через окно реплик сцены (если оно есть); Рэй стоит, пока они идут.
func _say() -> void:
	if not LINES.has(content_id):
		return
	var scene := get_tree().current_scene
	var box := scene.get_node_or_null("DialogueBox") if scene else null
	if box == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.set("input_locked", true)
		box.finished.connect(func(): player.set("input_locked", false), CONNECT_ONE_SHOT)
	box.play(LINES[content_id][0], PackedStringArray(LINES[content_id][1]))


## Душа — бледный огонёк с ореолом; вещь — светящаяся «искра» над полом (пока нет моделей вещей).
func _build_visual() -> void:
	_visual = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	var soul := kind == "soul"
	mesh.radius = 0.22 if soul else 0.14
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var m := StandardMaterial3D.new()
	var col := Color("8fd8d0") if soul else Color("e8c870")
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	_visual.mesh = mesh
	_visual.position.y = 1.0 if soul else 0.5
	add_child(_visual)
	_glow = OmniLight3D.new()
	_glow.light_color = col
	_glow.light_energy = 1.4
	_glow.omni_range = 3.5
	_glow.position.y = _visual.position.y
	add_child(_glow)


func _process(delta: float) -> void:
	super(delta)
	if _visual:
		var t := Time.get_ticks_msec() / 1000.0
		_visual.position.y = (1.0 if kind == "soul" else 0.5) + sin(t * 2.0) * 0.08
		_glow.light_energy = 1.2 + sin(t * 3.1) * 0.3
