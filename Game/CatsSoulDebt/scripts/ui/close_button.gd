class_name CloseButton
extends TextureButton
## Красный крестик закрытия 14×14 в углу окна — для мыши и касания (клавиатура и геймпад закрывают через Esc / B).
## Область нажатия шире картинки на 3 пикселя с каждой стороны, чтобы попадать пальцем.

const TEX := preload("res://assets/ui/close.png")
const TEX_HOVER := preload("res://assets/ui/close_hover.png")
const PAD := 3


func _ready() -> void:
	texture_normal = TEX
	texture_hover = TEX_HOVER
	texture_pressed = TEX_HOVER
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Закрыть"
	custom_minimum_size = TEX.get_size()
	size = TEX.get_size()


func _has_point(point: Vector2) -> bool:
	return Rect2(-Vector2(PAD, PAD), size + Vector2(PAD, PAD) * 2).has_point(point)
