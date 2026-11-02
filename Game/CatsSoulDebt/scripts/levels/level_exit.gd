class_name LevelExit
extends Area3D
## Переход между локациями: Рэй входит в зону — экран гаснет, грузится другая сцена,
## Рэй встаёт в точке target_position (через SaveGame.pending_position, как при загрузке сохранения).
## Деревня ⇄ Рубеж: лестница с обрыва Брода ⇄ ворота Рубежа.

@export_file("*.tscn") var target_scene: String
@export var target_position: Vector3
@export var size: Vector3 = Vector3(5, 3, 3)
## Надпись над переходом («↓ к Рубежу»).
@export var label: String = ""

var _busy: bool = false


func _ready() -> void:
	add_to_group("level_exits")   # для миникарты
	if label != "":
		var l := Label3D.new()
		l.text = label
		l.font = CombatFX.FONT
		l.font_size = 16
		l.pixel_size = 0.012
		l.outline_size = 4
		l.outline_modulate = Color("1e1614")
		l.modulate = Color("e6d6b0")
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		l.position.y = size.y + 0.5
		add_child(l)
	collision_layer = 0
	collision_mask = CombatFX.LAYER_PLAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _busy or not body.is_in_group("player"):
		return
	_busy = true
	body.set("input_locked", true)
	var layer := CanvasLayer.new()
	layer.layer = 30
	# Пока идёт переход, пауза/книга/карта не открываются: их слои ниже затемнения (меню не видно, игра
	# «висит» на чёрном), а «В главное меню» из паузы перебивал бы смену сцены.
	layer.add_to_group("scene_transition")
	var black := ColorRect.new()
	black.color = Color(0.02, 0.02, 0.03, 0.0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	get_tree().root.add_child(layer)
	var t := layer.create_tween()
	t.tween_property(black, "color:a", 1.0, 0.6)
	t.tween_callback(func():
		SaveGame.pending_position = target_position
		get_tree().change_scene_to_file(target_scene))
	t.tween_property(black, "color:a", 0.0, 0.6)
	t.tween_callback(layer.queue_free)
