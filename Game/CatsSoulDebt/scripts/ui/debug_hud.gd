extends Label
## Подсказка управления и отладки (флажок «Подсказка управления» в мастер-меню, Cheats.show_hint).

@export var player_path: NodePath
@export var atmosphere_path: NodePath

@onready var _player: Node = get_node_or_null(player_path)
@onready var _atmosphere: AtmosphereBlender = get_node_or_null(atmosphere_path)


func _process(_delta: float) -> void:
	visible = Cheats.show_hint
	if not visible:
		return
	var skin := ""
	if _player and _player.current_skin < _player.debug_skin_names.size():
		skin = _player.debug_skin_names[_player.current_skin]
	var zone := _atmosphere.current_zone_name() if _atmosphere else ""
	text = ("Облик: %s  Зона: %s  Смерти: %d/9\n" % [skin, zone, PlayerState.deaths]
		+ "O — мастер-меню отладки\n"
		+ "ЛКМ/J удар  Q R F скиллы  1 настойка  Shift бег  Пробел рывок  E действие")
