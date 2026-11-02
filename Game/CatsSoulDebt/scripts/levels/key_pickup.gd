extends Area3D
## Ключ на полу: светится и покачивается, подбирается касанием. Подпись из планировки задаёт предмет:
## «К1»/«К2»/«К3» — малые ключи, «часть ключа N/3» — часть ключа сокровищницы;
## три части сами собираются в ключ сокровищницы. Подобранный ключ больше не появляется.

const ICON := preload("res://assets/ui/icon_key.png")
const SMALL_KEYS := {"К1": &"key_rubezh_k1", "К2": &"key_rubezh_k2", "К3": &"key_rubezh_k3"}

@export var key_label: String = "К1"
@export var persist_id: String = ""

var _sprite: Sprite3D
var _time: float = 0.0


func _ready() -> void:
	if persist_id != "" and PlayerState.is_taken(persist_id):
		queue_free()
		return
	collision_layer = 0
	collision_mask = CombatFX.LAYER_PLAYER
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	shape.position.y = 0.5
	add_child(shape)
	_sprite = Sprite3D.new()
	_sprite.texture = ICON
	_sprite.pixel_size = 0.04
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = false
	add_child(_sprite)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.4)
	light.light_energy = 0.9
	light.omni_range = 2.5
	light.position.y = 0.7
	add_child(light)
	body_entered.connect(_on_body_entered)


func item_id() -> StringName:
	return SMALL_KEYS.get(key_label, &"key_treasury_part")


func _process(delta: float) -> void:
	_time += delta
	if _sprite:
		_sprite.position.y = 0.6 + sin(_time * 3.0) * 0.08


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var item := ContentDB.item(item_id())
	PlayerState.add_item(item, 1)
	if persist_id != "":
		PlayerState.take(persist_id)
	var top := global_position + Vector3(0, 1.6, 0)
	if item.id == &"key_treasury_part":
		var parts := PlayerState.count_of(item)
		if parts >= 3:
			PlayerState.remove_item(item, parts)
			var full := ContentDB.item(&"key_treasury")
			PlayerState.add_item(full, 1)
			CombatFX.float_text(top, "Собран: " + full.name.to_lower())
		else:
			CombatFX.float_text(top, "%s (%d/3)" % [item.name, parts])
	else:
		CombatFX.float_text(top, item.name)
	CombatFX.burst(global_position + Vector3(0, 0.6, 0), Color("e8c870"), Vector3.ZERO, 12, 2.0, 3.0, 0.06, 0.5)
	queue_free()
