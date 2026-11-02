extends Node
## Отмечает в журнале исследованные комнаты: в какой комнате карты стоит игрок (UI_SPEC, раздел 4).
## Ставится в сцену локации; карта — ресурс JournalMap.

@export var map: JournalMap
@export var player_path: NodePath

var _player: Node3D
var _last_room: String = ""


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D


func _physics_process(_delta: float) -> void:
	if map == null or _player == null:
		return
	var room := map.room_at(Vector2(_player.global_position.x, _player.global_position.z))
	if room.is_empty() or room["id"] == _last_room:
		return
	_last_room = room["id"]
	JournalState.explore(map.id, room["id"])
