class_name MenuScene
extends Control
## Живая сцена главного меню (макет «menu_v2»): ночная крепость над озером. Холст 640×360: картинка 1920×1080 с линейным
## фильтром, поверх — туман (шейдер, две полосы с маской), мерцающие звёзды, блики на воде и окно таверны.
## Раскладка эффектов — data/main_menu_fx.json (из макета: stars [x,y], glints [x,y,w,вид,фаза,скорость]).

const SCENE := preload("res://assets/ui/menu2/scene.png")
const FOG_A := preload("res://assets/ui/menu2/fog_a.png")
const FOG_B := preload("res://assets/ui/menu2/fog_b.png")
const FOG_MASK := preload("res://assets/ui/menu2/fog_mask.png")
const GLINT := {"t": Color(0.55, 0.85, 0.85), "v": Color(0.62, 0.55, 0.9), "o": Color(1.0, 0.68, 0.35)}
const SHADER := """
shader_type canvas_item;
uniform sampler2D fog_a : repeat_enable, filter_nearest;
uniform sampler2D fog_b : repeat_enable, filter_nearest;
uniform sampler2D mask : filter_nearest;
uniform float t;
void fragment() {
	vec2 px = floor(UV * vec2(640.0, 360.0));
	vec4 c = vec4(0.0);
	if (px.y >= 170.0 && px.y < 234.0) {
		vec4 a = texture(fog_a, vec2((px.x + floor(t * 2.2)) / 320.0, (px.y - 170.0) / 64.0));
		c = a;
	}
	if (px.y >= 214.0 && px.y < 324.0) {
		vec4 b = texture(fog_b, vec2((px.x - floor(t * 3.6)) / 320.0, (px.y - 214.0) / 110.0));
		c = c + b * (1.0 - c.a);
	}
	c.a *= texture(mask, UV).a;
	COLOR = c;
}
"""

var _fx: Dictionary = {}
var _clock := 0.0
var _fog: ColorRect
var _top: Control


func _ready() -> void:
	size = Vector2(640, 360)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := FileAccess.open("res://data/main_menu_fx.json", FileAccess.READ)
	if f:
		_fx = JSON.parse_string(f.get_as_text())
	var pic := TextureRect.new()
	pic.texture = SCENE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.size = size
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pic)
	_fog = ColorRect.new()
	_fog.size = size
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("fog_a", FOG_A)
	mat.set_shader_parameter("fog_b", FOG_B)
	mat.set_shader_parameter("mask", FOG_MASK)
	_fog.material = mat
	add_child(_fog)
	_top = Control.new()
	_top.size = size
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.draw.connect(_draw_top)
	add_child(_top)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	(_fog.material as ShaderMaterial).set_shader_parameter("t", _clock)
	_top.queue_redraw()


func _draw_top() -> void:
	var t := _clock
	var stars: Array = _fx.get("stars", [])
	for i in stars.size():
		var a := maxf(0.0, sin(t * (0.7 + (i % 5) * 0.23) + i * 2.4))
		_top.draw_rect(Rect2(stars[i][0], stars[i][1], 1, 1), Color(0.91, 0.94, 0.91, a * 0.85))
	for g in _fx.get("glints", []):
		var a := maxf(0.0, sin(t * float(g[5]) + float(g[4])))
		if a <= 0.02:
			continue
		var dx := roundf(sin(t * 0.5 + float(g[4])) * 2.0)
		var col: Color = GLINT[str(g[3])]
		col.a = a * (0.6 if g[3] == "o" else 0.5)
		_top.draw_rect(Rect2(float(g[0]) + dx - floorf(float(g[2]) / 2.0), g[1], g[2], 1), col)
	# Окно таверны: мерцание и ореол (складывается с картинкой).
	var f := 0.5 + 0.3 * sin(t * 6.1) + 0.2 * sin(t * 13.7 + 1.0)
	_top.draw_rect(Rect2(408, 194, 15, 17), Color(1.0, 0.667, 0.314, 0.03 + 0.05 * f))
	_top.draw_rect(Rect2(412, 198, 7, 9), Color(1.0, 0.69, 0.345, 0.08 + 0.2 * f))
