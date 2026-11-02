extends Interactable
## Находка побочного квеста (village_quests.gd → props): появляется, только пока квест взят и не сдан.
## «Действием» — подобрать: предмет (и сопутствующие) в инвентарь, гелиосы, флаг выбора; событие «item:<id>»;
## реплики Рэя. После подбора исчезает навсегда (persist_id).

@export var quest_id: String = ""
@export var item_id: String = ""
@export var also: PackedStringArray = []
@export var helios: int = 0
@export var flag: String = ""
@export var label_text: String = ""
@export var verb: String = "взять"
@export var lines: PackedStringArray = []

var _visual: MeshInstance3D
var _glow: OmniLight3D


func _ready() -> void:
	prompt_height = 1.4
	interact_range = 1.8
	super()
	add_to_group("quest_props")   # для навигатора (Waypoints): цель шага «item:<id>»
	if is_done():
		queue_free()
		return
	_visual = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.14
	mesh.height = 0.28
	mesh.radial_segments = 8
	mesh.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("e8c870")
	m.emission_enabled = true
	m.emission = Color("e8c870")
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	_visual.mesh = mesh
	_visual.position.y = 0.5
	add_child(_visual)
	_glow = OmniLight3D.new()
	_glow.light_color = Color("e8c870")
	_glow.light_energy = 1.2
	_glow.omni_range = 3.0
	_glow.position.y = 0.5
	add_child(_glow)


func _active() -> bool:
	return QuestState.active.has(quest_id) and not QuestState.is_done(quest_id)


func prompt_text() -> String:
	return "%s\n%s" % [label_text, with_key(verb)] if _active() else ""


func can_interact() -> bool:
	return _active()


func _process(delta: float) -> void:
	super(delta)
	var on := _active()
	_visual.visible = on
	_glow.visible = on
	if on:
		var t := Time.get_ticks_msec() / 1000.0
		_visual.position.y = 0.5 + sin(t * 2.0) * 0.08


func interact() -> void:
	mark_done()
	var title := label_text
	for id in ([item_id] if item_id != "" else []) + Array(also):
		var item := ContentDB.item(StringName(id))
		if item:
			PlayerState.add_item(item, 1)
			title = item.name if id == item_id else title
	if helios > 0:
		PlayerState.add_helios(helios, false)
		title = "+%d гелиосов" % helios
	if flag != "":
		PlayerState.take(flag)
	if item_id != "":
		QuestState.notify("item:" + item_id)
	Audio.play("pickup", global_position)
	CombatFX.float_text(global_position + Vector3(0, 1.8, 0), title, Color("e8c870"))
	var box := get_tree().current_scene.get_node_or_null("DialogueBox")
	var player := get_tree().get_first_node_in_group("player")
	if box and not lines.is_empty():
		if player:
			player.set("input_locked", true)
			box.finished.connect(func(): player.set("input_locked", false), CONNECT_ONE_SHOT)
		box.play("Рэй", lines)
	queue_free()
