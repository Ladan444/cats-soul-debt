class_name InventorySlot
extends Button
## Ячейка меню персонажа 22×22 (фокусируемая): иконка, счётчик, отметка «надето»,
## бледный силуэт для пустого слота экипировки. Наведение мышью = выбор.

const SLOT := preload("res://assets/ui/slot.png")
const SLOT_SELECTED := preload("res://assets/ui/slot_selected.png")
const SIZE := Vector2(22, 22)

var icon_tex: Texture2D:
	set(value):
		icon_tex = value
		queue_redraw()
## Силуэт, если ячейка пуста (слоты экипировки).
var placeholder: Texture2D
var count: int = -1:
	set(value):
		count = value
		queue_redraw()
var equipped: bool = false:
	set(value):
		equipped = value
		queue_redraw()
var dimmed: bool = false:
	set(value):
		dimmed = value
		queue_redraw()
## Любые данные, которые показывает ячейка (ItemData, SoulData, имя слота...).
var payload: Variant


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = SIZE
	size = SIZE
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(grab_focus)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	draw_texture(SLOT_SELECTED if has_focus() else SLOT, Vector2.ZERO)
	var tex := icon_tex if icon_tex else placeholder
	if tex:
		var pos := ((SIZE - tex.get_size()) / 2.0).floor()
		var color := Color.WHITE
		if icon_tex == null:
			color = Color(0.25, 0.18, 0.12, 0.3)  # силуэт пустого слота
		elif dimmed:
			color = Color(1, 1, 1, 0.4)
		draw_texture(tex, pos, color)
	if equipped:
		# Латунная скрепка в углу — «надето».
		draw_rect(Rect2(16, 2, 4, 4), Color("2e1d14"))
		draw_rect(Rect2(17, 3, 2, 2), Color("e8c870"))
	if count > 1 or count == 0:
		var t := str(count)
		TinyFont.draw_badge(self, t, Vector2(20 - TinyFont.width(t) - 2, 20 - TinyFont.HEIGHT - 2), Color.WHITE)
