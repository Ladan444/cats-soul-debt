class_name RoundButton
extends Button
## Круглая кнопка меню 24×24 нового HUD (книга / карта / меню): рама в 3 состояниях, значок по центру, маленькая подпись
## клавиши наезжает на кнопку снизу на 3 пикселя. Для мыши и касания: фокус не берёт, чтобы не мешать клавиатуре и геймпаду.

const SIZE := Vector2(24, 24)

var icon_name: String
var tag_name: String


## icon_name — спрайт значка в hud_atlas (ic_book / ic_map / ic_gear), tag_name — подпись клавиши (tag_TAB / tag_M / tag_ESC).
func _init(icon_sprite: String = "", tag_sprite: String = "", tip: String = "") -> void:
	icon_name = icon_sprite
	tag_name = tag_sprite
	tooltip_text = tip


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	custom_minimum_size = SIZE
	size = SIZE
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var down := get_draw_mode() in [DRAW_PRESSED, DRAW_HOVER_PRESSED]
	var state := "pressed" if down else ("hover" if is_hovered() else "normal")
	draw_texture(HudAtlas.tex("mbtn_" + state), Vector2.ZERO)
	if icon_name != "":
		var t := HudAtlas.tex(icon_name)
		draw_texture(t, Vector2(floorf((SIZE.x - t.get_width()) / 2.0), floorf((SIZE.y - t.get_height()) / 2.0) + (1 if down else 0)))
	if tag_name != "" and HudAtlas.has(tag_name):
		var g := HudAtlas.tex(tag_name)
		draw_texture(g, Vector2(floorf((SIZE.x - g.get_width()) / 2.0), SIZE.y - 3.0))
