class_name PixelBar
extends Control
## Полоса HP/энергии в пиксельной рамке. При уменьшении «съеденная» часть светлеет и догоняет.

const FRAME := preload("res://assets/ui/bar_frame.png")
const INSET := 2

@export var fill_color: Color = Color("b23a3a")
@export var shade_color: Color = Color("6e2024")
@export var trail_color: Color = Color("f0d8b0")
## Скорость, с которой след догоняет значение (доля полосы в секунду).
@export var trail_speed: float = 0.8

var ratio: float = 1.0
var _trail: float = 1.0
var _flash: float = 0.0
var _frame := StyleBoxTexture.new()


func _ready() -> void:
	_frame.texture = FRAME
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_frame.set_texture_margin(side, 3)
	_frame.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_ratio(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if value > _trail:
		_trail = value
	ratio = value
	queue_redraw()


## Короткая вспышка — например, когда не хватает энергии.
func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	var changed := false
	if _trail > ratio:
		_trail = maxf(ratio, _trail - trail_speed * delta)
		changed = true
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		changed = true
	if changed:
		queue_redraw()


func _draw() -> void:
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	var inner := Rect2(Vector2(INSET, INSET), size - Vector2(INSET, INSET) * 2)
	var trail_w := floorf(inner.size.x * _trail)
	var fill_w := floorf(inner.size.x * ratio)
	if trail_w > fill_w:
		draw_rect(Rect2(inner.position + Vector2(fill_w, 0), Vector2(trail_w - fill_w, inner.size.y)), trail_color)
	if fill_w > 0:
		var fill := fill_color.lerp(Color.WHITE, _flash * 0.6)
		draw_rect(Rect2(inner.position, Vector2(fill_w, inner.size.y)), fill)
		draw_rect(Rect2(inner.position, Vector2(fill_w, 1)), fill.lightened(0.3))
		draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 1), Vector2(fill_w, 1)), shade_color)
	# Деления каждые 10 % — как зарубки на планке.
	for i in range(1, 10):
		var x := inner.position.x + floorf(inner.size.x * i / 10.0)
		draw_rect(Rect2(x, inner.position.y + 1, 1, inner.size.y - 2), Color(0, 0, 0, 0.25))
