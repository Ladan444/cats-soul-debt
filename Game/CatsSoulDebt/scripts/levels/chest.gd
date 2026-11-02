extends Interactable
## Сундук: «Действием» открывается крышка, выпадает награда. Что внутри — по подписи из планировки
## (Tools/blender/rubezh_layout.py): «гелиосы», «настойки»; «реликвия» и «душа» — пока гелиосы
## и надпись, что здесь будет (системы реликвий и новых душ — позже). Пустой остаётся пустым навсегда.

const WOOD := preload("res://assets/textures/rubezh/rubezh_wood_planks.png")
const IRON := preload("res://assets/textures/rubezh/rubezh_iron_grate.png")

@export var contents: String = "гелиосы"

var _lid: Node3D
var _opened: bool = false


func _ready() -> void:
	super()
	interact_range = 1.8
	prompt.position.y = 1.4
	var wood := _material(WOOD)
	var iron := _material(IRON)
	_box(Vector3(0.9, 0.5, 0.6), Vector3(0, 0.25, 0), wood, self)
	_box(Vector3(0.94, 0.08, 0.64), Vector3(0, 0.08, 0), iron, self)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.5, -0.3)  # петли сзади
	add_child(_lid)
	_box(Vector3(0.92, 0.18, 0.62), Vector3(0, 0.09, 0.3), wood, _lid)
	_box(Vector3(0.96, 0.05, 0.66), Vector3(0, 0.2, 0.3), iron, _lid)
	# Препятствие — сундук не проходится насквозь.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.7, 0.6)
	shape.shape = box
	shape.position.y = 0.35
	body.add_child(shape)
	add_child(body)
	if is_done():
		_opened = true
		_lid.rotation.x = deg_to_rad(-100)


func prompt_text() -> String:
	return "" if _opened else with_key("открыть сундук")


func can_interact() -> bool:
	return not _opened


func interact() -> void:
	_opened = true
	mark_done()
	Audio.play("chest", global_position)
	var t := create_tween()
	t.tween_property(_lid, "rotation:x", deg_to_rad(-100), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	CombatFX.burst(global_position + Vector3(0, 0.6, 0), Color("e8c870"), Vector3.ZERO, 14, 2.5, 6.0, 0.06, 0.6)
	var top := global_position + Vector3(0, 1.3, 0)
	match contents:
		"настойки":
			var tincture := ContentDB.item(&"tincture_liara")
			PlayerState.add_item(tincture, 2)
			CombatFX.float_text(top, "+2 " + tincture.name.to_lower())
		"гелиосы", "":
			_drop_helios(randi_range(20, 35))
		_:
			_drop_helios(15)
			CombatFX.float_text(top, "(здесь будет: %s)" % contents, Color(0.7, 0.7, 0.7))


## Гелиосы сразу в кошелёк: раньше падали монетами, которые не сохраняются — уйдя, не подобрав, Рэй терял добычу,
## а сундук оставался открытым навсегда.
func _drop_helios(total: int) -> void:
	PlayerState.add_helios(total)
	Audio.play("coins", global_position)
	CombatFX.burst(global_position + Vector3(0, 0.9, 0), Color("f2c14e"), Vector3.UP, 10, 3.0, 9.0, 0.06, 0.6)
	CombatFX.float_text(global_position + Vector3(0, 1.6, 0), "+%d гелиосов" % total, Color("e8c870"))


func _material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 3.2
	m.roughness = 0.9
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
