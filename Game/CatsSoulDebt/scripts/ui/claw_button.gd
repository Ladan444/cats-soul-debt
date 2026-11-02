class_name ClawButton
extends Button
## Пункт меню: текст без рамки, у выбранного — латунный «коготь» слева, слегка покачивается.
## Наведение мышью = выбор (фокус), поэтому клавиатура, геймпад и мышь ведут себя одинаково.

const CLAW := preload("res://assets/ui/claw.png")
const INDENT := 12

## true — пункт на пергаменте (тёмные чернила), false — на тёмном фоне (светлый текст).
@export var on_parchment: bool = false

var _time: float = 0.0


func _init(label: String = "", parchment: bool = false) -> void:
	text = label
	on_parchment = parchment


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size.y = 12
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = INDENT
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, empty)
	var normal := Color("2a1e18") if on_parchment else Color("e6d6b0")
	var active := Color("3f6a4a") if on_parchment else Color("e8c870")
	add_theme_color_override("font_color", normal)
	add_theme_color_override("font_hover_color", active)
	add_theme_color_override("font_focus_color", active)
	add_theme_color_override("font_pressed_color", active)
	add_theme_color_override("font_hover_pressed_color", active)
	add_theme_color_override("font_disabled_color", Color("9a8a6a") if on_parchment else Color("7a6a55"))
	if not on_parchment:
		add_theme_color_override("font_outline_color", Color("2a1e18"))
		add_theme_constant_override("outline_size", 2)
	mouse_entered.connect(func(): if not disabled: grab_focus())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _process(delta: float) -> void:
	if has_focus():
		_time += delta
		queue_redraw()


func _draw() -> void:
	if has_focus():
		var sway := roundf(sin(_time * 5.0))
		draw_texture(CLAW, Vector2(1 + sway, floorf((size.y - CLAW.get_height()) / 2.0)))
