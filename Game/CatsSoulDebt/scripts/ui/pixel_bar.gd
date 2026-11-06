class_name PixelBar
extends Control
## Полоса HP/энергии нового HUD: рама с остриём (спрайт bar_hp / bar_en), внутри окно 6 рядов цвета с насечками
## каждые 10 %. При уменьшении «съеденная» часть светлеет и догоняет. Ширина кадра 100: рама 96 + остриё;
## у полосы энергии остриё слева (tip_left), её спрайт сдвинут на 4 влево от начала полосы.

const BODY_W := 96
const INSET := 2
const ROWS := 6

@export var kind: String = "hp"
@export var tip_left: bool = false
## Скорость, с которой след догоняет значение (доля полосы в секунду).
@export var trail_speed: float = 0.8

var ratio: float = 1.0
var _trail: float = 1.0
var _flash: float = 0.0

const TONES_HP := ["f0716a", "e05a58", "b23a3a", "b23a3a", "8f2a2e", "6e2024"]
const TONES_EN := ["bff4ee", "8fd8d0", "74c8c4", "5aaeb0", "46929a", "3e7e86"]
const EMPTY_HP := Color("240c0d")
const EMPTY_EN := Color("0c1e22")
const TRAIL_HP := Color("f0d8b0")
const TRAIL_EN := Color("e8fffb")


func _ready() -> void:
	custom_minimum_size = Vector2(100, 10)
	size = Vector2(100, 10)
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
	var hp := kind == "hp"
	var tones: Array = TONES_HP if hp else TONES_EN
	var empty: Color = EMPTY_HP if hp else EMPTY_EN
	# Тело полосы лежит в первых 96 px спрайта (у энергии — со сдвигом на остриё слева).
	var body_x := 4.0 if tip_left else 0.0
	var ix := body_x + INSET
	var iw := float(BODY_W - 2 * INSET)
	draw_rect(Rect2(ix, INSET, iw, ROWS), empty)
	var fw := floorf(iw * ratio)
	var tw := floorf(iw * _trail)
	if tw > fw:
		draw_rect(Rect2(ix + fw, INSET, tw - fw, ROWS), TRAIL_HP if hp else TRAIL_EN)
	for j in ROWS:
		var c := Color(tones[j])
		if _flash > 0.0:
			c = c.lerp(Color.WHITE, _flash * 0.6)
		draw_rect(Rect2(ix, INSET + j, fw, 1), c)
	if fw > 0.0:
		draw_rect(Rect2(ix + fw - 1, INSET, 1, ROWS), Color(tones[0]))
	for k in range(1, 10):
		draw_rect(Rect2(ix + floorf(iw * k / 10.0), INSET + 1, 1, ROWS - 2), Color(0, 0, 0, 0.28))
	draw_texture(HudAtlas.tex("bar_hp" if hp else "bar_en"), Vector2.ZERO)
