extends Node3D
## Уровень Рубежа из серых блоков (геометрия — glb из Blender, Tools/blender/build_greybox.py).
## При запуске: текстуры (стены — wall_xray с «окном» вокруг Рэя и мхом, полы, скалы пропасти)
## и двери: у каждого меша Door-* появляется LevelDoor (ключи, засовы, ложные стены, надписи).

const WALL_SHADER := preload("res://assets/shaders/wall_xray.gdshader")
const FLOOR_SHADER := preload("res://assets/shaders/greybox_floor.gdshader")
## Пиксельные текстуры Рубежа (Tools/texture_pipeline.py, 40 пикселей на метр).
const TEX := "res://assets/textures/rubezh/%s.png"
## Вид двери по типу: на ключ и сюжетные — сквозная опускная решётка (Tools/portcullis_texture.py),
## засов — дощатая дверь. Печати душ пока остаются серыми блоками своего цвета.
const DOOR_LOOKS := {"key": "rubezh_portcullis", "bigkey": "rubezh_portcullis", "story": "rubezh_portcullis",
	"oneway": "rubezh_wood_planks"}

@export var player_path: NodePath
@export var geometry_path: NodePath

var _player: Node3D


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	var geometry := get_node(geometry_path)
	var wall_material: ShaderMaterial
	var rooms := {}
	for child in geometry.get_children():
		if String(child.name).begins_with("room-"):
			rooms[String(child.name).trim_prefix("room-")] = (child as Node3D).global_position
	for child in geometry.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_node := child as MeshInstance3D
		var n := String(mesh_node.name)
		if n == "Walls":
			var wall := ShaderMaterial.new()
			wall.shader = WALL_SHADER
			wall.set_shader_parameter("use_texture", true)
			wall.set_shader_parameter("albedo_texture", load(TEX % "rubezh_wall_brick"))
			wall.set_shader_parameter("use_moss", true)
			wall.set_shader_parameter("moss_texture", load(TEX % "rubezh_wall_mossy"))
			mesh_node.material_override = wall
			wall_material = wall
		elif n == "Floor" or n == "CorridorFloor":
			var floor_mat := ShaderMaterial.new()
			floor_mat.shader = FLOOR_SHADER
			floor_mat.set_shader_parameter("use_texture", true)
			floor_mat.set_shader_parameter("albedo_texture",
				load(TEX % ("rubezh_floor_flagstone" if n == "Floor" else "rubezh_floor_cobble")))
			mesh_node.material_override = floor_mat
		elif n.begins_with("Chasm"):
			var rock := StandardMaterial3D.new()
			rock.albedo_texture = load(TEX % "rubezh_rock_cliff")
			rock.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			rock.uv1_triplanar = true
			rock.uv1_world_triplanar = true
			rock.uv1_scale = Vector3.ONE / 3.2
			rock.roughness = 0.95
			mesh_node.material_override = rock
	var props := get_node_or_null("Props")
	if props:
		for child in props.get_children():
			if child is MeshInstance3D and String(child.name) == "Arches":
				KitDress.kaykit_xray(child)
			elif child is MeshInstance3D and not String(child.name).ends_with("-colonly"):
				KitDress.kaykit(child)
	# Двери — после стен: ложной стене нужен материал стены, чтобы не выдавать тайник цветом.
	for child in geometry.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Door-"):
			var extras: Dictionary = child.get_meta("extras", {})
			var kind: String = extras.get("kind", "")
			if kind == "secret" and wall_material:
				child.material_override = wall_material
			elif DOOR_LOOKS.has(kind):
				child.material_override = _door_material(DOOR_LOOKS[kind])
			var door := LevelDoor.new()
			door.name = "Ctl" + String(child.name)
			door.setup(child, extras, rooms.get(extras.get("from", ""), Vector3.ZERO), scene_file_path)
			add_child(door)


## Материал двери по миру (трипланар, 3,2 м на плитку — 40 px/м); решётка — с альфа-вырезом и видна с обеих сторон.
func _door_material(texture_name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX % texture_name)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 3.2
	m.roughness = 0.8
	if texture_name == "rubezh_portcullis":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.metallic = 0.4
	return m


func _process(_delta: float) -> void:
	if _player:
		RenderingServer.global_shader_parameter_set("player_world_position", _player.global_position + Vector3(0, 0.8, 0))

