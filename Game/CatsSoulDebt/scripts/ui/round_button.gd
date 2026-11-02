class_name RoundButton
extends Button
## Круглая деревянная кнопка 22×22 с иконкой 10×10 и картинкой клавиши под ней (кнопки меню в HUD).
## Для мыши и касания: фокус не берёт, чтобы не мешать клавиатуре и геймпаду.

const TEX := preload("res://assets/ui/wood_button.png")
const TEX_PRESSED := preload("res://assets/ui/wood_button_pressed.png")
const SIZE := Vector2(22, 22)

var icon_tex: Texture2D
var _glyph: KeyGlyph


func _init(icon_texture: Texture2D = null, action: StringName = &"", tip: String = "") -> void:
	icon_tex = icon_texture
	tooltip_text = tip
	_glyph = KeyGlyph.new(action)


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	custom_minimum_size = SIZE
	size = SIZE
	add_child(_glyph)
	_glyph.resized.connect(_place_glyph)
	_place_glyph()
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _place_glyph() -> void:
	_glyph.position = Vector2(floorf((SIZE.x - _glyph.size.x) / 2.0), SIZE.y - 3)


func _draw() -> void:
	var down := get_draw_mode() in [DRAW_PRESSED, DRAW_HOVER_PRESSED]
	# Наведение — дерево светлеет, чтобы кнопку было видно на тёмной сцене.
	draw_texture(TEX_PRESSED if down else TEX, Vector2.ZERO, Color(1.25, 1.2, 1.1) if is_hovered() and not down else Color.WHITE)
	if icon_tex:
		var pos := ((SIZE - icon_tex.get_size()) / 2.0).floor() + Vector2(0, 1 if down else 0)
		draw_texture(icon_tex, pos)
