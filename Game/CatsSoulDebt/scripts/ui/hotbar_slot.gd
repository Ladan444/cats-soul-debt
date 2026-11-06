class_name HotbarSlot
extends Control
## Ячейка хотбара 26×26 (новый HUD, макет «Красивый HUD»): рама в 4 состояниях (обычная, наведение, нажатие,
## вспышка использования), под иконкой 20×20 — пергаментная карточка, пустая ячейка — гнездо, затемнение,
## перезарядка с секундами, счётчик; подпись клавиши — под ячейкой (спрайт tag_<клавиша> или крошечный шрифт).
## Нажимается мышью и касанием (сигнал pressed).

signal pressed

const SIZE := Vector2(26, 26)

var icon: Texture2D:
	set(value):
		icon = value
		queue_redraw()
var key_text: String = "":
	set(value):
		key_text = value
		queue_redraw()
## Номер ячейки 0..7 (карточка под иконкой разная) и вид — скилл или предмет (гнездо у пустой).
var index: int = 0
var is_skill: bool = true
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
## Сколько секунд осталось (для подписи на перезарядке); 0 — подпись считается по доле.
var cooldown_secs: float = 0.0
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
var _down: bool = false
var _shake: float = 0.0


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	clickable = clickable
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		_down = false
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	# Касание приходит сюда как эмулированная левая кнопка мыши.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_down = event.pressed
		queue_redraw()
		if event.pressed:
			pressed.emit()
			accept_event()


## Короткая подсветка при использовании.
func pulse() -> void:
	_pulse = 1.0


## Дрожание: «нельзя» (не хватает энергии, перезарядка).
func deny() -> void:
	_shake = 1.0


func _process(delta: float) -> void:
	if _pulse > 0.0 or _shake > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 4.0)
		_shake = maxf(0.0, _shake - delta * 5.0)
		queue_redraw()


func _frame_name() -> String:
	if _pulse > 0.0:
		return "slot_flash"
	if _down:
		return "slot_pressed"
	if _hover:
		return "slot_hover"
	return "slot_normal"


func _draw() -> void:
	var off := Vector2(roundf(sin(_shake * 24.0) * 2.0 * _shake), 0)
	var win := Vector2(3, 3) + off
	if icon:
		draw_texture(HudAtlas.tex("card%d" % clampi(index, 0, 7)), win)
		draw_texture(icon, win + Vector2(0, 1 if _down else 0), Color(1, 1, 1, 0.45) if count == 0 else Color.WHITE)
	else:
		draw_texture(HudAtlas.tex("sock_skill" if is_skill else "sock_item"), win)
	if dimmed:
		draw_rect(Rect2(win, Vector2(20, 20)), Color(0.08, 0.05, 0.09, 0.65))
	if cooldown > 0.0:
		var h := ceilf(20.0 * cooldown)
		draw_rect(Rect2(win.x, win.y + 20.0 - h, 20, h), Color(0.07, 0.04, 0.03, 0.76))
		draw_rect(Rect2(win.x, win.y + 20.0 - h, 20, 1), Color("e8c870"))
		var secs := str(maxi(1, int(ceilf(cooldown_secs)))) if cooldown_secs > 0.0 else str(maxi(1, roundi(cooldown * 6.0)))
		var tw := TinyFont.width(secs)
		TinyFont.draw_badge(self, secs, Vector2(floorf(13.0 - tw / 2.0) - 1.0, 10.0), Color("f4f2ec"))
	draw_texture(HudAtlas.tex(_frame_name()), Vector2.ZERO)
	_draw_key()
	if count >= 0:
		var t := str(count)
		TinyFont.draw_badge(self, t, Vector2(22 - TinyFont.width(t) - 1, 16), Color.WHITE)


## Подпись клавиши под ячейкой: готовый спрайт для Q R F C 1–4, для остального (кнопки геймпада) — крошечный шрифт.
func _draw_key() -> void:
	if key_text.is_empty():
		return
	var tag := "tag_" + key_text
	if HudAtlas.has(tag):
		var t := HudAtlas.tex(tag)
		draw_texture(t, Vector2(floorf((SIZE.x - t.get_width()) / 2.0), SIZE.y - 3.0))
	else:
		var w := TinyFont.width(key_text)
		TinyFont.draw_badge(self, key_text, Vector2(floorf((SIZE.x - w) / 2.0) - 1.0, SIZE.y - 3.0), Color("e6d6b0"))
