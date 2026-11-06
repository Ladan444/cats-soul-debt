class_name MenuPlate
extends Button
## Пункт главного меню (макет menu_v2): плашка 104×28 в трёх состояниях, у выбранного слева коготь с качанием ±1 px.
## Наведение мышью = фокус, как у ClawButton, — клавиатура, геймпад и мышь ведут себя одинаково.

const NORMAL := preload("res://assets/ui/menu2/pl_normal.png")
const SELECTED := preload("res://assets/ui/menu2/pl_selected.png")
const DOWN := preload("res://assets/ui/menu2/pl_down.png")
const CLAW := preload("res://assets/ui/menu2/claw.png")

var _claw: TextureRect
var _time := 0.0


func _init(label: String = "") -> void:
	text = label


func _ready() -> void:
	custom_minimum_size = Vector2(104, 28)
	focus_mode = Control.FOCUS_ALL
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_style("normal", NORMAL, 0)
	_style("disabled", NORMAL, 0)
	_style("hover", SELECTED, 0)
	_style("focus", SELECTED, 0)
	_style("pressed", DOWN, 2)
	_style("hover_pressed", DOWN, 2)
	var normal := Color("dcc89a")
	var on := Color("ebdcb8")
	add_theme_color_override("font_color", normal)
	for c in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(c, on)
	add_theme_color_override("font_disabled_color", Color("7a6a55"))
	add_theme_color_override("font_shadow_color", Color("140c08"))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)
	_claw = TextureRect.new()
	_claw.texture = CLAW
	_claw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_claw.visible = false
	_claw.size = CLAW.get_size()
	add_child(_claw)
	mouse_entered.connect(func(): if not disabled: grab_focus())
	focus_entered.connect(func(): _claw.visible = true)
	focus_exited.connect(func(): _claw.visible = false)


func _style(state: String, tex: Texture2D, top: int) -> void:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.content_margin_top = top
	add_theme_stylebox_override(state, s)


func _process(delta: float) -> void:
	if _claw.visible:
		_time += delta
		_claw.position = Vector2(CLAW.get_width() * -1 + 7 + roundf(sin(_time * 2.6)), floorf((size.y - CLAW.get_height()) / 2.0))
