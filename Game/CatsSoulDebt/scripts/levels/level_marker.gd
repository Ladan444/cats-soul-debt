extends Node3D
## Метка серых блоков: где будет сундук, ключ, душа, находка, ловушка или переход на другой этаж.
## Светящийся столбик своего цвета и подпись — пока эти вещи не сделаны в игре.

const COLORS := {
	"chest": Color(0.95, 0.7, 0.1), "key": Color(1, 0.95, 0.2), "bigkey": Color(1, 0.35, 0.1),
	"soul": Color(0.3, 0.9, 0.95), "item": Color(0.2, 0.8, 0.5), "trap": Color(0.95, 0.15, 0.4),
	"exit": Color(0.95, 0.95, 0.95), "boss": Color(1, 0.4, 0.05),
	"npc": Color(0.98, 0.72, 0.3), "trade": Color(0.15, 0.85, 0.4), "sleep": Color(0.35, 0.55, 1.0),
	"animal": Color(0.92, 0.92, 0.65),
}
const NAMES := {
	"chest": "сундук", "key": "ключ", "bigkey": "особый ключ", "soul": "душа", "item": "находка",
	"trap": "ловушка", "exit": "переход", "boss": "страж",
	"npc": "житель", "trade": "торговля", "sleep": "сон", "animal": "живность",
}

@export var kind: String = "chest"
@export var label: String = ""


func _ready() -> void:
	# Метки-заглушки скрывает и показывает мастер-меню отладки (Cheats.show_markers); их видит миникарта.
	add_to_group("level_markers")
	visible = Cheats.show_markers
	var color: Color = COLORS.get(kind, Color.WHITE)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.7, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	box.material = mat
	mesh.mesh = box
	mesh.position.y = 0.35
	add_child(mesh)
	var text := Label3D.new()
	text.text = NAMES.get(kind, kind) + ("\n" + label if label != "" else "")
	text.font = load("res://assets/fonts/public_pixel/PublicPixel.ttf")
	text.font_size = 16
	text.pixel_size = 0.01
	text.modulate = color
	text.outline_size = 4
	text.outline_modulate = Color("1e1614")
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	text.position.y = 1.3
	add_child(text)
