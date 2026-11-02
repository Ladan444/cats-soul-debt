class_name HotbarSlot
extends Control
## Ячейка хотбара 24×24: иконка, клавиша в углу, перезарядка, счётчик, затемнение.
## Нажимается мышью и касанием (сигнал pressed) — для тех, кому проще, чем учить клавиши.

signal pressed

const SLOT := preload("res://assets/ui/hot_slot.png")
const SLOT_SELECTED := preload("res://assets/ui/hot_slot_selected.png")
const SIZE := Vector2(24, 24)

var icon: Texture2D:
	set(value):
		icon = value
		queue_redraw()
var key_text: String = "":
	set(value):
		key_text = value
		queue_redraw()
## -1 — счётчик не показывается (у скиллов).
var count: int = -1:
	set(value):
		count = value
		queue_redraw()
## 0..1 — какая доля перезарядки осталась.
var cooldown: float = 0.0:
	set(value):
		cooldown = value
		queue_redraw()
var dimmed: bool = false:
	set(value):
		dimmed = value
		queue_redraw()

## false — ячейка не ловит мышь (хотбар спрятан в хабе).
var clickable: bool = true:
	set(value):
		clickable = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		_hover = _hover and value
		queue_redraw()

var _pulse: float = 0.0
var _hover: bool = false


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	clickable = clickable
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	# Касание приходит сюда как эмулированная левая кнопка мыши.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed.emit()
		accept_event()


## Короткая подсветка при использовании.
func pulse() -> void:
	_pulse = 1.0


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 4.0)
		queue_redraw()


func _draw() -> void:
	draw_texture(SLOT_SELECTED if _pulse > 0.0 or _hover else SLOT, Vector2.ZERO)
	if icon:
		var pos := ((SIZE - icon.get_size()) / 2.0).floor()
		draw_texture(icon, pos, Color(1, 1, 1, 0.45) if count == 0 else Color.WHITE)
	# Вся пергаментная часть ячейки (вместе с её тенью) — см. slot() в Tools/ui_atlas.py.
	var inner := Rect2(3, 3, 18, 18)
	if dimmed:
		draw_rect(inner, Color(0.12, 0.07, 0.05, 0.55))
	if cooldown > 0.0:
		var h := ceilf(inner.size.y * cooldown)
		draw_rect(Rect2(inner.position.x, inner.end.y - h, inner.size.x, h), Color(0.12, 0.07, 0.05, 0.7))
	if not key_text.is_empty():
		TinyFont.draw_badge(self, key_text, Vector2(2, 2), Color("e6d6b0"))
	if count >= 0:
		var t := str(count)
		TinyFont.draw_badge(self, t, Vector2(SIZE.x - TinyFont.width(t) - 3, SIZE.y - TinyFont.HEIGHT - 3), Color.WHITE)
