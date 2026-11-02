extends Node3D
## Таверна «Красная черепица» внутри (геометрия — Tools/blender/build_tavern.py → assets/levels/tavern.glb).
## Стены — модули Quaternius (KitDress.quaternius, окно вокруг Рэя), мебель — KayKit (KitDress.kaykit).
## Знамя третьей роты над камином видно, когда Рэй его принёс (долг «Знамя третьей роты» в PlayerState.taken).

@export var player_path: NodePath
@export var geometry_path: NodePath

var _player: Node3D
var _banner: Node3D


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	for child in get_node(geometry_path).get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_node := child as MeshInstance3D
		match String(mesh_node.name):
			"Walls":
				KitDress.quaternius(mesh_node)
			"Props", "Banner":
				KitDress.kaykit(mesh_node)
	_banner = get_node(geometry_path).get_node_or_null("Banner") as Node3D


func _process(_delta: float) -> void:
	if _player:
		RenderingServer.global_shader_parameter_set("player_world_position", _player.global_position + Vector3(0, 0.8, 0))
	if _banner:
		_banner.visible = PlayerState.is_taken("debt:Знамя третьей роты")
