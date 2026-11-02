class_name SoulLantern
extends Node3D
## Фонарь душ (COMBAT_SPEC, раздел 5): «Действием» рядом — зажечь. Последний зажжённый —
## точка возрождения Рэя. Пока не зажжён — тусклый, над ним подсказка с клавишей.

signal lit_up(lantern: SoulLantern)

const RANGE := 1.8
const COLOR_LIT := Color(0.75, 0.6, 1.0)

@export var lit: bool = false
## Свой столб и стекло (Рубеж). В мире вокруг Брода фонарь — модель из Blender (посох-крюк), узел стоит
## у подвесного фонаря и даёт только свет, подсказку и точку возрождения.
@export var builtin_model: bool = true
## Где свет и стекло относительно узла; где встаёт Рэй при возрождении.
@export var glow_offset := Vector3(0, 1.45, 0)
@export var respawn_offset := Vector3(0, 0, 0.9)

var _glass: MeshInstance3D
var _light: OmniLight3D
var _prompt: Label3D
var _player: Node3D
var _near: bool = false


func _ready() -> void:
	add_to_group("soul_lanterns")
	_light = OmniLight3D.new()
	_light.light_color = COLOR_LIT
	_light.omni_range = 6.0
	_light.position = glow_offset
	_light.shadow_enabled = false
	add_child(_light)
	if builtin_model:
		_build_model()
	_setup_prompt()
	# Зажжённые фонари помнит PlayerState (и сохранение).
	if PlayerState.lit_lanterns.has(key()):
		lit = true
	_apply()


## Столб и стекло фонаря (Рубеж).
func _build_model() -> void:
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color("3a2e2a")
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 1.2, 0.12)
	post_mesh.material = post_mat
	post.mesh = post_mesh
	post.position.y = 0.6
	add_child(post)
	_glass = MeshInstance3D.new()
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(0.28, 0.32, 0.28)
	_glass.mesh = glass_mesh
	_glass.position.y = 1.32
	add_child(_glass)
	# Препятствие, чтобы не проходить сквозь столб.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 1.4, 0.3)
	shape.shape = box
	shape.position.y = 0.7
	body.add_child(shape)
	add_child(body)


func _setup_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.font = CombatFX.FONT
	_prompt.font_size = 16
	_prompt.pixel_size = 0.011
	_prompt.outline_size = 4
	_prompt.outline_modulate = Color("1e1614")
	_prompt.modulate = Color("e6d6b0")
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_prompt.position.y = glow_offset.y + 0.5
	_prompt.visible = false
	add_child(_prompt)


## Ключ фонаря в сохранении: сцена и имя узла.
func key() -> String:
	# owner — корень сцены локации (current_scene во время _ready может быть ещё не назначен).
	var scene: Node = owner if owner else (get_tree().current_scene if is_inside_tree() else null)
	return "%s:%s" % [scene.scene_file_path if scene else "", name]


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	var d := _player.global_position - global_position
	d.y = 0
	_near = d.length() < RANGE and _player.is_alive()
	_prompt.visible = _near and not lit
	if _prompt.visible:
		var key_label := InputGlyphs.label(&"interact")
		# При касании клавиш нет — на экране кнопка «Действие» с рукой.
		_prompt.text = "%s — зажечь фонарь" % key_label if key_label != "" else "Зажечь фонарь"


func _unhandled_input(event: InputEvent) -> void:
	# Во время реплик и переходов «Действие» листает реплики, а не зажигает фонарь рядом (как у Interactable).
	if _near and not lit and event.is_action_pressed("interact") and not _player.get("input_locked"):
		light_up()
		get_viewport().set_input_as_handled()


func light_up() -> void:
	lit = true
	PlayerState.light_lantern(key())
	_apply()
	Audio.play("lantern", global_position)
	# Вспышка при зажжении.
	_light.light_energy = 5.0
	create_tween().tween_property(_light, "light_energy", 1.6, 0.8)
	lit_up.emit(self)


## Где возрождается Рэй: чуть перед фонарём (к камере).
func respawn_point() -> Vector3:
	return global_position + respawn_offset


func _apply() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_LIT if lit else Color(0.25, 0.22, 0.3)
	mat.emission_enabled = lit
	mat.emission = COLOR_LIT
	mat.emission_energy_multiplier = 3.0
	if _glass:
		_glass.mesh.material = mat
	_light.light_energy = 1.6 if lit else 0.0
	_light.visible = lit
