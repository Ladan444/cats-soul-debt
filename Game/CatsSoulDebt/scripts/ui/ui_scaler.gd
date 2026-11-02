class_name UIScaler
extends Control
## Корень интерфейса: всё внутри рисуется в «UI-пикселях» и масштабируется целым числом,
## чтобы пиксель-арт не расплывался. Базовый холст при ×3 и 1080p — 640×360 (UI_SPEC, раздел 1).

## Желаемый масштаб (настройка «Масштаб интерфейса»: 2, 3 или 4).
@export var ui_scale: int = 3:
	set(value):
		ui_scale = value
		_fit()
## Меньший холст, на котором содержимое ещё помещается (у книги — больше базового):
## масштаб уменьшается, чтобы окно не вылезало за экран при «Масштабе интерфейса» ×4.
## По умолчанию — под самое большое обычное окно (настройки 380×258): на 720p выйдет ×2 (640×360),
## на 1080p — до ×4 (480×270).
@export var min_canvas: Vector2 = Vector2(400, 264):
	set(value):
		min_canvas = value
		_fit()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ui_scale = Settings.get_value("ui_scale")
	Settings.changed.connect(func(key):
		if key == "ui_scale":
			ui_scale = Settings.get_value("ui_scale"))
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	# Не больше, чем помещается: холст должен быть хотя бы min_canvas UI-пикселей.
	var max_fit := maxi(1, int(minf(vp.x / min_canvas.x, vp.y / min_canvas.y)))
	var s := clampi(ui_scale, 1, max_fit)
	scale = Vector2(s, s)
	position = Vector2.ZERO
	size = (vp / s).floor()
