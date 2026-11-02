class_name KeyGlyph
extends Control
## Картинка клавиши или кнопки геймпада для действия (UI_SPEC: глифы в подсказках).
## Сама меняется, когда игрок переключается между клавиатурой и геймпадом (InputGlyphs).

const KEYCAP := preload("res://assets/ui/keycap.png")
const H := 13

@export var action: StringName:
	set(value):
		action = value
		_refresh()

var _text: String = ""
var _cap := StyleBoxTexture.new()


func _init(action_name: StringName = &"") -> void:
	action = action_name


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap.texture = KEYCAP
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_cap.set_texture_margin(side, 4)
	InputGlyphs.device_changed.connect(func(_g): _refresh())
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	_text = InputGlyphs.label(action)
	var font := get_theme_default_font()
	var w := maxf(font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 6, H)
	custom_minimum_size = Vector2(w, H)
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	if _text.is_empty():
		return
	var font := get_theme_default_font()
	var tw := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	if InputGlyphs.gamepad and _text.length() == 1 and _text in ["A", "B", "X", "Y"]:
		# Круглая цветная кнопка геймпада.
		var c := Vector2(6.5, 6.5)
		for y in H:
			for x in H:
				var d := Vector2(x, y).distance_to(c)
				if d <= 6.5:
					draw_rect(Rect2(x, y, 1, 1), Color("1e1614") if d > 5.5 else InputGlyphs.pad_color(_text))
		draw_string(font, Vector2(3, 10), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("f4f2ec"))
		return
	draw_style_box(_cap, Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(floorf((size.x - tw) / 2.0), 9), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("e6d6b0"))
