shader_type canvas_item;
// Фон паузы: размытый и затемнённый кадр игры (UI_SPEC, раздел 5).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod = 2.5;
uniform vec4 tint : source_color = vec4(0.06, 0.035, 0.025, 0.55);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}
